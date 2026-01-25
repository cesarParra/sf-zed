import 'package:apex_lsp/indexing/tree_sitter_completion_types.dart';

enum ScopeType { file, typeDeclaration, methodBody, localBlock }

class Scope {
  Scope({
    required this.type,
    required this.startByte,
    required this.endByte,
    this.parent,
    this.isStatic = false,
    List<ApexEntity>? definitions,
    List<Scope>? children,
  }) : definitions = definitions ?? [],
       children = children ?? [];

  final ScopeType type;
  final int startByte;
  final int endByte;
  final bool isStatic;
  Scope? parent;
  final List<ApexEntity> definitions;
  final List<Scope> children;

  @override
  String toString() {
    return 'Scope(type: $type, start: $startByte, end: $endByte, static: $isStatic, defs: ${definitions.length}, children: ${children.length})';
  }
}
