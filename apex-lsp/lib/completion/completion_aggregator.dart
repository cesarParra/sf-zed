import 'package:apex_lsp/completion/helpers.dart';
import 'package:apex_lsp/completion/tree_sitter_completion_service.dart';
import 'package:apex_lsp/completion/tree_sitter_completion_types.dart';
import 'package:apex_lsp/di.dart';
import 'package:apex_lsp/indexing/indexer.dart';
import 'package:apex_lsp/indexing/indexed_class.dart';
import 'package:apex_lsp/lsp_out.dart';

final logger = locator<LspOut>();

/// Aggregates completion candidates from the open document (Tree-sitter)
/// and workspace index (.sf-zed JSON).
final class CompletionAggregator {
  CompletionAggregator({
    required TreeSitterCompletionService documentService,
    required IndexedClassProvider workspaceIndex,
  }) : _documentService = documentService,
       _workspaceIndex = workspaceIndex;

  final TreeSitterCompletionService _documentService;
  final IndexedClassProvider _workspaceIndex;

  Future<CompletionCandidates> suggest({
    required String text,
    required int cursorOffset,
  }) async {
    final candidates = _documentService.suggest(
      text: text,
      cursorOffset: cursorOffset,
    );

    return switch (candidates.kind) {
      .none => candidates,
      .member => _mergeMemberCandidates(
        text: text,
        cursorOffset: cursorOffset,
        local: candidates,
      ),
      .className => _mergeClassNameCandidates(
        text: text,
        cursorOffset: cursorOffset,
        local: candidates,
      ),
    };
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
    final prefix = text.extractIndentifierPrefixAt(cursorOffset);

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
    final prefix = text.extractIndentifierPrefixAt(cursorOffset).toLowerCase();

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
}

/// Adapter to expose [ApexIndexer] as a [IndexedClassProvider].
final class ApexIndexerWorkspaceIndexAdapter implements IndexedClassProvider {
  ApexIndexerWorkspaceIndexAdapter(this._indexer);

  final ApexIndexer _indexer;

  @override
  Iterable<String> get classNames => _indexer.indexedClassNames;

  @override
  Future<IndexedClass?> classByNameAsync(String name) {
    return _indexer.loadWorkspaceClassInfo(name);
  }
}
