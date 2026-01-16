import 'package:apex_lsp/completion/completion_aggregator.dart';
import 'package:apex_lsp/completion/tree_sitter_completion_types.dart';
import 'package:apex_lsp/documents/open_documents.dart';
import 'package:apex_lsp/message.dart';

Future<CompletionList> onCompletion({
  required OpenDocuments openDocuments,
  required CompletionAggregator aggregator,
  required Object id,
  required CompletionParams params,
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

  final candidates = await aggregator.suggest(
    text: text,
    cursorOffset: cursorOffset,
  );

  final sortedLabels = candidates.kind == CompletionKind.className
      ? _scoreCandidatesByPrefix(
          candidates.labels,
          _extractPrefixFromText(text, cursorOffset),
        )
      : candidates.labels;

  final items = sortedLabels
      .take(25)
      .map((label) => CompletionItem(label: label, insertText: label))
      .toList();

  return CompletionList(isIncomplete: sortedLabels.length > 25, items: items);
}

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

String _extractPrefixFromText(String text, int cursorOffset) {
  var i = cursorOffset;
  if (i > text.length) i = text.length;

  var start = i;
  while (start > 0) {
    final ch = text.codeUnitAt(start - 1);
    final isIdent =
        (ch >= 48 && ch <= 57) || // 0-9
        (ch >= 65 && ch <= 90) || // A-Z
        (ch >= 97 && ch <= 122) || // a-z
        ch == 95 || // _
        ch == 36; // $
    if (!isIdent) break;
    start--;
  }

  return text.substring(start, i);
}

List<String> _scoreCandidatesByPrefix(List<String> labels, String prefix) {
  if (prefix.isEmpty) return List<String>.from(labels);
  final lowerPrefix = prefix.toLowerCase();

  final scored =
      labels
          .where((name) => name.toLowerCase().startsWith(lowerPrefix))
          .map(
            (name) => (
              name: name,
              length: name.length,
              distance: _levenshteinDistance(lowerPrefix, name.toLowerCase()),
            ),
          )
          .toList()
        ..sort((a, b) {
          final byDistance = a.distance.compareTo(b.distance);
          if (byDistance != 0) return byDistance;

          final byLength = a.length.compareTo(b.length);
          if (byLength != 0) return byLength;

          return a.name.compareTo(b.name);
        });

  return scored.map((c) => c.name).toList();
}

int _levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  // Ensure we use less memory by keeping the shorter string as "b".
  if (a.length < b.length) {
    final tmp = a;
    a = b;
    b = tmp;
  }

  final previous = List<int>.generate(b.length + 1, (i) => i);
  final current = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    final aChar = a.codeUnitAt(i - 1);

    for (var j = 1; j <= b.length; j++) {
      final cost = aChar == b.codeUnitAt(j - 1) ? 0 : 1;

      final deletion = previous[j] + 1;
      final insertion = current[j - 1] + 1;
      final substitution = previous[j - 1] + cost;

      var best = deletion;
      if (insertion < best) best = insertion;
      if (substitution < best) best = substitution;

      current[j] = best;
    }

    for (var j = 0; j < current.length; j++) {
      previous[j] = current[j];
    }
  }

  return previous[b.length];
}
