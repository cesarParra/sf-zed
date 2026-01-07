import 'dart:io';
import 'dart:convert';

import 'message.dart';

class LspOut {
  LspOut({required Stdout output}) : _output = output;

  final Stdout _output;

  Future<dynamic> flush() => _output.flush();

  void add(List<int> data) => _output.add(data);

  Future<void> logMessage(MessageType type, String message) async {
    _writeMessage(LogMessage(MessageParams(type: type, message: message)));
  }

  void debug(String message) {
    logMessage(.log, '[apex-lsp] $message');
  }

  Future<void> showMessage(MessageType type, String message) async {
    try {
      _writeMessage(ShowMessage(MessageParams(type: type, message: message)));
    } catch (e) {
      await logMessage(.error, 'showMessage failed: $e');
    }
  }

  Future<void> sendResponse({
    required Object id,
    required Object? result,
  }) async {
    _writeMessage(SuccessResponseMessage(id, result));
  }

  Future<void> sendError({
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
