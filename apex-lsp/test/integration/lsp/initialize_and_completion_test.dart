import 'dart:async';
import 'dart:io';

import 'package:apex_lsp/di.dart';
import 'package:apex_lsp/lsp_out.dart';
import 'package:apex_lsp/server.dart';
import 'package:test/test.dart';

import '../../support/lsp_test_harness.dart';

final class _ExitCalled implements Exception {
  _ExitCalled(this.code);
  final int code;

  @override
  String toString() => '_ExitCalled(code=$code)';
}

void main() {
  group('LSP integration', () {
    late Directory workspaceDir;
    late Uri workspaceUri;

    late InMemoryLspInput input;
    late InMemoryByteSink sink;
    late Server server;

    setUp(() async {
      // Create a temporary workspace.
      workspaceDir = await Directory.systemTemp.createTemp('apex-lsp-it-');
      workspaceUri = Uri.directory(workspaceDir.path);

      // Minimal SFDX project config (loaded from fixtures).
      final sfdxProject = File('${workspaceDir.path}/sfdx-project.json');
      final sfdxProjectFixture = File(
        'test/fixtures/initialize_and_completion/sfdx-project.json',
      );
      await sfdxProject.writeAsString(await sfdxProjectFixture.readAsString());

      // Create an Apex class under the typical SFDX path.
      final classesDir = Directory(
        '${workspaceDir.path}/force-app/main/default/classes',
      );
      await classesDir.create(recursive: true);

      final fooClass = File('${classesDir.path}/Foo.cls');
      final fooClassFixture = File(
        'test/fixtures/initialize_and_completion/Foo.cls',
      );
      await fooClass.writeAsString(await fooClassFixture.readAsString());

      // Inject an ExitFn that throws instead of terminating the process.
      locator.registerFactory<ExitFn>(
        () =>
            (code) => throw _ExitCalled(code),
      );

      input = InMemoryLspInput(sync: true);
      sink = InMemoryByteSink();

      locator.registerSingleton<LspOut>(LspOut(output: sink));

      // Ensure production (non-overridden) dependencies are initialized.
      initializeDependencies();

      server = Server(input: input.stream);
    });

    tearDown(() async {
      await input.close();
      await workspaceDir.delete(recursive: true);
      await locator.reset(dispose: true);
    });

    test(
      'fails with error response when request sent before initialize',
      () async {
        final serverTask = server.run();

        // Send a request before `initialize`. The server should respond with an
        // LSP ServerNotInitialized error.
        input.addFrame(
          jsonRpcRequest(
            id: 1,
            method: 'textDocument/completion',
            params: <String, Object?>{
              'textDocument': <String, Object?>{
                'uri': 'file:///does/not/matter',
              },
              'position': <String, Object?>{'line': 0, 'character': 0},
            },
          ),
        );

        final errorResponse = await _waitForResponse(
          sink: sink,
          id: 1,
          timeout: const Duration(seconds: 2),
        );

        expect(errorResponse['jsonrpc'], equals('2.0'));
        expect(errorResponse['id'], equals(1));
        expect(errorResponse['error'], isA<Map<String, Object?>>());

        final error = errorResponse['error'] as Map<String, Object?>;
        expect(error['code'], equals(-32002));
        expect(error['message'], equals('Server not initialized'));

        await input.close();
        await serverTask.timeout(const Duration(seconds: 2));
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );

    test(
      'client can initialize, server indexes workspace, and completion includes indexed class name',
      () async {
        final serverTask = server.run();

        // 1) initialize request w/ workspaceFolders.
        // NOTE: the server's InitializeRequest model expects "workspaceFolders"
        // under params (or absent/null).
        input.addFrame(
          jsonRpcInitialize(
            id: 1,
            workspaceFolders: <Map<String, String>>[
              <String, String>{
                'uri': workspaceUri.toString(),
                'name': 'workspace',
              },
            ],
          ),
        );

        // 2) initialized notification triggers background indexing.
        input.addFrame(jsonRpcNotification(method: 'initialized'));

        // 3) Open a document with a prefix to complete.
        // Completion uses the *open document text* to extract the prefix.
        final docUri = workspaceUri
            .resolve('force-app/main/default/classes/SomeFile.cls')
            .toString();

        input.addFrame(
          jsonRpcNotification(
            method: 'textDocument/didOpen',
            params: <String, Object?>{
              'textDocument': <String, Object?>{
                'uri': docUri,
                'text': 'public class SomeFile { void m(){ Fo } }',
              },
            },
          ),
        );

        // 4) Request completion at the cursor right after "Fo".
        //
        // IMPORTANT:
        // Completion prefix extraction uses the open document text and splits on '\n'.
        // Character is treated as a (clamped) string index in that line.
        //
        // In the string below:
        //   'public class SomeFile { void m(){ Fo } }'
        // the "Fo" starts at index 34 and ends at index 36.
        // We want the cursor positioned after "Fo", so character=36.
        input.addFrame(
          jsonRpcRequest(
            id: 2,
            method: 'textDocument/completion',
            params: <String, Object?>{
              'textDocument': <String, Object?>{'uri': docUri},
              'position': <String, Object?>{'line': 0, 'character': 36},
            },
          ),
        );

        // Wait for at least the initialize response.
        final initResponse = await _waitForResponse(
          sink: sink,
          id: 1,
          timeout: const Duration(seconds: 2),
        );

        expect(initResponse['jsonrpc'], equals('2.0'));
        expect(initResponse['id'], equals(1));
        expect(initResponse['result'], isA<Map<String, Object?>>());

        final result = initResponse['result'] as Map<String, Object?>;
        expect(result['capabilities'], isA<Map<String, Object?>>());
        final caps = result['capabilities'] as Map<String, Object?>;
        expect(caps['textDocumentSync'], equals(1));
        expect(caps['completionProvider'], isA<Map<String, Object?>>());

        // Completion may be empty if indexing hasn't finished yet. Keep sending
        // completion requests until indexing populates the completion index and
        // we see "Foo" in the results.
        final completionResponse = await _pollCompletionUntilContains(
          input: input,
          sink: sink,
          docUri: docUri,
          expectedLabel: 'Foo',
          timeout: const Duration(seconds: 6),
        );

        expect(completionResponse['jsonrpc'], equals('2.0'));
        expect(completionResponse['id'], isA<int>());
        expect((completionResponse['id'] as int) >= 2, isTrue);
        expect(completionResponse['result'], isA<Map<String, Object?>>());

        final completionResult =
            completionResponse['result'] as Map<String, Object?>;
        expect(completionResult['isIncomplete'], isFalse);
        expect(completionResult['items'], isA<List<Object?>>());

        final items = (completionResult['items'] as List<Object?>)
            .whereType<Map<Object?, Object?>>()
            .map((m) => m.cast<String, Object?>())
            .toList();

        expect(items.any((i) => i['label'] == 'Foo'), isTrue);

        // Close input and wait for the server loop to finish (it will finish
        // once the stream closes).
        await input.close();
        await serverTask.timeout(const Duration(seconds: 2));
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });
}

/// Waits until a JSON-RPC response with [id] is observed in [sink]'s frames.
Future<Map<String, Object?>> _waitForResponse({
  required InMemoryByteSink sink,
  required Object id,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(deadline)) {
    final frames = sink.takeFrames();

    for (final frame in frames) {
      if (frame is! Map) continue;
      if (frame['id'] == id) {
        return frame.cast<String, Object?>();
      }
    }

    // Allow time for async indexing and server loop to progress.
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }

  throw StateError('Timed out waiting for response id=$id');
}

/// Continuously sends completion requests and waits for a response that contains
/// [expectedLabel].
///
/// This is more robust than waiting on a single completion response because
/// indexing happens in the background and there is no guarantee the first
/// completion request will be answered after indexing completes.
///
/// NOTE: Each completion request uses a *new* request id. We accept whichever
/// id yields the expected label.
Future<Map<String, Object?>> _pollCompletionUntilContains({
  required InMemoryLspInput input,
  required InMemoryByteSink sink,
  required String docUri,
  required String expectedLabel,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);

  var requestId = 2;
  while (DateTime.now().isBefore(deadline)) {
    // Drain any frames currently available (so we don't miss responses).
    final frames = sink.takeFrames();

    for (final frame in frames) {
      if (frame is! Map) continue;

      // Ignore any non-completion frames and unrelated responses.
      if (frame['id'] is! int) continue;
      if ((frame['id'] as int) < 2) continue;

      final result = frame['result'];
      if (result is Map) {
        final items = result['items'];
        if (items is List) {
          final has = items.any(
            (it) => it is Map && it['label'] == expectedLabel,
          );
          if (has) {
            return frame.cast<String, Object?>();
          }
        }
      }
    }

    // Send another completion request with a new ID.
    requestId++;
    input.addFrame(
      jsonRpcRequest(
        id: requestId,
        method: 'textDocument/completion',
        params: <String, Object?>{
          'textDocument': <String, Object?>{'uri': docUri},
          'position': <String, Object?>{'line': 0, 'character': 36},
        },
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  throw StateError(
    'Timed out waiting for completion containing label=$expectedLabel',
  );
}
