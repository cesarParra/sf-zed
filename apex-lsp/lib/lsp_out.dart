import 'dart:io';
import 'dart:convert';

import 'message.dart';

class LspOut {
  LspOut({
    required Stdout output,
  }) : _output = output;

  final Stdout _output;

  Future<dynamic> flush() => _output.flush();

  void add(List<int> data) => _output.add(data);

  Future<void> logMessage(MessageType type, String message) async {
    // LSP `window/logMessage` is a notification, so no response is expected.
    //
    // Spec: `LogMessageParams`:
    // - type: MessageType (1=Error,2=Warning,3=Info,4=Log)
    // - message: string
    _writeMessage(
      NotificationMessage(
        // TODO: these should be proper types, since it is easy to make a mistake when building the params
        // or typing out the message string name
        'window/logMessage',
        <String, Object?>{
          'type': type.code,
          'message': message,
        },
      ),
    );
  }

  void debug(String message) {
    // TODO: Avoid using hardcoded numbers
    logMessage(.log, '[apex-lsp] $message');
  }

  Future<void> showMessage(int type, String message) async {
    // Spec: `window/showMessage` is a notification:
    // method: 'window/showMessage'
    // params: { type: MessageType, message: string }
    //
    // If the server hasn't been initialized yet, we can't rely on the client
    // being ready, so fall back to stderr.
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
      // TODO: Avoid using hardcoded numbers
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
