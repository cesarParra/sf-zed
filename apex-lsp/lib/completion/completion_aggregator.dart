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
    required IndexedClassProvider indexedClassesRepository,
  }) : _documentService = documentService,
       _indexedClassesRepository = indexedClassesRepository;

  final TreeSitterCompletionService _documentService;
  final IndexedClassProvider _indexedClassesRepository;

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

    if (resolvedType != null && resolvedType.isNotEmpty) {
      final workspaceClass = await _indexedClassesRepository.classByNameAsync(
        resolvedType,
      );

      if (workspaceClass != null) {
        return CompletionCandidates(
          kind: CompletionKind.member,
          labels: workspaceClass.memberNames,
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
    final merged = <String>{};
    merged.addAll(local.labels);
    merged.addAll(_indexedClassesRepository.classNames);

    return CompletionCandidates(
      kind: CompletionKind.className,
      labels: merged.toList(),
    );
  }
}

/// Adapter to expose [ApexIndexer] as a [IndexedClassProvider].
final class ApexIndexerWorkspaceIndexAdapter implements IndexedClassProvider {
  ApexIndexerWorkspaceIndexAdapter(this._indexer);

  final ApexIndexer _indexer;

  @override
  Iterable<String> get classNames => _indexer.indexedClassNames;

  @override
  Future<IndexedClass?> classByNameAsync(String name) async {
    final classMirror = await _indexer.loadWorkspaceClassInfo(name);
    return classMirror != null
        ? ClassMirrorWrapper(classMirror: classMirror)
        : null;
  }
}
