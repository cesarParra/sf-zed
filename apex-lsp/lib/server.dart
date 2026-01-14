import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apex_lsp/documents/open_documents.dart';
import 'package:get_it/get_it.dart';

import 'indexing/indexer.dart';
import 'init/initialization.dart';
import 'init/sfdx_workspace_locator.dart';
import 'lsp_out.dart';
import 'message.dart';
import 'message_reader.dart';

typedef ExitFn = Never Function(int exitCode);

final class Server {
  factory Server({required Stream<List<int>> input}) =>
      Server._(input: input, locator: GetIt.I);

  Server._({required Stream<List<int>> input, required GetIt locator})
    : _output = locator<LspOut>(),
      _reader = MessageReader(input),
      _sfdxWorkspaceLocator = locator<SfdxWorkspaceLocator>(),
      _indexer = locator<ApexIndexer>(),
      _exitFn = locator<ExitFn>(),
      _openDocuments = OpenDocuments();

  final LspOut _output;
  final MessageReader _reader;

  final SfdxWorkspaceLocator _sfdxWorkspaceLocator;
  final ApexIndexer _indexer;
  final ExitFn _exitFn;

  final OpenDocuments _openDocuments;

  bool _initialized = false;
  bool _shutdownRequested = false;
  bool _exiting = false;

  // Workspace roots discovered during initialize.
  List<Uri> _workspaceRootUris = const <Uri>[];

  // Source-of-truth index scope: all package directories across workspace roots.
  List<Uri> _packageDirectoryUris = const <Uri>[];

  // Token used to report work-done progress for indexing.
  ProgressToken? _indexingProgressToken;

  Future<void>? _indexingTask;

  // Minimal in-memory completion index derived from `.sf-zed/*.json`.
  // Top-level for now: just known class names.
  final Set<String> _indexedClassNames = <String>{};

  Future<void> logMessage(MessageType type, String message) async {
    if (!_initialized) return;
    await _output.logMessage(type, message);
  }

  Future<void> run() async {
    await for (final message in _reader.messages()) {
      if (_exiting) break;

      switch (message) {
        case RequestMessage():
          await _handleRequest(message);
        case IncomingNotificationMessage():
          await _handleNotification(message);
      }
    }
  }

  Future<void> _handleRequest(RequestMessage req) async {
    if (!_initialized &&
        req.method != 'initialize' &&
        req.method != 'shutdown') {
      await _output.sendError(
        id: req.id,
        code: -32002, // ServerNotInitialized (LSP)
        message: 'Server not initialized',
      );
      return;
    }

    switch (req) {
      case InitializeRequest():
        await _onInitialize(req);
      case ShutdownRequest():
        _shutdownRequested = true;
        await _output.sendResponse(id: req.id, result: null);
      case CompletionRequest(:final id, :final params):
        await _onCompletion(id: id, params: params);
    }
  }

  Future<void> _handleNotification(IncomingNotificationMessage note) async {
    switch (note) {
      case InitializedMessage():
        await logMessage(MessageType.info, 'Apex LSP initialized');
        await _beginIndexingProgress();

        // Run indexing asynchronously so we don't block the main request loop.
        _indexingTask ??= _indexInBackground();

      case TextDocumentDidOpenMessage(:final params):
        _openDocuments.didOpen(params);
      case TextDocumentDidChangeMessage(:final params):
        _openDocuments.didChange(params);
      case TextDocumentDidCloseMessage(:final params):
        _openDocuments.didClose(params);

      case ExitMessage():
        // Spec: If exit is received and shutdown has been requested -> exit 0,
        // otherwise -> exit 1.
        _exiting = true;
        exitCode = _shutdownRequested ? 0 : 1;

        await logMessage(
          MessageType.info,
          'Apex LSP exiting (shutdown=$_shutdownRequested)',
        );
        await _output.flush();
        _exitFn(exitCode);
    }
  }

  Future<void> _onInitialize(InitializeRequest req) async {
    _initialized = true;

    // Gather workspace roots. If none are provided, indexing scope
    // will remain empty for now.
    _workspaceRootUris = Initialization.extractWorkspaceRoots(req);

    // Load SFDX project configs (if present) and compute package directory roots.
    _packageDirectoryUris = await _sfdxWorkspaceLocator
        .packageDirectoryScopeForWorkspaces(_workspaceRootUris);

    if (_packageDirectoryUris.isNotEmpty) {
      await logMessage(
        MessageType.info,
        'SFDX package directories: ${_packageDirectoryUris.join(', ')}',
      );
    } else {
      await logMessage(MessageType.info, 'No SFDX package directories found');
    }

    // Minimal InitializeResult with full document sync.
    //
    // TODO: Wire up workDoneProgress capability negotiation and proper
    // InitializeResult classes.
    final result = <String, Object?>{
      'capabilities': <String, Object?>{
        'textDocumentSync': 1, // TextDocumentSyncKind.Full
        // Very basic completions using the prebuilt index.
        // We keep it minimal: advertise that we support completion requests.
        'completionProvider': <String, Object?>{},
      },
      // TODO: Get from dynamic JSON or pubspec or something like that
      'serverInfo': <String, Object?>{'name': 'apex-lsp', 'version': '0.0.1'},
    };

    await _output.sendResponse(id: req.id, result: result);
  }

  Future<void> _beginIndexingProgress() async {
    // For now, only send a generic message that indexing will happen.
    //
    // TODO: We intentionally don't stream progress reports yet; we'll do that once the
    // indexer is implemented and we can measure progress.
    _indexingProgressToken ??= await Initialization.beginIndexingProgress(
      _output,
    );
  }

