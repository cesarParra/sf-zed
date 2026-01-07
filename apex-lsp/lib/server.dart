import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lsp_out.dart';
import 'message.dart';
import 'message_reader.dart';

final class Server {
  Server({
    required Stdin input,
    required LspOut output,
    required IOSink logger,
  })  : _output = output,
        _log = logger,
        _reader = MessageReader(input);

  final LspOut _output;
  final IOSink _log;
  final MessageReader _reader;

  bool _initialized = false;
  bool _shutdownRequested = false;
  bool _exiting = false;

  // Minimal in-memory document store so we can compute basic completions.
  final Map<String, String> _openDocuments = <String, String>{};

  /// Sends an LSP `window/logMessage` notification.
  ///
  /// Additionally mirrors the message to stderr so it is visible when running
  /// Zed with `--foreground` (Zed may not surface `window/logMessage`).
  Future<void> logInfo(String message) =>
      _logMessage(MessageType.info, message);

  /// Sends an LSP `window/logMessage` notification at warning severity.
  ///
  /// Additionally mirrors the message to stderr so it is visible when running
  /// Zed with `--foreground` (Zed may not surface `window/logMessage`).
  Future<void> logWarn(String message) =>
      _logMessage(MessageType.warning, message);

  /// Sends an LSP `window/logMessage` notification at error severity.
  ///
  /// Additionally mirrors the message to stderr so it is visible when running
  /// Zed with `--foreground` (Zed may not surface `window/logMessage`).
  Future<void> logError(String message) =>
      _logMessage(MessageType.error, message);

  /// Sends an LSP `window/showMessage` notification (user-visible).
  Future<void> showInfo(String message) =>
      _showMessage(MessageType.info, message);

  Future<void> _logMessage(int type, String message) async {
    // LSP `window/logMessage` is a notification, so no response is expected.
    //
    // Spec: `LogMessageParams`:
    // - type: MessageType (1=Error,2=Warning,3=Info,4=Log)
    // - message: string
    _log.writeln('[apex-lsp] $message');

    if (!_initialized) return;

    try {
      _writeMessage(
        NotificationMessage(
          // TODO: Maybe we can use enums instead of strings for this?
          'window/logMessage',
          <String, Object?>{
            'type': type,
            'message': message,
          },
        ),
      );
    } catch (e) {
      _log.writeln('[apex-lsp] (logMessage failed: $e)');
    }
  }

  Future<void> _showMessage(int type, String message) async {
    // Spec: `window/showMessage` is a notification:
    // method: 'window/showMessage'
    // params: { type: MessageType, message: string }
    //
    // If the server hasn't been initialized yet, we can't rely on the client
    // being ready, so fall back to stderr.
    _log.writeln('[apex-lsp] $message');

    if (!_initialized) return;

    try {
      _writeMessage(
        NotificationMessage(
          'window/showMessage',
          <String, Object?>{
            'type': type,
            'message': message,
          },
        ),
      );
    } catch (e) {
      _log.writeln('[apex-lsp] (showMessage failed: $e)');
    }
  }

  Future<void> run() async {
    await logInfo('Starting (stdio)');

    await for (final message in _reader.messages()) {
      if (_exiting) break;

      // TODO: Use switch for this since we are working with a sealed class
      if (message is RequestMessage) {
        await _handleRequest(message);
      } else if (message is NotificationMessage) {
        await _handleNotification(message);
      } else {
        // Should never happen; keep the loop robust.
        await logWarn('Unknown message type: $message');
      }
    }

    await logInfo('Stopped');
  }

  Future<void> _handleRequest(RequestMessage req) async {
    if (!_initialized &&
        req.method != 'initialize' &&
        req.method != 'shutdown') {
      await _sendError(
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
        await _sendResponse(id: req.id, result: null);
        return;

      case 'textDocument/completion':
        await _onCompletion(req);
        return;

      default:
        await _sendError(
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
        // Milestone: show a user-visible notification so we know the LSP wiring
        // is working even if the client doesn't surface `window/logMessage`.
        await showInfo('Apex LSP initialized');
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

        // Milestone: show exit event as a user-visible message.
        await showInfo('Apex LSP exiting (shutdown=$_shutdownRequested)');

        await logInfo('exit received; shutdown=$_shutdownRequested');
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

    await _sendResponse(id: req.id, result: result);
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
      await _sendResponse(
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

    await _sendResponse(id: req.id, result: result);
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

  Future<void> _sendResponse({
    required Object id,
    required Object? result,
  }) async {
    _writeMessage(SuccessResponseMessage(id, result));
  }

  Future<void> _sendError({
    required Object id,
    required int code,
    required String message,
    Object? data,
  }) async {
    final errorObj = ResponseError(code, message, data);
    _writeMessage(ErrorResponseMessage(id, errorObj));
  }

  void _writeMessage(Message message) {
    final payload = jsonEncode(message.toJson());
    final bytes = utf8.encode(payload);

    // LSP framing:
    // Content-Length: <bytes>\r\n
    // \r\n
    // <json>
    final header = 'Content-Length: ${bytes.length}\r\n\r\n';

    // stdout is a byte sink; use add for correctness.
    _output.add(utf8.encode(header));
    _output.add(bytes);
    // Do not add extra newlines; protocol framing must be exact.
  }
}
