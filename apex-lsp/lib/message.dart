enum MessageType {
  error(code: 1),
  warning(code: 2),
  info(code: 3),
  log(code: 4);

  const MessageType({required this.code});

  final int code;
}

// ----------- Incoming requests and notifications-----------------
// The LSP protocol defines 2 types of incoming messages: requests and notifications.

sealed class IncomingMessage {
  const IncomingMessage();
}

class RequestMessage extends IncomingMessage {
  final Object id;
  final String method;
  // TODO: make this a proper object (sealed class?)
  final Object? params;

  const RequestMessage(this.id, this.method, this.params);
}

/// Common base for notifications.
sealed class IncomingNotificationMessage extends IncomingMessage {
  String get method;

  const IncomingNotificationMessage();
}

/// Common base for notifications that include typed `params`.
sealed class IncomingNotificationMessageWithParams<TParams>
    extends IncomingNotificationMessage {
  TParams get params;

  const IncomingNotificationMessageWithParams();
}

class InitializedMessage extends IncomingNotificationMessage {
  @override
  String get method => 'initialized';

  const InitializedMessage();
}

class ExitMessage extends IncomingNotificationMessage {
  @override
  String get method => 'exit';

  const ExitMessage();
}

class TextDocumentDidOpenMessage
    extends IncomingNotificationMessageWithParams<DidOpenTextDocumentParams> {
  @override
  String get method => 'textDocument/didOpen';

  @override
  final DidOpenTextDocumentParams params;

  const TextDocumentDidOpenMessage(this.params);
}

final class DidOpenTextDocumentParams {
  final TextDocumentItem textDocument;

  const DidOpenTextDocumentParams({required this.textDocument});

  static DidOpenTextDocumentParams? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final textDocument = TextDocumentItem.tryFromJson(json['textDocument']);
    if (textDocument == null) return null;
    return DidOpenTextDocumentParams(textDocument: textDocument);
  }
}

final class TextDocumentItem {
  final String uri;
  final String text;

  const TextDocumentItem({required this.uri, required this.text});

  static TextDocumentItem? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final uri = json['uri'];
    final text = json['text'];
    if (uri is! String || text is! String) return null;
    return TextDocumentItem(uri: uri, text: text);
  }
}

class TextDocumentDidChangeMessage
    extends IncomingNotificationMessageWithParams<DidChangeTextDocumentParams> {
  @override
  String get method => 'textDocument/didChange';

  @override
  final DidChangeTextDocumentParams params;

  const TextDocumentDidChangeMessage(this.params);
}

class TextDocumentDidCloseMessage
    extends IncomingNotificationMessageWithParams<DidCloseTextDocumentParams> {
  @override
  String get method => 'textDocument/didClose';

  @override
  final DidCloseTextDocumentParams params;

  const TextDocumentDidCloseMessage(this.params);
}

final class DidCloseTextDocumentParams {
  final TextDocumentIdentifier textDocument;

  const DidCloseTextDocumentParams({required this.textDocument});

  static DidCloseTextDocumentParams? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final textDocument = TextDocumentIdentifier.tryFromJson(
      json['textDocument'],
    );
    if (textDocument == null) return null;
    return DidCloseTextDocumentParams(textDocument: textDocument);
  }
}

final class TextDocumentIdentifier {
  final String uri;

  const TextDocumentIdentifier({required this.uri});

  static TextDocumentIdentifier? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final uri = json['uri'];
    if (uri is! String) return null;
    return TextDocumentIdentifier(uri: uri);
  }
}

final class TextDocumentContentChangeEvent {
  final String text;

  const TextDocumentContentChangeEvent({required this.text});

  static TextDocumentContentChangeEvent? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final text = json['text'];
    if (text is! String) return null;
    return TextDocumentContentChangeEvent(text: text);
  }
}

final class DidChangeTextDocumentParams {
  final TextDocumentIdentifier textDocument;
  final List<TextDocumentContentChangeEvent> contentChanges;

  const DidChangeTextDocumentParams({
    required this.textDocument,
    required this.contentChanges,
  });

  static DidChangeTextDocumentParams? tryFromJson(Object? json) {
    if (json is! Map) return null;

    final textDocument = TextDocumentIdentifier.tryFromJson(
      json['textDocument'],
    );
    if (textDocument == null) return null;

    final rawChanges = json['contentChanges'];
    if (rawChanges is! List) return null;

    final contentChanges = <TextDocumentContentChangeEvent>[];
    for (final raw in rawChanges) {
      final change = TextDocumentContentChangeEvent.tryFromJson(raw);
      if (change == null) return null;
      contentChanges.add(change);
    }

    return DidChangeTextDocumentParams(
      textDocument: textDocument,
      contentChanges: contentChanges,
    );
  }
}

//  ---------- Outgoing requests and notifications -------------

sealed class OutgoingMessage {
  final String jsonrpc = '2.0';

  const OutgoingMessage();

  Map<String, Object?> toJson();
}

sealed class ResponseMessage extends OutgoingMessage {
  final Object? id;

  const ResponseMessage(this.id);
}

class SuccessResponseMessage extends ResponseMessage {
  final Object? result;

  const SuccessResponseMessage(super.id, this.result);

  @override
  Map<String, Object?> toJson() {
    return {'jsonrpc': jsonrpc, 'id': id, 'result': result};
  }
}

class ResponseError {
  final int code;
  final String message;
  final Object? data;

  const ResponseError(this.code, this.message, this.data);

  Map<String, Object?> toJson() {
    return {'code': code, 'message': message, 'data': data};
  }
}

class ErrorResponseMessage extends ResponseMessage {
  final ResponseError error;

  const ErrorResponseMessage(super.id, this.error);

  @override
  Map<String, Object?> toJson() {
    return {'jsonrpc': jsonrpc, 'id': id, 'error': error.toJson()};
  }
}

sealed class OutgoingNotificationMessage extends OutgoingMessage {
  String get method;

  const OutgoingNotificationMessage();
}

/// Common base for notifications that include typed `params`.
sealed class OutgoingNotificationMessageWithParams<TParams>
    extends OutgoingNotificationMessage {
  TParams get params;

  const OutgoingNotificationMessageWithParams();
}

// todo: this should be withparams
class LogMessage extends OutgoingNotificationMessage {
  @override
  String get method => 'window/logMessage';
  final MessageParams params;

  const LogMessage(this.params);

  @override
  Map<String, Object?> toJson() {
    return {'jsonrpc': jsonrpc, 'method': method, 'params': params.toJson()};
  }
}

// todo: this should be withparams
class ShowMessage extends OutgoingNotificationMessage {
  @override
  String get method => 'window/showMessage';
  final MessageParams params;

  const ShowMessage(this.params);

  @override
  Map<String, Object?> toJson() {
    return {'jsonrpc': jsonrpc, 'method': method, 'params': params.toJson()};
  }
}

class MessageParams {
  final MessageType type;
  final String message;

  const MessageParams({required this.type, required this.message});

  Map<String, Object> toJson() {
    return {'type': type.code, 'message': message};
  }
}
