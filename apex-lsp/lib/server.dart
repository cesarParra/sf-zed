import 'dart:async';
import 'dart:io';

import 'package:apex_lsp/completion/completion.dart';
import 'package:apex_lsp/documents/open_documents.dart';
import 'package:apex_lsp/indexing/indexer.dart';
import 'package:apex_lsp/indexing/local_indexer.dart';
import 'package:apex_lsp/initialization_status.dart';

import 'lsp_out.dart';
import 'message.dart';
import 'message_reader.dart';

typedef ExitFn = Never Function(int exitCode);

final class Server {
  Server({
    required LspOut output,
    required MessageReader reader,
    required ExitFn exitFn,
    required OpenDocuments openDocuments,
    required LocalIndexer localIndexer,
    required ApexIndexer workspaceIndexer,
  }) : _output = output,
       _reader = reader,
       _exitFn = exitFn,
       _openDocuments = openDocuments,
       _localIndexer = localIndexer,
       _workspaceIndexer = workspaceIndexer;

  final LspOut _output;
  final MessageReader _reader;
  final ExitFn _exitFn;

  final OpenDocuments _openDocuments;
  final LocalIndexer _localIndexer;
  final ApexIndexer _workspaceIndexer;

  InitializationStatus _initializationStatus = NotInitialized();
  bool _shutdownRequested = false;
  bool _exiting = false;

  Future<void> logMessage(MessageType type, String message) async {
    switch (_initializationStatus) {
      case Initialized():
        await _output.logMessage(type, message);
      case NotInitialized():
    }
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
    switch (_initializationStatus) {
      case NotInitialized():
        if (req.method != 'initialize' && req.method != 'shutdown') {
          await _output.sendError(
            id: req.id,
            code: -32002, // ServerNotInitialized (LSP)
            message: 'Server not initialized',
          );
          return;
        }
      case Initialized():
    }

    switch (req) {
      case InitializeRequest():
        await _onInitialize(req);
      case ShutdownRequest():
        _shutdownRequested = true;
        await _output.sendResponse(id: req.id, result: null);
      case CompletionRequest(:final id, :final params):
        await _onCompletion(
          id: id,
          params: params,
          localIndexer: _localIndexer,
        );
    }
  }

  Future<void> _handleNotification(IncomingNotificationMessage note) async {
    switch (_initializationStatus) {
      case Initialized(:final params):
        switch (note) {
          case InitializedMessage():
            await logMessage(MessageType.info, 'Apex LSP initialized');

            final token = ProgressToken.string(
              'apex-lsp-indexing-${DateTime.now().millisecondsSinceEpoch}',
            );
            await _output.workDoneProgressCreate(token: token);

            await for (final value in _workspaceIndexer.index(
              params,
              token: token,
            )) {
              _output.progress(params: value);
            }

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
      case NotInitialized():
        await logMessage(
          MessageType.error,
          'LSP not initiazed. Received ${note.method}',
        );
    }
  }

  Future<void> _onInitialize(InitializeRequest req) async {
    _initializationStatus = Initialized(params: req.params);

    // Minimal InitializeResult with full document sync.
    final result = <String, Object?>{
      'capabilities': <String, Object?>{
        'textDocumentSync': 1, // TextDocumentSyncKind.Full
        // Very basic completions using the prebuilt index.
        // We keep it minimal: advertise that we support completion requests.
        'completionProvider': <String, Object?>{
          'triggerCharacters': ['.'],
        },
      },
      // TODO: Get from dynamic JSON or pubspec or something like that
      'serverInfo': <String, Object?>{'name': 'apex-lsp', 'version': '0.0.1'},
    };

    await _output.sendResponse(id: req.id, result: result);
  }

  Future<void> _onCompletion({
    required Object id,
    required CompletionParams params,
    required LocalIndexer localIndexer,
  }) async {
    final text = _openDocuments.get(params.textDocument.uri);
    if (text == null) {
      return;
    }
    final completionList = await onCompletion(
      text: text,
      position: params.position,
      index: localIndexer.parseAndIndex(text),
    );
    await _output.sendResponse(id: id, result: completionList.toJson());
  }
}
