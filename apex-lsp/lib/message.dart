enum MessageType {
  error(code: 1),
  warning(code: 2),
  info(code: 3),
  log(code: 4);

  const MessageType({required this.code});

  final int code;
}

/// LSP `TextDocumentIdentifier`
///
/// Spec shape: `{ uri: DocumentUri }`
final class TextDocumentIdentifier {
  final String uri;

  const TextDocumentIdentifier({required this.uri});

  Map<String, Object?> toJson() => {'uri': uri};

  static TextDocumentIdentifier? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final uri = json['uri'];
    if (uri is! String) return null;
    return TextDocumentIdentifier(uri: uri);
  }
}

/// LSP `TextDocumentItem`
///
/// Spec shape: `{ uri, languageId, version, text }`
///
/// Note: This server only needs `uri` and `text` today.
final class TextDocumentItem {
  final String uri;
  final String text;

  const TextDocumentItem({required this.uri, required this.text});

  Map<String, Object?> toJson() => {'uri': uri, 'text': text};

  static TextDocumentItem? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final uri = json['uri'];
    final text = json['text'];
    if (uri is! String || text is! String) return null;
    return TextDocumentItem(uri: uri, text: text);
  }
}

/// LSP `TextDocumentContentChangeEvent`
///
/// For full sync, the shape is `{ text: string }`.
/// (Incremental changes include `range` / `rangeLength`.)
final class TextDocumentContentChangeEvent {
  final String text;

  const TextDocumentContentChangeEvent({required this.text});

  Map<String, Object?> toJson() => {'text': text};

  static TextDocumentContentChangeEvent? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final text = json['text'];
    if (text is! String) return null;
    return TextDocumentContentChangeEvent(text: text);
  }
}

/// LSP `DidOpenTextDocumentParams`
///
/// Spec shape: `{ textDocument: TextDocumentItem }`
final class DidOpenTextDocumentParams {
  final TextDocumentItem textDocument;

  const DidOpenTextDocumentParams({required this.textDocument});

  Map<String, Object?> toJson() => {'textDocument': textDocument.toJson()};

  static DidOpenTextDocumentParams? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final textDocument = TextDocumentItem.tryFromJson(json['textDocument']);
    if (textDocument == null) return null;
    return DidOpenTextDocumentParams(textDocument: textDocument);
  }
}

/// LSP `DidChangeTextDocumentParams`
///
/// Spec shape:
/// `{ textDocument: VersionedTextDocumentIdentifier, contentChanges: TextDocumentContentChangeEvent[] }`
///
/// Note: This server only needs `textDocument.uri` and `contentChanges[].text`.
final class DidChangeTextDocumentParams {
  final TextDocumentIdentifier textDocument;
  final List<TextDocumentContentChangeEvent> contentChanges;

  const DidChangeTextDocumentParams({
    required this.textDocument,
    required this.contentChanges,
  });

  Map<String, Object?> toJson() => {
    'textDocument': textDocument.toJson(),
    'contentChanges': contentChanges.map((c) => c.toJson()).toList(),
  };

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

/// LSP `DidCloseTextDocumentParams`
///
/// Spec shape: `{ textDocument: TextDocumentIdentifier }`
final class DidCloseTextDocumentParams {
  final TextDocumentIdentifier textDocument;

  const DidCloseTextDocumentParams({required this.textDocument});

  Map<String, Object?> toJson() => {'textDocument': textDocument.toJson()};

  static DidCloseTextDocumentParams? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final textDocument = TextDocumentIdentifier.tryFromJson(
      json['textDocument'],
    );
    if (textDocument == null) return null;
    return DidCloseTextDocumentParams(textDocument: textDocument);
  }
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

  const RequestMessage(this.id, this.method, this.params);

  @override
  Map<String, Object?> toJson() {
    return {'jsonrpc': jsonrpc, 'id': id, 'method': method, 'params': params};
  }
}

sealed class ResponseMessage extends Message {
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

sealed class NotificationMessage extends Message {
  String get method;

  const NotificationMessage();
}

/// Common base for notifications that include typed `params`.
sealed class NotificationMessageWithParams<TParams>
    extends NotificationMessage {
  TParams get params;

  const NotificationMessageWithParams();
}

/// LSP: `exit` notification has no params.
class ExitMessage extends NotificationMessage {
  @override
  String get method => 'exit';

  const ExitMessage();

  @override
  Map<String, Object?> toJson() {
    return {'jsonrpc': jsonrpc, 'method': method};
  }
}

/// LSP: `textDocument/didOpen`
class TextDocumentDidOpenMessage
    extends NotificationMessageWithParams<DidOpenTextDocumentParams> {
  @override
  String get method => 'textDocument/didOpen';

  @override
  final DidOpenTextDocumentParams params;

  const TextDocumentDidOpenMessage(this.params);

  @override
  Map<String, Object?> toJson() {
    return {'jsonrpc': jsonrpc, 'method': method, 'params': params.toJson()};
  }
}

/// LSP: `textDocument/didChange`
class TextDocumentDidChangeMessage
    extends NotificationMessageWithParams<DidChangeTextDocumentParams> {
  @override
  String get method => 'textDocument/didChange';

  @override
  final DidChangeTextDocumentParams params;

  const TextDocumentDidChangeMessage(this.params);

  @override
  Map<String, Object?> toJson() {
    return {'jsonrpc': jsonrpc, 'method': method, 'params': params.toJson()};
  }
}

/// LSP: `textDocument/didClose`
class TextDocumentDidCloseMessage
    extends NotificationMessageWithParams<DidCloseTextDocumentParams> {
  @override
  String get method => 'textDocument/didClose';

  @override
  final DidCloseTextDocumentParams params;

  const TextDocumentDidCloseMessage(this.params);

  @override
  Map<String, Object?> toJson() {
    return {'jsonrpc': jsonrpc, 'method': method, 'params': params.toJson()};
  }
}

class InitializedMessage extends NotificationMessage {
  @override
  String get method => 'initialized';

  const InitializedMessage();

  @override
  Map<String, Object?> toJson() {
    return {'jsonrpc': jsonrpc, 'method': method};
  }
}

class LogMessage extends NotificationMessage {
  @override
  String get method => 'window/logMessage';
  final MessageParams params;

  const LogMessage(this.params);

  @override
  Map<String, Object?> toJson() {
    return {'jsonrpc': jsonrpc, 'method': method, 'params': params.toJson()};
  }
}

class ShowMessage extends NotificationMessage {
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
