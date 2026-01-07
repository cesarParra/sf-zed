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

      // TODO: Use switch for this since we are working with a sealed class
      if (message is RequestMessage) {
        await _handleRequest(message);
      } else if (message is NotificationMessage) {
        await _handleNotification(message);
      } else {
        // TODO: Use Dart dot shorthands whenever logging messages
        await logMessage(
          .warning,
          'Unknown message type: $message',
        );
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

    switch (req.method) {
      case 'initialize':
        await _onInitialize(req);
        return;

      case 'shutdown':
        _shutdownRequested = true;
        await _output.sendResponse(id: req.id, result: null);
        return;

      case 'textDocument/completion':
        _output.debug('completion received');
        await _onCompletion(req);
        return;

      default:
        await _output.sendError(
          id: req.id,
          code: -32601, // Method not found (JSON-RPC)
          message: 'Method not found: ${req.method}',
        );
        return;
    }
  }

  Future<void> _handleNotification(NotificationMessage note) async {
    switch (note.method) {
      case 'initialized':
        await logMessage(MessageType.info, 'Apex LSP initialized');
        return;

      case 'textDocument/didOpen':
        _onDidOpen(note.params);
        return;

      case 'textDocument/didChange':
        _onDidChange(note.params);
        return;

      case 'textDocument/didClose':
        _onDidClose(note.params);
        return;

      case 'exit':
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
      default:
        // TODO: For this skeleton, ignore all other notifications.
        return;
    }
  }

  Future<void> _onInitialize(RequestMessage req) async {
    _initialized = true;

    // Minimal InitializeResult with completion provider and full document sync.
    final result = <String, Object?>{
      'capabilities': <String, Object?>{
        'textDocumentSync': 1, // TextDocumentSyncKind.Full
        'completionProvider': <String, Object?>{
          // TODO: For testing purposes, allow "T" to trigger completion without extra configuration.
          'triggerCharacters': <String>['T'],
        },
      },
      // TODO: Get from dynamic JSON or pubspec or something like that
      'serverInfo': <String, Object?>{'name': 'apex-lsp', 'version': '0.0.1'},
    };

    await _output.sendResponse(id: req.id, result: result);
  }

  void _onDidOpen(Object? params) {
    if (params is! Map) return;
    final textDocument = params['textDocument'];
    if (textDocument is! Map) return;

    final uri = textDocument['uri'];
    final text = textDocument['text'];
    if (uri is String && text is String) {
      _openDocuments[uri] = text;
    }
  }

  void _onDidChange(Object? params) {
    if (params is! Map) return;
    final textDocument = params['textDocument'];
    final contentChanges = params['contentChanges'];

    if (textDocument is! Map || contentChanges is! List) return;
    final uri = textDocument['uri'];
    if (uri is! String) return;

    // Full sync: contentChanges[0].text is the whole document.
    if (contentChanges.isEmpty) return;
    final first = contentChanges.first;
    if (first is! Map) return;

    final text = first['text'];
    if (text is String) {
      _openDocuments[uri] = text;
    }
  }

  void _onDidClose(Object? params) {
    if (params is! Map) return;
    final textDocument = params['textDocument'];
    if (textDocument is! Map) return;

    final uri = textDocument['uri'];
    if (uri is String) {
      _openDocuments.remove(uri);
    }
  }

  Future<void> _onCompletion(RequestMessage req) async {
    // Return a CompletionList containing one item when the character immediately
    // before the cursor is "T".
    final shouldSuggest = _shouldSuggestWorkingCompletion(req.params);
    if (!shouldSuggest) {
      await _output.sendResponse(
        id: req.id,
        result: <String, Object?>{'isIncomplete': false, 'items': []},
      );
      return;
    }

    final item = <String, Object?>{
      'label': 'This is working',
      'kind': 1, // CompletionItemKind.Text
      // Insert the full phrase. If you only want it as a label, remove insertText.
      'insertText': 'This is working',
    };

    final result = <String, Object?>{
      'isIncomplete': false,
      'items': <Object?>[item],
    };

    await _output.sendResponse(id: req.id, result: result);
  }

  bool _shouldSuggestWorkingCompletion(Object? params) {
    if (params is! Map) return false;

    final textDocument = params['textDocument'];
    final position = params['position'];

    if (textDocument is! Map || position is! Map) return false;

    final uri = textDocument['uri'];
    final line = position['line'];
    final character = position['character'];

    if (uri is! String || line is! int || character is! int) return false;

    final text = _openDocuments[uri];
    if (text == null) return false;

    final lines = text.split('\n');
    if (line < 0 || line >= lines.length) return false;

    final lineText = lines[line];

    // TODO: position.character is UTF-16 based in LSP, but for this trivial test we
    // treat it as a simple code-unit offset.
    if (character <= 0 || character > lineText.length) return false;

    final prevChar = lineText.substring(character - 1, character);
    return prevChar == 'T';
  }
}
