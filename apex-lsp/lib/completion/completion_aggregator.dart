import 'dart:async';

import 'package:apex_lsp/completion/completion.dart';
import 'package:apex_lsp/completion/completion_context.dart';
import 'package:apex_lsp/indexing/indexed_class.dart' as indexed_class;
import 'package:apex_lsp/indexing/tree_sitter_completion_types.dart';

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
  }) async {
    final localSuggestions = await localSuggestion.suggest(context: context);
    final indexedSuggestions = await indexedSuggestion.suggest(
      context: context,
    );
    return [...localSuggestions, ...indexedSuggestions];
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
      if (typeName == null || objectName == null) {
        return [];
      }

      final classInfo = _index.classByName(typeName);
      if (classInfo == null) {
        return [];
      }

      final memberType = typeName.toLowerCase() == objectName.toLowerCase()
          ? MemberType.static
          : MemberType.instance;

      final apexType = Local(name: classInfo.name);
      final memberList = <ApexMemberInfo>[
        ...classInfo.fields,
        ...classInfo.properties,
        ...classInfo.methods,
      ];

      final members = membersFromMemberInfo(
        memberList,
        apexType,
      ).where((m) => m.type == memberType);

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
      // since it doesn't care from which class the member came from (in anon-apex
      // we can have more than one class declaration per file)
      // Eventually we want this to be only for types of "Self"
      final localMembers = [
        ..._index.classes.expand(
          (c) => [
            ...membersFromMemberInfo(c.fields, Local(name: c.name)),
            ...membersFromMemberInfo(c.properties, Local(name: c.name)),
            ...membersFromMemberInfo(c.methods, Local(name: c.name)),
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

      logger.debug('member type $resolvedType and object Name $objectName');
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

    logger.debug('dealing with $context');
    return switch (context) {
      CompletionContextNone() => [],
      CompletionContextMember(:final typeName, :final objectName) =>
        completeMembersFromIndex(typeName, objectName),
      CompletionContextTopLevel() => completeTypesFromIndex(),
    };
  }
}

Iterable<Member> membersFromMemberInfo(
  Iterable<ApexMemberInfo> members,
  ApexType apexType,
) {
  return members.map((member) {
    return Member(
      name: member.name,
      parentType: apexType,
      type: member.isStatic ? MemberType.static : MemberType.instance,
    );
  });
}
