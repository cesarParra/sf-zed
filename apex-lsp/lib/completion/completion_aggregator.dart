import 'dart:async';

import 'package:apex_lsp/completion/completion.dart';
import 'package:apex_lsp/completion/completion_candidates.dart';
import 'package:apex_lsp/completion/completion_context.dart';
import 'package:apex_lsp/indexing/indexer.dart';
import 'package:apex_lsp/indexing/indexed_class.dart' as indexed_class;
import 'package:apex_lsp/indexing/tree_sitter_completion_types.dart';

final class CompletionAggregatorLegacy {
  // Future<CompletionCandidates> suggest({
  //   required String text,
  //   required int cursorOffset,
  // }) async {
  //   final candidates = _documentService.suggestLegacy(
  //     text: text,
  //     cursorOffset: cursorOffset,
  //   );

  //   return switch (candidates) {
  //     NoCandidates() => candidates,
  //     MemberCandidates() => _mergeMemberCandidates(
  //       text: text,
  //       cursorOffset: cursorOffset,
  //       candidates: candidates,
  //     ),
  //     ClassNameOrLocalCandidates() => _mergeClassNameCandidates(
  //       text: text,
  //       cursorOffset: cursorOffset,
  //       local: candidates,
  //     ),
  //   };
  // }

  /// Merges member completion candidates from local and workspace sources.
  ///
  /// If [candidates] already has a resolved member type from the document, it is
  /// returned as-is. Otherwise, it attempts to resolve the type using the
  /// workspace index.
  ///
  /// - [text]: The current file content.
  /// - [cursorOffset]: The cursor position.
  /// - [candidates]: The candidates found by the document service.
  // Future<CompletionCandidates> _mergeMemberCandidates({
  //   required String text,
  //   required int cursorOffset,
  //   required MemberCandidates candidates,
  // }) async {
  //   // If the candidate comes from the open document, we return the local information
  //   // instead of merging with the indexed class, which represent the rest of the codebase.
  //   if (candidates.memberTypeResolvedFromDocument) {
  //     return candidates;
  //   }

  //   final resolvedType = candidates.memberOfType;
  //   if (resolvedType.isNotEmpty) {
  //     final workspaceClass = await _indexedClassesRepository.typeByNameAsync(
  //       resolvedType,
  //     );

  //     if (workspaceClass != null) {
  //       final memberType =
  //           resolvedType.toLowerCase() == candidates.objectName.toLowerCase()
  //           ? indexed_class.MemberType.static
  //           : indexed_class.MemberType.instance;

  //       return MemberCandidates(
  //         labels: workspaceClass.memberNamesByType(memberType),
  //         memberOfType: resolvedType,
  //         memberTypeResolvedFromDocument: false,
  //         objectName: candidates.objectName,
  //       );
  //     }
  //   }

  //   return NoCandidates();
  // }

  /// Merges class name candidates from local and workspace sources.
  ///
  /// Combines labels from [local] with all class names known to the
  /// [_indexedClassesRepository].
  ///
  /// - [text]: The current file content.
  /// - [cursorOffset]: The cursor position.
  /// - [local]: The candidates found by the document service.
  // CompletionCandidates _mergeClassNameCandidates({
  //   required String text,
  //   required int cursorOffset,
  //   required ClassNameOrLocalCandidates local,
  // }) {
  //   final merged = <String>{};
  //   merged.addAll(local.labels);
  //   merged.addAll(_indexedClassesRepository.classNames);

  //   return ClassNameOrLocalCandidates(labels: merged.toList());
  // }
}

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
final class CompletionAggregator implements CompletionSuggestion {
  final CompletionSuggestion localSuggestion;
  final CompletionSuggestion indexedSuggestion;

  CompletionAggregator({
    required this.localSuggestion,
    required this.indexedSuggestion,
  });

  /// Suggests completion candidates at the specified [cursorOffset] in the [text].
  ///
  /// It first queries the [documentService] for local candidates. Depending on
  /// the kind of completion identified, it may merge those results with
  /// information from the [_indexedClassesRepository].
  ///
  /// - [text]: The current content of the file being edited.
  /// - [cursorOffset]: The 0-based character offset of the cursor.
  @override
  FutureOr<List<CompletionCandidate>> suggest({
    required CompletionContext context,
  }) {
    // TODO: aggregation of suggestion logic
    throw UnimplementedError();
  }
}

final class TreeSitterCompletionService implements CompletionSuggestion {
  TreeSitterCompletionService({required ApexDocumentIndex index})
    : _index = index;

  final ApexDocumentIndex _index;

  @override
  FutureOr<List<CompletionCandidate>> suggest({
    required CompletionContext context,
  }) {
    List<CompletionCandidate> completeMembers({
      required String text,
      required int cursorOffset,
      required String? objectName,
      required String? typeName,
    }) {
      if (typeName == null) {
        return [];
      }

      final classInfo = _index.classByName(typeName);
      if (classInfo == null) {
        return [];
      }

      final apexType = Local(name: classInfo.name);
      final memberSet = <String>{
        ...classInfo.fields,
        ...classInfo.properties,
        ...classInfo.methods,
      };
      final members = memberSet.map((memberName) {
        final member = classInfo.memberByName(memberName);
        if (member == null) return null;
        return MemberCandidate(
          label: memberName,
          kind: member.kind,
          type: member.type,
          resolvedType: apexType,
          memberOfType: apexType,
          memberTypeResolvedFromDocument: true,
          objectName: objectName,
        );
      }).whereType<MemberCandidate>().toList();

      return MemberCandidates(
        labels: memberSet.toList(),
        memberOfType: resolvedType,
        memberTypeResolvedFromDocument: true,
        objectName: objectName,
      );
    }

    List<CompletionCandidate> completeTopLevel() {
      // Class name and local variable declaration completion.
      // TODO: The way we are treating local variable declarations is pretty naive, since we don't
      // care in which scope they were found. Variable declarations should only show up if the user
      // is typing within the scope where it was declared (and before the currrent index)
      final all = {
        // All top level variables declared in the file. This
        // is more for the anonymous Apex case, where things can be declared
        // at any level.
        ..._index.variables.map((v) => v.name),

        // For the declared class, expands all local members.
        // TODO: This is a naive implementation that does't work for anon-apex,
        // since it doesn't care from which class the member came from.
        ..._index.classes.expand((c) => c.fields),
        ..._index.classes.expand((c) => c.properties),
        ..._index.classes.expand((c) => c.methods),

        // The name of the declared class (or classes in case of anon-apex) itself.
        ..._index.classes.map((c) => c.name),
      };

      return ClassNameOrLocalCandidates(labels: all.toList());
    }

    return switch (context) {
      CompletionContextNone() => [],
      CompletionContextMember(
        :final text,
        :final cursorOffset,
        :final objectName,
        :final typeName,
      ) =>
        completeMembers(
          text: text,
          cursorOffset: cursorOffset,
          objectName: objectName,
          typeName: typeName,
        ),
      CompletionContextTopLevel() => completeTopLevel(),
    };
  }
}

final class SuggestionFromIndexedFiles implements CompletionSuggestion {
  final indexed_class.IndexedClassProvider _indexClassProvider;

  SuggestionFromIndexedFiles({
    required indexed_class.IndexedClassProvider indexClassProvider,
  }) : _indexClassProvider = indexClassProvider;

  @override
  FutureOr<List<CompletionCandidate>> suggest({
    required CompletionContext context,
  }) {
    // TODO: implementation of suggestion logic
    throw UnimplementedError();
  }
}
