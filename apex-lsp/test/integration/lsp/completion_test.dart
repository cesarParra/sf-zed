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
  group('LSP Completion', () {
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

    test('completion includes indexed class name', () async {
      final serverTask = server.run();

      // 1) initialize
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
      await _waitForResponse(
        sink: sink,
        id: 1,
        timeout: const Duration(seconds: 2),
      );

      // 2) initialized notification
      input.addFrame(jsonRpcNotification(method: 'initialized'));

      // 3) Open a document with a prefix to complete.
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

      // 4) Poll completion until "Foo" (from indexing) is present.
      final completionResponse = await _pollCompletionUntilContains(
        input: input,
        sink: sink,
        docUri: docUri,
        expectedLabel: 'Foo',
        timeout: const Duration(seconds: 6),
      );

      expect(completionResponse['result'], isA<Map<String, Object?>>());
      final completionResult =
          completionResponse['result'] as Map<String, Object?>;
      final items = (completionResult['items'] as List<Object?>)
          .whereType<Map<Object?, Object?>>()
          .map((m) => m.cast<String, Object?>())
          .toList();

      expect(items.any((i) => i['label'] == 'Foo'), isTrue);

      await input.close();
      await serverTask.timeout(const Duration(seconds: 2));
    });
  });
}

/// Generic polling helper for LSP frames that handles timeouts and frame draining.
Future<Map<String, Object?>> _pollFrames({
  required InMemoryByteSink sink,
  required Duration timeout,
  required bool Function(Map<String, Object?> frame) predicate,
  FutureOr<void> Function()? onTick,
  String? timeoutMessage,
}) async {
  final deadline = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(deadline)) {
    final frames = sink.takeFrames();

    for (final frame in frames) {
      if (frame is Map) {
        final casted = frame.cast<String, Object?>();
        if (predicate(casted)) {
          return casted;
        }
      }
    }

    if (onTick != null) {
      await onTick();
    }

    // Allow time for async indexing and server loop to progress.
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }

  throw StateError(timeoutMessage ?? 'Timed out waiting for expected frame');
}

/// Waits until a JSON-RPC response with [id] is observed in [sink]'s frames.
Future<Map<String, Object?>> _waitForResponse({
  required InMemoryByteSink sink,
  required Object id,
  required Duration timeout,
}) async {
  return _pollFrames(
    sink: sink,
    timeout: timeout,
    predicate: (frame) => frame['id'] == id,
    timeoutMessage: 'Timed out waiting for response id=$id',
  );
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
  var requestId = 2;

  return _pollFrames(
    sink: sink,
    timeout: timeout,
    predicate: (frame) {
      // Ignore any non-completion frames and unrelated responses.
      if (frame['id'] is! int) return false;
      if ((frame['id'] as int) < 2) return false;

      final result = frame['result'];
      if (result is Map) {
        final items = result['items'];
        if (items is List) {
          return items.any((it) => it is Map && it['label'] == expectedLabel);
        }
      }
      return false;
    },
    onTick: () async {
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
    },
    timeoutMessage:
        'Timed out waiting for completion containing label=$expectedLabel',
  );
}
