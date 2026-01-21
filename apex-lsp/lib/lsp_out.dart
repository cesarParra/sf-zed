import 'dart:convert';
import 'dart:io';

import 'message.dart';

/// Allows for testing without binding to `Stdout`.
abstract interface class LspByteSink {
  void add(List<int> data);

  Future<void> flush();
}

/// Adapter for production usage.
final class StdoutByteSink implements LspByteSink {
  StdoutByteSink(this._stdout);

  final Stdout _stdout;

  @override
  void add(List<int> data) => _stdout.add(data);

  @override
  Future<void> flush() => _stdout.flush();
}

/// Handles responding to messages through an [LspByteSink].
class LspOut {
  LspOut({required LspByteSink output}) : _output = output;

  final LspByteSink _output;

  Future<void> flush() => _output.flush();

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

  /// LSP `window/workDoneProgress/create` request.
  ///
  /// This asks the client to create a progress UI slot associated with [token].
  Future<void> workDoneProgressCreate({required ProgressToken token}) async {
    const requestId = 'workDoneProgressCreate';
    final params = WorkDoneProgressCreateParams(token: token);
    _writeMessage(WorkDoneProgressCreateRequest(id: requestId, params: params));
  }

  /// LSP `$/progress` notification for work-done progress.
  void progress({required WorkDoneProgressParams params}) {
    _writeMessage(WorkDoneProgressNotification(params));
  }

  void _writeMessage(OutgoingMessage message) {
    final payload = jsonEncode(message.toJson());
    final bytes = utf8.encode(payload);

    // LSP framing:
    // Content-Length: <bytes>\r\n
    // \r\n
    // <json>
    final header = 'Content-Length: ${bytes.length}\r\n\r\n';

    // Write header + json to the configured sink.
    _output.add(utf8.encode(header));
    _output.add(bytes);
    // Do not add extra newlines; protocol framing must be exact.
  }
}
