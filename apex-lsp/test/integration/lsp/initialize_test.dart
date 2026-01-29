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
  group('LSP Initialization', () {
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

    test('client can initialize', () async {
      final serverTask = server.run();

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

      await input.close();
      await serverTask.timeout(const Duration(seconds: 2));
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

    test('receives indexing updates after initialization', () async {
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

      // 2) initialized notification triggers indexing
      input.addFrame(jsonRpcNotification(method: 'initialized'));

      // 3) Wait for progress notifications ($/progress).
      // We expect at least 'begin' and 'end'.
      final beginProgress = await _waitForNotification(
        sink: sink,
        method: r'$/progress',
        predicate: (params) => (params['value'] as Map)['kind'] == 'begin',
        timeout: const Duration(seconds: 2),
      );
      expect(beginProgress, isNotNull);

      final endProgress = await _waitForNotification(
        sink: sink,
        method: r'$/progress',
        predicate: (params) => (params['value'] as Map)['kind'] == 'end',
        timeout: const Duration(seconds: 5),
      );
      expect(endProgress, isNotNull);

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

/// Waits until a JSON-RPC notification with [method] and matching [predicate] is
/// observed in [sink]'s frames.
Future<Map<String, Object?>> _waitForNotification({
  required InMemoryByteSink sink,
  required String method,
  required bool Function(Map<String, Object?> params) predicate,
  required Duration timeout,
}) async {
  return _pollFrames(
    sink: sink,
    timeout: timeout,
    predicate: (frame) {
      if (frame['method'] != method) return false;
      final params = frame['params'];
      return params is Map && predicate(params.cast<String, Object?>());
    },
    timeoutMessage: 'Timed out waiting for notification $method',
  );
}
