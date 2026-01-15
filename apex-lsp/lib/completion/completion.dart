import 'package:apex_lsp/documents/open_documents.dart';
import 'package:apex_lsp/indexing/indexer.dart';
import 'package:apex_lsp/message.dart';

Future<CompletionList> onCompletion({
  required OpenDocuments openDocuments,
  required ApexIndexer apexIndexer,
  required Object id,
  required CompletionParams params,
}) async {
  final prefix = _extractPrefixAtPosition(
    openDocuments: openDocuments,
    uri: params.textDocument.uri,
    line: params.position.line,
    character: params.position.character,
  );

  if (prefix.isEmpty) {
    return CompletionList(isIncomplete: false, items: <CompletionItem>[]);
  }

  final lowerPrefix = prefix.toLowerCase();

  // Score candidates so that "better" matches come first:
  // 1) Prefer closer spelling using a simple edit-distance measure.
  // 2) Then prefer shorter names (helps short class names surface).
  // 3) Finally, fall back to alphabetical order.
  //
  // TODO: We currently only match startsWith(prefix). We want to eventually
  // do fuzzy matching
  final candidates =
      apexIndexer.indexedClassNames
          .where((name) => name.toLowerCase().startsWith(lowerPrefix))
          .map(
            (name) => (
              name: name,
              // Smaller is better.
              length: name.length,
              // Smaller is better.
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

  final items = candidates
      .take(25)
      .map((c) => CompletionItem(label: c.name, insertText: c.name))
      .toList();

  return CompletionList(isIncomplete: candidates.length > 25, items: items);
}

String _extractPrefixAtPosition({
  required OpenDocuments openDocuments,
  required String uri,
  required int line,
  required int character,
}) {
  final text = openDocuments.get(uri);
  if (text == null) return '';

  final lines = text.split('\n');
  if (line < 0 || line >= lines.length) return '';

  final lineText = lines[line];

  // LSP character is UTF-16 code unit offset; for now we treat it as a string index.
  final clamped = character.clamp(0, lineText.length);

  // Walk left while we’re in an identifier.
  var start = clamped;
  while (start > 0) {
    final ch = lineText.codeUnitAt(start - 1);
    final isIdent =
        (ch >= 48 && ch <= 57) || // 0-9
        (ch >= 65 && ch <= 90) || // A-Z
        (ch >= 97 && ch <= 122) || // a-z
        ch == 95; // _
    if (!isIdent) break;
    start--;
  }

  return lineText.substring(start, clamped);
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