  Future<void> _endIndexingProgress({required String message}) async {
    final token = _indexingProgressToken;
    if (token == null) return;

    await _output.progress(
      token: token,
      value: WorkDoneProgressEnd(message: message),
    );

    // Reset token so a future re-index can start a new progress session cleanly.
    _indexingProgressToken = null;
  }

  Future<void> _indexInBackground() async {
    if (_workspaceRootUris.isEmpty) {
      await _endIndexingProgress(message: 'Indexing complete (no workspaces)');
      await logMessage(MessageType.info, 'Indexing complete (no workspaces)');
      return;
    }

    try {
      await logMessage(
        MessageType.info,
        'Indexing starting. Workspaces=${_workspaceRootUris.length}, '
        'packageDirs(total)=${_packageDirectoryUris.length}',
      );

      // The current design keeps `_packageDirectoryUris` as a combined scope across
      // all workspace roots. For indexing, we do a best-effort association:
      // index each workspace using the package directories that are under it.
      for (final root in _workspaceRootUris) {
        final rootPath = root.toFilePath(windows: Platform.isWindows);

        final packageDirsForRoot = _packageDirectoryUris.where((pkgUri) {
          final pkgPath = pkgUri.toFilePath(windows: Platform.isWindows);
          return pkgPath.startsWith(rootPath);
        }).toList();

        await logMessage(
          MessageType.info,
          'Indexing workspace root=$root (rootPath=$rootPath), '
          'packageDirs(forRoot)=${packageDirsForRoot.length}',
        );

        if (packageDirsForRoot.isNotEmpty) {
          await logMessage(
            MessageType.info,
            'Package dirs for $root: ${packageDirsForRoot.join(', ')}',
          );
        }

        await _indexer.indexWorkspace(
          workspaceRoot: root,
          packageDirectoryUris: packageDirsForRoot,
        );

        // Load class names from the generated `.sf-zed` JSON index.
        final loaded = await _loadIndexedClassNamesForWorkspace(root);
        await logMessage(
          MessageType.info,
          'Loaded $loaded indexed class names for $root',
        );
      }

      await _endIndexingProgress(message: 'Indexing complete');
      await logMessage(MessageType.info, 'Indexing complete');
    } catch (e) {
      await _endIndexingProgress(message: 'Indexing failed');
      await logMessage(MessageType.error, 'Indexing failed: $e');
    }
  }

  Future<int> _loadIndexedClassNamesForWorkspace(Uri workspaceRoot) async {
    final rootPath = workspaceRoot.toFilePath(windows: Platform.isWindows);
    final indexDir = Directory('$rootPath/.sf-zed');
    if (!await indexDir.exists()) return 0;

    var loaded = 0;

    await for (final entity in indexDir.list(
      recursive: false,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.json')) continue;

      try {
        final content = await entity.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is! Map) continue;

        final source = decoded['source'];
        if (source is! Map) continue;

        final relativePath = source['relativePath'];
        if (relativePath is! String) continue;

        final fileName = relativePath.split(Platform.pathSeparator).last;
        if (!fileName.toLowerCase().endsWith('.cls')) continue;

        final className = fileName.substring(0, fileName.length - 4);
        if (className.isEmpty) continue;

        if (_indexedClassNames.add(className)) {
          loaded++;
        }
      } catch (_) {
        // Ignore malformed index entries for now.
      }
    }

    return loaded;
  }

  Future<void> _onCompletion({
    required Object id,
    required CompletionParams params,
  }) async {
    final prefix = _extractPrefixAtPosition(
      uri: params.textDocument.uri,
      line: params.position.line,
      character: params.position.character,
    );

    if (prefix.isEmpty) {
      await _output.sendResponse(
        id: id,
        result: const CompletionList(
          isIncomplete: false,
          items: <CompletionItem>[],
        ).toJson(),
      );
      return;
    }

    final matches =
        _indexedClassNames
            .where(
              (name) => name.toLowerCase().startsWith(prefix.toLowerCase()),
            )
            .take(25)
            .toList()
          ..sort((a, b) => a.compareTo(b));

    final items = matches
        .map((name) => CompletionItem(label: name, insertText: name))
        .toList();

    await _output.sendResponse(
      id: id,
      result: CompletionList(isIncomplete: false, items: items).toJson(),
    );
  }

  String _extractPrefixAtPosition({
    required String uri,
    required int line,
    required int character,
  }) {
    final text = _openDocuments.get(uri);
    if (text == null) return '';

    final lines = text.split('\n');
    if (line < 0 || line >= lines.length) return '';

    final lineText = lines[line];

    // LSP character is UTF-16 code unit offset; for now we treat it as a string index.
    final clamped = character.clamp(0, lineText.length);

    // Walk left while we’re in an identifier.
    var start = clamped;
    while (start > 0) {
      final ch = lineText.codeUnitAt(start - 1);
      final isIdent =
          (ch >= 48 && ch <= 57) || // 0-9
          (ch >= 65 && ch <= 90) || // A-Z
          (ch >= 97 && ch <= 122) || // a-z
          ch == 95; // _
      if (!isIdent) break;
      start--;
    }

    return lineText.substring(start, clamped);
  }
  //   // treat it as a simple code-unit offset.
  //   if (character <= 0 || character > lineText.length) return false;

  //   final prevChar = lineText.substring(character - 1, character);
  //   return prevChar == 'T';
  // }
}
