import 'dart:async';

import 'package:apex_lsp/completion/completion.dart';
import 'package:apex_lsp/completion/completion_context.dart';
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
    //throw UnimplementedError();
    return localSuggestion.suggest(context: context);
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

      final members = membersFromName(memberSet, apexType);

      return members.map(MemberCandidate.new).toList();
    }

    List<CompletionCandidate> completeTopLevel() {
      // Class name and local variable declaration completion.
      // TODO: The way we are treating local variable declarations is pretty naive, since we don't
      // care in which scope they were found. Variable declarations should only show up if the user
      // is typing within the scope where it was declared (and before the currrent index)

      // All top level variables declared in the file. This
      // is more for the anonymous Apex case, where things can be declared
      // at any level.
      final topLevelVariables = _index.variables.map(
        (v) => LocalVariableCandidate(v.name),
      );

      // For the declared class, expands all local members.
      // TODO: This is a naive implementation that does't work for anon-apex,
      // since it doesn't care from which class the member came from.
      // Eventually we want this to be only for types of "Self"
      final localMembers = [
        ..._index.classes.expand(
          (c) => [
            ...membersFromName(c.fields, Local(name: c.name)),
            ...membersFromName(c.properties, Local(name: c.name)),
            ...membersFromName(c.methods, Local(name: c.name)),
          ],
        ),
      ].map(MemberCandidate.new);

      // The name of the declared class (or classes in case of anon-apex) itself.
      final localClasses = _index.classes
          .map((c) => Local(name: c.name))
          .map(ApexTypeCandidate.new);

      return [...topLevelVariables, ...localMembers, ...localClasses];
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
    Future<List<CompletionCandidate>> completeMembersFromIndex(
      String? resolvedType,
      String? objectName,
    ) async {
      if (resolvedType == null || resolvedType.isEmpty || objectName == null) {
        return [];
      }

      final workspaceClass = await _indexClassProvider.typeByNameAsync(
        resolvedType,
      );

      if (workspaceClass == null) {
        return [];
      }

      final memberType = resolvedType.toLowerCase() == objectName.toLowerCase()
          // If the name of the type itself matches the name of the variable
          // we resolved for, then we are dealing with a static call (e.g. Foo.b)
          ? MemberType.static
          : MemberType.instance;

      final memberNamesForType = workspaceClass.memberNamesByType(memberType);

      return memberNamesForType.map((memberName) {
        return MemberCandidate(
          Member(
            name: memberName,
            parentType: Indexed(name: resolvedType),
            type: memberType,
          ),
        );
      }).toList();
    }

    Future<List<CompletionCandidate>> completeTypesFromIndex() async {
      return _indexClassProvider.classNames.map((classInfo) {
        return ApexTypeCandidate(Indexed(name: classInfo));
      }).toList();
    }

    return switch (context) {
      CompletionContextNone() => [],
      CompletionContextMember(:final typeName, :final objectName) =>
        completeMembersFromIndex(typeName, objectName),
      CompletionContextTopLevel() => completeTypesFromIndex(),
    };
  }
}

// TODO: At the moment, the information comming from tree sitter
// is not enough to know the type of member we are dealing with, so
// we are adding it as both static and instace for the time being.
Iterable<Member> membersFromName(
  Iterable<String> memberNames,
  ApexType apexType,
) {
  return memberNames.expand<Member>((memberName) {
    return [
      Member(name: memberName, parentType: apexType, type: .instance),
      Member(name: memberName, parentType: apexType, type: .static),
    ];
  });
}
