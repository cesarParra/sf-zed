sealed class Message {
  final String jsonrpc = '2.0';

  const Message();
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
}

sealed class ResponseMessage extends Message {
  final Object? id;

  const ResponseMessage(this.id);
}

class SuccessResponseMessage extends ResponseMessage {
  final Object result;

  const SuccessResponseMessage(
    super.id,
    this.result,
  );
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
}

class ErrorResponseMessage extends ResponseMessage {
  final ResponseError error;

  const ErrorResponseMessage(super.id, this.error);
}

class NotificationMessage extends Message {
  final String method;
  final Object? params;

  const NotificationMessage(this.method, this.params);
}
