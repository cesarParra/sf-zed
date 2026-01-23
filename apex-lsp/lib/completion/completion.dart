import 'dart:async';

import 'package:apex_lsp/completion/completion_aggregator.dart';
import 'package:apex_lsp/completion/completion_context.dart';
import 'package:apex_lsp/completion/rank.dart';
import 'package:apex_lsp/documents/open_documents.dart';
import 'package:apex_lsp/indexing/indexed_class.dart';
import 'package:apex_lsp/indexing/tree_sitter_indexer.dart';
import 'package:apex_lsp/message.dart';

// TODO: In the future, we also want to add language keywords here
/// Represents a candidate for completion.
sealed class CompletionCandidate {}

/// Represents a completion for a top level [ApexType].
final class ApexTypeCandidate extends CompletionCandidate {
  final ApexType type;

  ApexTypeCandidate(this.type);
}

/// Represents a completion for a member of a type
final class MemberCandidate extends CompletionCandidate {
  final Member member;

  MemberCandidate(this.member);
}

enum MemberType { static, instance }

final class Member {
  final String name;
  final ApexType parentType;
  final MemberType type;

  Member({required this.name, required this.parentType, required this.type});
}

/// Represents a completion to a locally declared variable accessible
/// "globally" in this file. This can happen in anonymous apex files.
final class LocalVariableCandidate extends CompletionCandidate {}

/// Represents a top-level type (class, enum, interface).
sealed class ApexType {
  final String name;

  ApexType({required this.name});
}

/// Represents an [ApexType] that is somewhere in the index,
/// this means it lives in a different file than the one being edited.
final class Indexed extends ApexType {
  Indexed({required super.name});
}

/// Represents an [ApexType] that is somewhere local but is not the
/// type being edited. For example, this can happen when writing Anonymous Apex.
final class Local extends ApexType {
  Local({required super.name});
}

/// Represents the [ApexType] being edited.
final class Self extends ApexType {
  Self({required super.name});
}

/// Supports suggesting [CompletionCadidate]s based on the received [text],
/// which is the full text of the open document, and an [cursorOffset],
/// which is where the cursor is currently positioned at.
abstract interface class CompletionSuggestion {
  FutureOr<List<CompletionCandidate>> suggest({
    required CompletionContext context,
  });
}

const maxCompletionItems = 25;

/// Handles a Language Server Protocol completion request.
///
/// This function processes a completion request by retrieving
/// the text content of the [openDocuments] at the given URI, extracting its position using
/// the received [params], and delegates the work to the [aggregator]. It finally ranks the completion
/// candidates returned by the aggregator.
///
/// Returns a [CompletionList] with up to 25 completion items. The list is marked
/// as incomplete (`isIncomplete: true`) when there are more than 25 candidates
/// available, indicating that the client may need to request more specific completions
/// as the user continues typing.
///
/// Example:
/// ```dart
/// final completions = await onCompletion(
///   openDocuments: openDocuments,
///   aggregator: completionAggregator,
///   id: requestId,
///   params: completionParams,
/// );
/// // Send completions back to the LSP client
/// ```
///
/// See also:
///  * [CompletionAggregator], which provides the completion candidates.
///  * [rankCandidates], which applies ranking to class name suggestions.
Future<CompletionList> onCompletion({
  required OpenDocuments openDocuments,
  required CompletionParams params,
  required TreeSitterIndexer localIndexer,
  required IndexedClassProvider indexedClasProvider,
  Rank rank = rankCandidates,
}) async {
  final text = openDocuments.get(params.textDocument.uri);
  if (text == null) {
    return CompletionList(isIncomplete: false, items: <CompletionItem>[]);
  }

  final cursorOffset = _offsetAtPosition(
    text: text,
    line: params.position.line,
    character: params.position.character,
  );

  final index = localIndexer.parseAndIndex(text);
  final contextDetector = ContextDetector(index: index);
  final context = contextDetector.detect(
    text: text,
    cursorOffset: cursorOffset,
  );

  // TODO: If we are dealing with a "no_context", we can just return early.

  final localSuggestion = TreeSitterCompletionService(index: index);
  final indexedSuggestion = SuggestionFromIndexedFiles(
    indexClassProvider: indexedClasProvider,
  );

  final aggregator = CompletionAggregator(
    localSuggestion: localSuggestion,
    indexedSuggestion: indexedSuggestion,
  );
  final candidates = await aggregator.suggest(context: context);

  // TODO: filter rank, take, map and return.

  throw UnimplementedError();

  // final candidates = await aggregator.suggest(
  //   text: text,
  //   cursorOffset: cursorOffset,
  // );

  // final sortedLabels = rank(
  //   candidates.labels,
  //   text.extractIndentifierPrefixAt(cursorOffset),
  // );

  // final items = sortedLabels
  //     .take(maxCompletionItems)
  //     .map((label) => CompletionItem(label: label, insertText: label))
  //     .toList();

  // return CompletionList(isIncomplete: sortedLabels.length > 25, items: items);
}

/// Converts a line and character position to a byte offset within the text.
///
/// This utility function calculates the zero-based byte offset corresponding to
/// a given line and character position in a multiline text string. Lines are
/// assumed to be separated by `\n` characters.
///
/// - [text]: The complete text content to calculate offsets within.
/// - [line]: Zero-based line number.
/// - [character]: Zero-based character position within the line.
///
/// Returns the byte offset as an integer. If the line number is negative,
/// returns 0. If the line number exceeds the text length, returns the length
/// of the text. The character position is clamped to the line's length.
///
/// Example:
/// ```dart
/// final offset = _offsetAtPosition(
///   text: 'Hello\nWorld',
///   line: 1,      // Second line
///   character: 2, // Third character ('r')
/// );
/// print(offset); // 8 (6 for 'Hello\n' + 2 for 'Wo')
/// ```
int _offsetAtPosition({
  required String text,
  required int line,
  required int character,
}) {
  if (line < 0) return 0;

  final lines = text.split('\n');
  if (lines.isEmpty) return 0;
  if (line >= lines.length) return text.length;

  var offset = 0;
  for (var i = 0; i < line; i++) {
    offset += lines[i].length + 1;
  }

  final lineText = lines[line];
  final clamped = character.clamp(0, lineText.length).toInt();
  return offset + clamped;
}
