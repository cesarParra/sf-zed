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

@JsonSerializable()
final class Position {
  final int line;
  final int character;

  const Position({required this.line, required this.character});

  factory Position.fromJson(Map<String, Object?> json) =>
      _$PositionFromJson(json);

  Map<String, Object?> toJson() => _$PositionToJson(this);
}

@JsonSerializable()
final class TextDocumentIdentifierWithUri {
  final String uri;

  const TextDocumentIdentifierWithUri({required this.uri});

  factory TextDocumentIdentifierWithUri.fromJson(Map<String, Object?> json) =>
      _$TextDocumentIdentifierWithUriFromJson(json);

  Map<String, Object?> toJson() => _$TextDocumentIdentifierWithUriToJson(this);
}

@JsonSerializable()
final class CompletionParams {
  final TextDocumentIdentifierWithUri textDocument;
  final Position position;

  const CompletionParams({required this.textDocument, required this.position});

  factory CompletionParams.fromJson(Map<String, Object?> json) =>
      _$CompletionParamsFromJson(json);

  Map<String, Object?> toJson() => _$CompletionParamsToJson(this);
}

final class CompletionRequest
    extends RequestMessageWithParams<CompletionParams> {
  @override
  String get method => 'textDocument/completion';

  const CompletionRequest(super.id, super.params);
}

@JsonSerializable(createFactory: false)
final class CompletionItem {
  final String label;
  final String? insertText;

  const CompletionItem({required this.label, this.insertText});

  Map<String, Object?> toJson() => _$CompletionItemToJson(this);
}

@JsonSerializable(createFactory: false)
final class CompletionList {
  final bool isIncomplete;
  final List<CompletionItem> items;

  const CompletionList({required this.isIncomplete, required this.items});

  Map<String, Object?> toJson() => _$CompletionListToJson(this);
}

final class InitializeRequest
    extends RequestMessageWithParams<InitializedParams> {
  @override
  String get method => 'initialize';

  const InitializeRequest(super.id, super.params);

  @override
  String toString() {
    return 'InitializeRequest{id: $id, params: $params}';
  }
}

@JsonSerializable()
final class WorkspaceFolder {
  final String uri;
  final String name;

  const WorkspaceFolder(this.uri, this.name);

  factory WorkspaceFolder.fromJson(Map<String, dynamic> json) =>
      _$WorkspaceFolderFromJson(json);

  Map<String, dynamic> toJson() => _$WorkspaceFolderToJson(this);

  @override
  String toString() {
    return 'WorkspaceFolder{uri: $uri, name: $name}';
  }
}

@JsonSerializable()
final class InitializedParams {
  final List<WorkspaceFolder>? workspaceFolders;

  const InitializedParams(this.workspaceFolders);

  factory InitializedParams.fromJson(Map<String, dynamic> json) =>
      _$InitializedParamsFromJson(json);

  Map<String, dynamic> toJson() => _$InitializedParamsToJson(this);

  @override
  String toString() {
    return 'InitializedParams{workspaceFolders: $workspaceFolders}';
  }
}

final class ShutdownRequest extends RequestMessage {
  @override
  String get method => 'shutdown';

  const ShutdownRequest(super.id);
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

/// A progress token as defined by LSP:
/// `ProgressToken = integer | string`
///
/// We intentionally do not use `json_serializable` here since the JSON shape is
/// not an object, but a tagged union of primitives.
final class ProgressToken {
  final Object value;

  const ProgressToken._(this.value);

  const ProgressToken.integer(int value) : this._(value);
  const ProgressToken.string(String value) : this._(value);

  factory ProgressToken.fromJson(Object? json) => switch (json) {
    final int v => ProgressToken.integer(v),
    final String v => ProgressToken.string(v),
    _ => throw ArgumentError.value(
      json,
      'json',
      'ProgressToken must be an int or a string',
    ),
  };

  Object toJson() => value;

  @override
  String toString() => 'ProgressToken($value)';
}

@JsonSerializable(createFactory: false)
final class WorkDoneProgressCreateParams {
  final ProgressToken token;

  const WorkDoneProgressCreateParams({required this.token});

  Map<String, Object?> toJson() => _$WorkDoneProgressCreateParamsToJson(this);
}

@JsonSerializable(createFactory: false)
final class WorkDoneProgressCreateRequest extends OutgoingMessage {
  final Object id;

  final String method = 'window/workDoneProgress/create';

  final WorkDoneProgressCreateParams params;

  const WorkDoneProgressCreateRequest({required this.id, required this.params});

  @override
  Map<String, Object?> toJson() => _$WorkDoneProgressCreateRequestToJson(this);
}

@JsonSerializable(createFactory: false)
final class WorkDoneProgressNotification extends OutgoingNotificationMessage {
  @override
  String get method => r'$/progress';

  final WorkDoneProgressParams params;

  const WorkDoneProgressNotification(this.params);

  @override
  Map<String, Object?> toJson() => _$WorkDoneProgressNotificationToJson(this);
}

@JsonSerializable(createFactory: false)
final class WorkDoneProgressParams {
  final ProgressToken token;
  final WorkDoneProgressValue value;

  const WorkDoneProgressParams({required this.token, required this.value});

  Map<String, Object?> toJson() => _$WorkDoneProgressParamsToJson(this);
}

sealed class WorkDoneProgressValue {
  const WorkDoneProgressValue();

  Map<String, Object?> toJson();
}

@JsonSerializable(createFactory: false)
final class WorkDoneProgressBegin extends WorkDoneProgressValue {
  final String kind = 'begin';
  final String title;
  final bool? cancellable;
  final String? message;
  final int? percentage;

  const WorkDoneProgressBegin({
    required this.title,
    this.cancellable,
    this.message,
    this.percentage,
  });

  @override
  Map<String, Object?> toJson() => _$WorkDoneProgressBeginToJson(this);
}

@JsonSerializable(createFactory: false)
final class WorkDoneProgressReport extends WorkDoneProgressValue {
  final String kind = 'report';
  final bool? cancellable;
  final String? message;
  final int? percentage;

  const WorkDoneProgressReport({
    this.cancellable,
    this.message,
    this.percentage,
  });

  @override
  Map<String, Object?> toJson() => _$WorkDoneProgressReportToJson(this);
}

@JsonSerializable(createFactory: false)
final class WorkDoneProgressEnd extends WorkDoneProgressValue {
  final String kind = 'end';
  final String? message;

  const WorkDoneProgressEnd({this.message});

  @override
  Map<String, Object?> toJson() => _$WorkDoneProgressEndToJson(this);
}
