import 'dart:io';

import 'package:apex_lsp/completion/completion_aggregator.dart';
import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/completion/tree_sitter_completion_service.dart';
import 'package:apex_lsp/completion/tree_sitter_completion_types.dart';
import 'package:apex_lsp/documents/open_documents.dart';
import 'package:apex_lsp/indexing/indexer.dart';
import 'package:apex_lsp/message.dart';

CompletionAggregator? _completionAggregator;
TreeSitterCompletionService? _treeSitterService;

CompletionAggregator? _buildAggregator(ApexIndexer apexIndexer) {
  if (_completionAggregator != null) return _completionAggregator;

  final libPath = Platform.environment['TS_SFAPEX_LIB'];
  final hasOverride = libPath != null && libPath.isNotEmpty;

  try {
    final bindings = TreeSitterBindings.load(
      path: hasOverride ? libPath : null,
    );
    _treeSitterService ??= TreeSitterCompletionService(bindings: bindings);
    _completionAggregator ??= CompletionAggregator(
      documentService: _treeSitterService!,
      workspaceIndex: ApexIndexerWorkspaceIndexAdapter(apexIndexer),
    );
    return _completionAggregator;
  } catch (_) {
    return null;
  }
}

Future<CompletionList> onCompletion({
  required OpenDocuments openDocuments,
  required ApexIndexer apexIndexer,
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

  final aggregator = _buildAggregator(apexIndexer);
  // TODO: Right now, this tries to build and aggregator and then
  // falls back to the old logic if it cannot. This leads to duplicated
  // logic in the completion-aggregator/service,and the fallback. Let's
  // make it so that there is always an aggregator and internally it resolves or not
  // if there are issues.
  if (aggregator != null) {
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

// TODO: Some crazy duplication here
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
