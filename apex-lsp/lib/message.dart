/// LSP `MessageType` (used by `window/logMessage` and `window/showMessage`).
///
/// Spec values:
/// - 1: Error
/// - 2: Warning
/// - 3: Info
/// - 4: Log
///
/// TODO: Can we use enums instead?
/// TODO: We want to create proper types based on the Spec
final class MessageType {
  static const int error = 1;
  static const int warning = 2;
  static const int info = 3;
}

sealed class Message {
  final String jsonrpc = '2.0';

  const Message();

  Map<String, Object?> toJson();
}

class RequestMessage extends Message {
  final Object id;
  final String method;
  // TODO: make this a proper object (sealed class?)
  final Object? params;

  const RequestMessage(
    this.id,
    this.method,
    this.params,
  );

  @override
  Map<String, Object?> toJson() {
    return {
      'jsonrpc': jsonrpc,
      'id': id,
      'method': method,
      'params': params,
    };
  }
}

sealed class ResponseMessage extends Message {
  final Object? id;

  const ResponseMessage(this.id);
}

class SuccessResponseMessage extends ResponseMessage {
  final Object? result;

  const SuccessResponseMessage(
    super.id,
    this.result,
  );

  @override
  Map<String, Object?> toJson() {
    return {
      'jsonrpc': jsonrpc,
      'id': id,
      'result': result,
    };
  }
}

class ResponseError {
  final int code;
  final String message;
  final Object? data;

  const ResponseError(
    this.code,
    this.message,
    this.data,
  );

  Map<String, Object?> toJson() {
    return {
      'code': code,
      'message': message,
      'data': data,
    };
  }
}

class ErrorResponseMessage extends ResponseMessage {
  final ResponseError error;

  const ErrorResponseMessage(super.id, this.error);

  @override
  Map<String, Object?> toJson() {
    return {
      'jsonrpc': jsonrpc,
      'id': id,
      'error': error.toJson(),
    };
  }
}

class NotificationMessage extends Message {
  final String method;
  final Object? params;

  const NotificationMessage(this.method, this.params);

  @override
  Map<String, Object?> toJson() {
    return {
      'jsonrpc': jsonrpc,
      'method': method,
      'params': params,
    };
  }
}
