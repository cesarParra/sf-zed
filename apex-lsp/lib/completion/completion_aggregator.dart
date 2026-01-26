import 'dart:async';

import 'package:apex_lsp/completion/completion.dart';
import 'package:apex_lsp/completion/completion_context.dart';
import 'package:apex_lsp/di.dart';
import 'package:apex_lsp/indexing/indexed_class.dart' as indexed_class;
import 'package:apex_lsp/indexing/scope.dart';
import 'package:apex_lsp/indexing/tree_sitter_completion_types.dart';
import 'package:apex_lsp/lsp_out.dart';

final logger = locator<LspOut>();

/// Aggregates completion candidates from the open document (Tree-sitter)
/// and workspace index (.sf-zed JSON file repository).
final class CompletionAggregator implements CompletionSuggestion {
  final CompletionSuggestion localSuggestion;
  final CompletionSuggestion indexedSuggestion;

  CompletionAggregator({
    required this.localSuggestion,
    required this.indexedSuggestion,
  });

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
    return switch (context) {
      CompletionContextNone() => [],
      CompletionContextMember(
        :final text,
        :final cursorOffset,
        :final objectName,
        :final typeName,
      ) =>
        _completeMembers(
          text: text,
          cursorOffset: cursorOffset,
          objectName: objectName,
          typeName: typeName,
        ),
      CompletionContextTopLevel(:final cursorOffset) => _completeTopLevel(
        cursorOffset: cursorOffset,
      ),
    };
  }

  List<CompletionCandidate> _completeMembers({
    required String text,
    required int cursorOffset,
    required String? objectName,
    required String? typeName,
  }) {
    logger.debug(
      'Completing member. Object name: $objectName, Type name: $typeName',
    );
    if (typeName == null || objectName == null) {
      return [];
    }

    final typeInfo = _index.typeByName(typeName);
    logger.debug('Found type info $typeInfo');
    if (typeInfo == null) {
      return [];
    }

    final isStaticAccess = typeName.toLowerCase() == objectName.toLowerCase();

    // If it is an Enum, we only allow static access.
    if (typeInfo is ApexEnumInfo && !isStaticAccess) {
      return [];
    }

    final targetMemberType = isStaticAccess
        ? MemberType.static
        : MemberType.instance;

    final apexType = Local(name: typeInfo.name);
    final members = membersFromMemberInfo(
      typeInfo.members,
      apexType,
    ).where((m) => m.type == targetMemberType);

    return members.map(MemberCandidate.new).toList();
  }

  List<CompletionCandidate> _completeTopLevel({required int cursorOffset}) {
    final candidates = <CompletionCandidate>[];
    var currentScope = _findScope(_index.rootScope, cursorOffset);

    // Track if we are inside a static context (e.g. static method)
    // to filter out instance members of enclosing classes.
    var insideStaticContext = false;

    while (currentScope != null) {
      if (currentScope.type == ScopeType.methodBody && currentScope.isStatic) {
        insideStaticContext = true;
      }

      final isLocalScope =
          currentScope.type == ScopeType.methodBody ||
          currentScope.type == ScopeType.localBlock;

      for (final def in currentScope.definitions) {
        switch (def) {
          case ApexVariableInfo variable:
            // Local variables must be declared before use (endByte < cursorOffset)
            if (isLocalScope) {
              if (variable.endByte < cursorOffset) {
                candidates.add(LocalVariableCandidate(variable.name));
              }
            } else {
              // Should not happen based on current indexer logic (vars only in methods/blocks),
              // but if global vars existed they might be visible.
              candidates.add(LocalVariableCandidate(variable.name));
            }

          case ApexMemberInfo member:
            // Members (Fields/Properties/Methods) are visible if we are in a class body.
            // If we are inside a static context, we can only see static members.
            if (!insideStaticContext || member.isStatic) {
              // Try to find enclosing type name from parent scope for "Self"
              String typeName = 'Self';
              final parent = currentScope.parent;
              if (parent != null) {
                // The TypeInfo entity lives in the parent scope of the Class Body Scope
                // matching the range of the class body scope.
                for (final parentDef in parent.definitions) {
                  if (parentDef is TypeInfo &&
                      parentDef.startByte == currentScope.startByte &&
                      parentDef.endByte == currentScope.endByte) {
                    typeName = parentDef.name;
                    break;
                  }
                }
              }

              candidates.add(
                MemberCandidate(
                  Member(
                    name: member.name,
                    parentType: Self(name: typeName),
                    type: member.isStatic
                        ? MemberType.static
                        : MemberType.instance,
                  ),
                ),
              );
            }

          case TypeInfo type:
            // Types (classes, enums, interfaces) are always visible if in scope
            candidates.add(ApexTypeCandidate(Local(name: type.name)));
        }
      }

      currentScope = currentScope.parent;
    }

    return candidates;
  }

  Scope? _findScope(Scope scope, int offset) {
    // Check if offset is within this scope
    if (offset < scope.startByte || offset > scope.endByte) {
      return null;
    }

    // Check children (deepest first)
    for (final child in scope.children) {
      final result = _findScope(child, offset);
      if (result != null) {
        return result;
      }
    }

    return scope;
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
