import 'package:apex_lsp/completion/tree_sitter_completion_service.dart';
import 'package:apex_lsp/completion/tree_sitter_completion_types.dart';
import 'package:apex_lsp/indexing/indexer.dart';
import 'package:apex_lsp/indexing/workspace_index.dart';

/// Aggregates completion candidates from the open document (Tree-sitter)
/// and workspace index (.sf-zed JSON).
final class CompletionAggregator {
  CompletionAggregator({
    required TreeSitterCompletionService documentService,
    required WorkspaceIndexProvider workspaceIndex,
  }) : _documentService = documentService,
       _workspaceIndex = workspaceIndex;

  final TreeSitterCompletionService _documentService;
  final WorkspaceIndexProvider _workspaceIndex;

  Future<CompletionCandidates> suggest({
    required String text,
    required int cursorOffset,
  }) async {
    final local = _documentService.suggest(
      text: text,
      cursorOffset: cursorOffset,
    );

    // TODO: There is a simpler return switch syntax for this
    switch (local.kind) {
      case CompletionKind.none:
        return local;
      case CompletionKind.member:
        return _mergeMemberCandidates(
          text: text,
          cursorOffset: cursorOffset,
          local: local,
        );
      case CompletionKind.className:
        return _mergeClassNameCandidates(
          text: text,
          cursorOffset: cursorOffset,
          local: local,
        );
    }
  }

  Future<CompletionCandidates> _mergeMemberCandidates({
    required String text,
    required int cursorOffset,
    required CompletionCandidates local,
  }) async {
    if (local.memberTypeResolvedFromDocument) {
      return local;
    }

    final resolvedType = local.memberOfType;
    final prefix = _extractIdentifierPrefix(text, cursorOffset);

    if (resolvedType != null && resolvedType.isNotEmpty) {
      final workspaceClass = await _workspaceIndex.classByNameAsync(
        resolvedType,
      );

      if (workspaceClass != null) {
        final members = workspaceClass.membersMatching(prefix);

        return CompletionCandidates(
          kind: CompletionKind.member,
          labels: members,
          memberOfType: resolvedType,
          memberTypeResolvedFromDocument: false,
        );
      }
    }

    if (local.labels.isNotEmpty) {
      return local;
    }

    // If we couldn't resolve a member type, fall back to class name completion.
    return _mergeClassNameCandidates(
      text: text,
      cursorOffset: cursorOffset,
      local: CompletionCandidates(
        kind: CompletionKind.className,
        labels: const [],
      ),
    );
  }

  CompletionCandidates _mergeClassNameCandidates({
    required String text,
    required int cursorOffset,
    required CompletionCandidates local,
  }) {
    final prefix = _extractIdentifierPrefix(text, cursorOffset).toLowerCase();

    final merged = <String>{};
    merged.addAll(local.labels);

    for (final name in _workspaceIndex.classNames) {
      if (prefix.isEmpty || name.toLowerCase().startsWith(prefix)) {
        merged.add(name);
      }
    }

    final labels = merged.toList()..sort();
    return CompletionCandidates(kind: CompletionKind.className, labels: labels);
  }

  String _extractIdentifierPrefix(String text, int cursorOffset) {
    var i = cursorOffset;
    if (i > text.length) i = text.length;

    var start = i;
    while (start > 0 && _isIdentifierChar(text.codeUnitAt(start - 1))) {
      start--;
    }
    return text.substring(start, i);
  }

  bool _isIdentifierChar(int ch) {
    return (ch >= 48 && ch <= 57) || // 0-9
        (ch >= 65 && ch <= 90) || // A-Z
        (ch >= 97 && ch <= 122) || // a-z
        ch == 95 || // _
        ch == 36; // $
  }
}

/// Adapter to expose [ApexIndexer] as a [WorkspaceIndexProvider].
final class ApexIndexerWorkspaceIndexAdapter implements WorkspaceIndexProvider {
  ApexIndexerWorkspaceIndexAdapter(this._indexer);

  final ApexIndexer _indexer;

  @override
  Iterable<String> get classNames => _indexer.indexedClassNames;

  @override
  Future<WorkspaceClassInfo?> classByNameAsync(String name) {
    return _indexer.loadWorkspaceClassInfo(name);
  }
}
