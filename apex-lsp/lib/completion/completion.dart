import 'package:apex_lsp/completion/completion_aggregator.dart';
import 'package:apex_lsp/completion/helpers.dart';
import 'package:apex_lsp/completion/rank.dart';
import 'package:apex_lsp/completion/tree_sitter_completion_types.dart';
import 'package:apex_lsp/di.dart';
import 'package:apex_lsp/documents/open_documents.dart';
import 'package:apex_lsp/lsp_out.dart';
import 'package:apex_lsp/message.dart';

const maxCompletionItems = 25;

/// Handles a Language Server Protocol completion request.
///
/// This function processes a completion request by retrieving
/// the text content of the document at the given URI, extracting its position
/// and delegates the work to the [aggregator]. It finally ranks the completion
/// candidates returned by the aggregator.
///
/// - [openDocuments]: Collection of currently open documents in the editor.
/// - [aggregator]: Service that aggregates completion candidates from both the
///   current document (via Tree-sitter parsing) and the workspace index.
/// - [id]: Unique identifier for this LSP request (used for logging).
/// - [params]: LSP completion parameters containing the text document URI and cursor position.
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
  required CompletionAggregator aggregator,
  required CompletionParams params,
}) async {
  final logger = locator<LspOut>();
  final text = openDocuments.get(params.textDocument.uri);
  if (text == null) {
    logger.debug('[completion] no text');
    return CompletionList(isIncomplete: false, items: <CompletionItem>[]);
  }

  final cursorOffset = _offsetAtPosition(
    text: text,
    line: params.position.line,
    character: params.position.character,
  );
  logger.debug(
    '[completion] - finding a suggestion for ${_extractPrefixFromText(text, cursorOffset)} - Position - $cursorOffset',
  );

  final candidates = await aggregator.suggest(
    text: text,
    cursorOffset: cursorOffset,
  );

  final sortedLabels = candidates.kind == CompletionKind.className
      ? rankCandidates(
          candidates.labels,
          _extractPrefixFromText(text, cursorOffset),
        )
      : candidates.labels;

  final items = sortedLabels
      .take(maxCompletionItems)
      .map((label) => CompletionItem(label: label, insertText: label))
      .toList();

  logger.debug(
    '[completion] Returning ${items.length} out pf ${sortedLabels.length} possible',
  );
  return CompletionList(isIncomplete: sortedLabels.length > 25, items: items);
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

/// Extracts the identifier prefix immediately before the cursor offset.
/// Scans backward from the cursor position to find the start of an identifier.
///
/// This prefix is used to filter completion candidates and compute ranking.
///
/// - [text]: The complete text content.
/// - [cursorOffset]: Zero-based byte offset of the cursor position.
///
/// Returns the identifier prefix as a string, which may be empty if the cursor
/// is not positioned after an identifier character.
///
/// Example:
/// ```dart
/// final prefix = _extractPrefixFromText(
///   text: 'System.debug(myVar)',
///   cursorOffset: 12, // Position after 'myVar'
/// );
/// print(prefix); // 'myVar'
/// ```
String _extractPrefixFromText(String text, int cursorOffset) {
  var i = cursorOffset;
  if (i > text.length) i = text.length;

  var start = i;
  while (start > 0) {
    final ch = text.codeUnitAt(start - 1);
    if (!ch.isIdentifierChar) break;
    start--;
  }

  return text.substring(start, i);
}
