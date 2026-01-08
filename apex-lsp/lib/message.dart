import 'package:json_annotation/json_annotation.dart';

part 'message.g.dart';

enum MessageType {
  error(code: 1),
  warning(code: 2),
  info(code: 3),
  log(code: 4);

  const MessageType({required this.code});

  final int code;
}

int messageTypeToJson(MessageType type) => type.code;

MessageType messageTypeFromJson(int code) =>
    MessageType.values.firstWhere((t) => t.code == code);

// ----------- Incoming requests and notifications-----------------
// The LSP protocol defines 2 types of incoming messages: requests and notifications.

sealed class IncomingMessage {
  const IncomingMessage();
}

sealed class RequestMessage extends IncomingMessage {
  final Object id;
  String get method;

  const RequestMessage(this.id);
}

sealed class RequestMessageWithParams<TParams> extends RequestMessage {
  final TParams params;

  const RequestMessageWithParams(super.id, this.params);
}

final class InitializeRequest
    extends RequestMessageWithParams<Map<String, Object?>> {
  @override
  String get method => 'initialize';

  const InitializeRequest(super.id, super.params);
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

@JsonSerializable()
final class DidOpenTextDocumentParams {
  final TextDocumentItem textDocument;

  const DidOpenTextDocumentParams({required this.textDocument});

  factory DidOpenTextDocumentParams.fromJson(Map<String, Object?> json) =>
      _$DidOpenTextDocumentParamsFromJson(json);

  Map<String, Object?> toJson() => _$DidOpenTextDocumentParamsToJson(this);
}

@JsonSerializable()
final class TextDocumentItem {
  final String uri;
  final String text;

  const TextDocumentItem({required this.uri, required this.text});

  factory TextDocumentItem.fromJson(Map<String, Object?> json) =>
      _$TextDocumentItemFromJson(json);

  Map<String, Object?> toJson() => _$TextDocumentItemToJson(this);
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

@JsonSerializable()
final class DidCloseTextDocumentParams {
  final TextDocumentIdentifier textDocument;

  const DidCloseTextDocumentParams({required this.textDocument});

  factory DidCloseTextDocumentParams.fromJson(Map<String, Object?> json) =>
      _$DidCloseTextDocumentParamsFromJson(json);

  Map<String, Object?> toJson() => _$DidCloseTextDocumentParamsToJson(this);
}

@JsonSerializable()
final class TextDocumentIdentifier {
  final String uri;

  const TextDocumentIdentifier({required this.uri});

  factory TextDocumentIdentifier.fromJson(Map<String, Object?> json) =>
      _$TextDocumentIdentifierFromJson(json);

  Map<String, Object?> toJson() => _$TextDocumentIdentifierToJson(this);
}

@JsonSerializable()
final class TextDocumentContentChangeEvent {
  final String text;

  const TextDocumentContentChangeEvent({required this.text});

  factory TextDocumentContentChangeEvent.fromJson(Map<String, Object?> json) =>
      _$TextDocumentContentChangeEventFromJson(json);

  Map<String, Object?> toJson() => _$TextDocumentContentChangeEventToJson(this);
}

@JsonSerializable()
final class DidChangeTextDocumentParams {
  final TextDocumentIdentifier textDocument;
  final List<TextDocumentContentChangeEvent> contentChanges;

  const DidChangeTextDocumentParams({
    required this.textDocument,
    required this.contentChanges,
  });

  factory DidChangeTextDocumentParams.fromJson(Map<String, Object?> json) =>
      _$DidChangeTextDocumentParamsFromJson(json);

  Map<String, Object?> toJson() => _$DidChangeTextDocumentParamsToJson(this);
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

@JsonSerializable(createFactory: false)
class SuccessResponseMessage extends ResponseMessage {
  final Object? result;

  const SuccessResponseMessage(super.id, this.result);

  @override
  Map<String, Object?> toJson() => _$SuccessResponseMessageToJson(this);
}

@JsonSerializable(createFactory: false)
class ResponseError {
  final int code;
  final String message;
  final Object? data;

  const ResponseError(this.code, this.message, this.data);

  Map<String, Object?> toJson() => _$ResponseErrorToJson(this);
}

@JsonSerializable(createFactory: false)
class ErrorResponseMessage extends ResponseMessage {
  final ResponseError error;

  const ErrorResponseMessage(super.id, this.error);

  @override
  Map<String, Object?> toJson() => _$ErrorResponseMessageToJson(this);
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
@JsonSerializable(createFactory: false)
class LogMessage extends OutgoingNotificationMessage {
  @override
  String get method => 'window/logMessage';
  final MessageParams params;

  const LogMessage(this.params);

  @override
  Map<String, Object?> toJson() => _$LogMessageToJson(this);
}

// todo: this should be withparams
@JsonSerializable(createFactory: false)
class ShowMessage extends OutgoingNotificationMessage {
  @override
  String get method => 'window/showMessage';
  final MessageParams params;

  const ShowMessage(this.params);

  @override
  Map<String, Object?> toJson() => _$ShowMessageToJson(this);
}

@JsonSerializable(createFactory: false)
class MessageParams {
  @JsonKey(fromJson: messageTypeFromJson, toJson: messageTypeToJson)
  final MessageType type;
  final String message;

  const MessageParams({required this.type, required this.message});

  Map<String, Object?> toJson() => _$MessageParamsToJson(this);
}
