import 'package:apex_lsp/completion/tree_sitter_completion_service.dart';
import 'package:apex_lsp/completion/tree_sitter_completion_types.dart';
import 'package:apex_lsp/indexing/indexer.dart';
import 'package:apex_lsp/indexing/indexed_class.dart';

/// Aggregates completion candidates from the open document (Tree-sitter)
/// and workspace index (.sf-zed JSON file repository).
///
/// This class acts as a coordinator between local document analysis provided
/// by [TreeSitterCompletionService] and global workspace information provided
/// by [IndexedClassProvider]. It determines the completion kind and merges
/// results accordingly.
///
/// Example:
/// ```dart
/// final aggregator = CompletionAggregator(
///   documentService: myTreeSitterService,
///   indexedClassesRepository: myIndexerAdapter,
/// );
///
/// final candidates = await aggregator.suggest(
///   text: 'Account a; a.',
///   cursorOffset: 12,
/// );
/// ```
final class CompletionAggregator {
  /// Creates a [CompletionAggregator] with the required services.
  ///
  /// - [documentService]: The service providing Tree-sitter based completions.
  /// - [indexedClassesRepository]: The repository containing indexed workspace classes.
  CompletionAggregator({
    required TreeSitterCompletionService documentService,
    required IndexedClassProvider indexedClassesRepository,
  }) : _documentService = documentService,
       _indexedClassesRepository = indexedClassesRepository;

  final TreeSitterCompletionService _documentService;
  final IndexedClassProvider _indexedClassesRepository;

  /// Suggests completion candidates at the specified [cursorOffset] in the [text].
  ///
  /// It first queries the [documentService] for local candidates. Depending on
  /// the kind of completion identified, it may merge those results with
  /// information from the [_indexedClassesRepository].
  ///
  /// - [text]: The current content of the file being edited.
  /// - [cursorOffset]: The 0-based character offset of the cursor.
  ///
  /// Returns a [Future] that completes with [CompletionCandidates].
  Future<CompletionCandidates> suggest({
    required String text,
    required int cursorOffset,
  }) async {
    final candidates = _documentService.suggest(
      text: text,
      cursorOffset: cursorOffset,
    );

    return switch (candidates) {
      NoCandidates() => candidates,
      MemberCandidates() => _mergeMemberCandidates(
        text: text,
        cursorOffset: cursorOffset,
        candidates: candidates,
      ),
      ClassNameCandidates() => _mergeClassNameCandidates(
        text: text,
        cursorOffset: cursorOffset,
        local: candidates,
      ),
    };
  }

  /// Merges member completion candidates from local and workspace sources.
  ///
  /// If [candidates] already has a resolved member type from the document, it is
  /// returned as-is. Otherwise, it attempts to resolve the type using the
  /// workspace index.
  ///
  /// - [text]: The current file content.
  /// - [cursorOffset]: The cursor position.
  /// - [candidates]: The candidates found by the document service.
  Future<CompletionCandidates> _mergeMemberCandidates({
    required String text,
    required int cursorOffset,
    required MemberCandidates candidates,
  }) async {
    // If the candidate comes from the open document, we return the local information
    // instead of merging with the indexed class, which represent the rest of the codebase.
    if (candidates.memberTypeResolvedFromDocument) {
      return candidates;
    }

    final resolvedType = candidates.memberOfType;
    if (resolvedType.isNotEmpty) {
      final workspaceClass = await _indexedClassesRepository.classByNameAsync(
        resolvedType,
      );

      if (workspaceClass != null) {
        final memberType =
            resolvedType.toLowerCase() == candidates.objectName?.toLowerCase()
            ? MemberType.static
            : MemberType.instance;

        return MemberCandidates(
          labels: workspaceClass.memberNamesByType(memberType),
          memberOfType: resolvedType,
          memberTypeResolvedFromDocument: false,
          objectName: candidates.objectName,
        );
      }
    }

    return NoCandidates();
  }

  /// Merges class name candidates from local and workspace sources.
  ///
  /// Combines labels from [local] with all class names known to the
  /// [_indexedClassesRepository].
  ///
  /// - [text]: The current file content.
  /// - [cursorOffset]: The cursor position.
  /// - [local]: The candidates found by the document service.
  CompletionCandidates _mergeClassNameCandidates({
    required String text,
    required int cursorOffset,
    required ClassNameCandidates local,
  }) {
    final merged = <String>{};
    merged.addAll(local.labels);
    merged.addAll(_indexedClassesRepository.classNames);

    return ClassNameCandidates(labels: merged.toList());
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
    final classMirror = await _indexer.getIndexedClassInfo(name);
    return classMirror != null
        ? ClassMirrorWrapper(classMirror: classMirror)
        : null;
  }
}
