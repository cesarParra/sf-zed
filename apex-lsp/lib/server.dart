import 'dart:async';
import 'dart:io';

import 'lsp_out.dart';
import 'message.dart';
import 'message_reader.dart';

final class Server {
  Server({required Stdin input, required LspOut output})
    : _output = output,
      _reader = MessageReader(input);

  final LspOut _output;
  final MessageReader _reader;

  bool _initialized = false;
  bool _shutdownRequested = false;
  bool _exiting = false;

  // Minimal in-memory document store so we can compute basic completions.
  final Map<String, String> _openDocuments = <String, String>{};

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
    }

    // TODO: Use proper classes and pattern matching instead of strings
    // switch (req.method) {
    //   case 'textDocument/completion':
    //     _output.debug('completion received');
    //     await _onCompletion(req);
    //     return;
    // }
  }

  Future<void> _handleNotification(IncomingNotificationMessage note) async {
    switch (note) {
      case InitializedMessage():
        await logMessage(MessageType.info, 'Apex LSP initialized');

      case TextDocumentDidOpenMessage(:final params):
        _output.debug('Received TextDocumentDidOpenMessage');
        _onDidOpen(params);

      case TextDocumentDidChangeMessage(:final params):
        _output.debug('Received TextDocumentDidChangeMessage');
        _onDidChange(params);

      case TextDocumentDidCloseMessage(:final params):
        _output.debug('Received TextDocumentDidCloseMessage');
        _onDidClose(params);

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
        exit(exitCode);
    }
  }

  Future<void> _onInitialize(InitializeRequest req) async {
    _initialized = true;

    // Minimal InitializeResult with completion provider and full document sync.
    final result = <String, Object?>{
      'capabilities': <String, Object?>{
        'textDocumentSync': 1, // TextDocumentSyncKind.Full
      },
      // TODO: Get from dynamic JSON or pubspec or something like that
      'serverInfo': <String, Object?>{'name': 'apex-lsp', 'version': '0.0.1'},
    };

    await _output.sendResponse(id: req.id, result: result);
  }

  void _onDidOpen(DidOpenTextDocumentParams params) {
    _openDocuments[params.textDocument.uri] = params.textDocument.text;
  }

  void _onDidChange(DidChangeTextDocumentParams params) {
    // Full sync: contentChanges[0].text is the whole document.
    if (params.contentChanges.isEmpty) return;
    final text = params.contentChanges.first.text;
    _openDocuments[params.textDocument.uri] = text;
  }

  void _onDidClose(DidCloseTextDocumentParams params) {
    _openDocuments.remove(params.textDocument.uri);
  }

  // Future<void> _onCompletion(RequestMessage req) async {
  //   // Return a CompletionList containing one item when the character immediately
  //   // before the cursor is "T".
  //   final shouldSuggest = _shouldSuggestWorkingCompletion(req.params);
  //   if (!shouldSuggest) {
  //     await _output.sendResponse(
  //       id: req.id,
  //       result: <String, Object?>{'isIncomplete': false, 'items': []},
  //     );
  //     return;
  //   }

  //   final item = <String, Object?>{
  //     'label': 'This is working',
  //     'kind': 1, // CompletionItemKind.Text
  //     // Insert the full phrase. If you only want it as a label, remove insertText.
  //     'insertText': 'This is working',
  //   };

  //   final result = <String, Object?>{
  //     'isIncomplete': false,
  //     'items': <Object?>[item],
  //   };

  //   await _output.sendResponse(id: req.id, result: result);
  // }

  // bool _shouldSuggestWorkingCompletion(Object? params) {
  //   if (params is! Map) return false;

  //   final textDocument = params['textDocument'];
  //   final position = params['position'];

  //   if (textDocument is! Map || position is! Map) return false;

  //   final uri = textDocument['uri'];
  //   final line = position['line'];
  //   final character = position['character'];

  //   if (uri is! String || line is! int || character is! int) return false;

  //   final text = _openDocuments[uri];
  //   if (text == null) return false;

  //   final lines = text.split('\n');
  //   if (line < 0 || line >= lines.length) return false;

  //   final lineText = lines[line];

  //   // TODO: position.character is UTF-16 based in LSP, but for this trivial test we
  //   // treat it as a simple code-unit offset.
  //   if (character <= 0 || character > lineText.length) return false;

  //   final prevChar = lineText.substring(character - 1, character);
  //   return prevChar == 'T';
  // }
}
