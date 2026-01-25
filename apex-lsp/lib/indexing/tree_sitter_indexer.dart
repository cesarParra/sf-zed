import 'dart:convert';
import 'dart:ffi';

import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/indexing/tree_sitter_completion_types.dart';
import 'package:ffi/ffi.dart';

class TreeSitterIndexer {
  TreeSitterIndexer({required TreeSitterBindings bindings})
    : _bindings = bindings,
      _parser = bindings.ts_parser_new() {
    final language = _bindings.tree_sitter_apex();
    final ok = _bindings.ts_parser_set_language(_parser, language);
    if (ok == 0) {
      throw StateError('Failed to set Tree-sitter Apex language.');
    }
  }

  final TreeSitterBindings _bindings;
  final Pointer<TSParser> _parser;

  ApexDocumentIndex parseAndIndex(String text) {
    final bindings = _bindings;
    final parser = _parser;
    final sourceBytes = utf8.encode(text);
    final sourcePtr = text.toNativeUtf8();
    try {
      final tree = bindings.ts_parser_parse_string(
        parser,
        nullptr,
        sourcePtr,
        sourceBytes.length,
      );

      final root = bindings.ts_tree_root_node(tree);
      final index = _MutableApexDocumentIndex(text: text, bytes: sourceBytes);

      _collectDeclarations(root, index);

      bindings.ts_tree_delete(tree);
      return index.toPublicIndex();
    } finally {
      malloc.free(sourcePtr);
    }
  }

  void _collectDeclarations(TSNode root, _MutableApexDocumentIndex index) {
    final stack = <TSNode>[root];

    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      final type = _nodeType(node);

      if (type == 'class_declaration') {
        final classInfo = _extractClass(node, index);
        if (classInfo != null) {
          index.types.add(classInfo);
        }
      } else if (type == 'enum_declaration') {
        final enumInfo = _extractEnum(node, index);
        if (enumInfo != null) {
          index.types.add(enumInfo);
        }
      } else if (type == 'field_declaration' ||
          type == 'local_variable_declaration' ||
          type == 'formal_parameter') {
        final variables = _extractVariables(node, index, kind: type);
        index.variables.addAll(variables);
      }

      final namedCount = _bindings.ts_node_named_child_count(node);
      for (var i = 0; i < namedCount; i++) {
        stack.add(_bindings.ts_node_named_child(node, i));
      }
    }
  }

  String _nodeType(TSNode node) {
    final ptr = _bindings.ts_node_type(node);
    return ptr.toDartString();
  }

  ApexEnumInfo? _extractEnum(TSNode node, _MutableApexDocumentIndex index) {
    final nameNode = _getField(node, 'name');
    if (_isNullNode(nameNode)) return null;

    final enumName = _nodeText(nameNode, index);
    if (enumName.isEmpty) return null;

    final members = <ApexMemberInfo>[];
    final bodyNode = _getField(node, 'body');
    if (!_isNullNode(bodyNode)) {
      final constants = _collectDirectChildrenByType(bodyNode, 'enum_constant');
      for (final constant in constants) {
        final name = _nodeText(constant, index);
        if (name.isNotEmpty) {
          members.add(ApexMemberInfo(name: name, isStatic: true));
        }
      }
    }

    return ApexEnumInfo(
      name: enumName,
      startByte: _bindings.ts_node_start_byte(node),
      endByte: _bindings.ts_node_end_byte(node),
      members: members,
    );
  }

  ApexClassInfo? _extractClass(TSNode node, _MutableApexDocumentIndex index) {
    final nameNode = _getField(node, 'name');
    if (_isNullNode(nameNode)) return null;

    final className = _nodeText(nameNode, index);
    if (className.isEmpty) return null;

    final bodyNode = _getField(node, 'body');
    final members = <ApexMemberInfo>[];

    if (!_isNullNode(bodyNode)) {
      final fieldDeclarations = _collectDirectChildrenByType(
        bodyNode,
        'field_declaration',
      );
      for (final fieldDecl in fieldDeclarations) {
        final typeName = _extractTypeName(fieldDecl, index);
        if (typeName == null || typeName.isEmpty) continue;

        final isStatic = _hasStaticModifier(fieldDecl, index);

        final declarators = _collectDirectChildrenByType(
          fieldDecl,
          'variable_declarator',
        );
        for (final declarator in declarators) {
          final varName = _extractDeclaratorName(declarator, index);
          if (varName != null && varName.isNotEmpty) {
            final member = ApexMemberInfo(name: varName, isStatic: isStatic);
            members.add(member);
          }
        }
      }

      final methodDeclarations = _collectDirectChildrenByType(
        bodyNode,
        'method_declaration',
      );
      for (final methodDecl in methodDeclarations) {
        final name = _extractMemberName(methodDecl, index);
        if (name != null && name.isNotEmpty) {
          final isStatic = _hasStaticModifier(methodDecl, index);
          members.add(ApexMemberInfo(name: name, isStatic: isStatic));
        }
      }
    }

    final superclass = _extractSuperclass(node, index);

    return ApexClassInfo(
      name: className,
      startByte: _bindings.ts_node_start_byte(node),
      endByte: _bindings.ts_node_end_byte(node),
      members: members..sort((a, b) => a.name.compareTo(b.name)),
      superclass: superclass,
    );
  }

  TSNode _getField(TSNode node, String fieldName) {
    final fieldPtr = fieldName.toNativeUtf8();
    try {
      return _bindings.ts_node_child_by_field_name(
        node,
        fieldPtr,
        fieldName.length,
      );
    } finally {
      malloc.free(fieldPtr);
    }
  }

  List<ApexVariableInfo> _extractVariables(
    TSNode node,
    _MutableApexDocumentIndex index, {
    required String kind,
  }) {
    final typeName = _extractTypeName(node, index);
    if (typeName == null || typeName.isEmpty) return const [];

    final declarators = _collectDirectChildrenByType(
      node,
      'variable_declarator',
    );

    final variables = <ApexVariableInfo>[];
    if (declarators.isNotEmpty) {
      for (final declarator in declarators) {
        final name = _extractDeclaratorName(declarator, index);
        if (name == null || name.isEmpty) continue;
        variables.add(
          ApexVariableInfo(
            name: name,
            typeName: typeName,
            startByte: _bindings.ts_node_start_byte(declarator),
            endByte: _bindings.ts_node_end_byte(declarator),
            kind: kind,
          ),
        );
      }
      return variables;
    }

    // formal_parameter uses _variable_declarator_id (field name).
    final nameNode = _getField(node, 'name');
    if (!_isNullNode(nameNode)) {
      variables.add(
        ApexVariableInfo(
          name: _nodeText(nameNode, index),
          typeName: typeName,
          startByte: _bindings.ts_node_start_byte(node),
          endByte: _bindings.ts_node_end_byte(node),
          kind: kind,
        ),
      );
    }

    return variables;
  }

  bool _isNullNode(TSNode node) => node.id.address == 0;

  String _nodeText(TSNode node, _MutableApexDocumentIndex index) {
    final start = _bindings.ts_node_start_byte(node);
    final end = _bindings.ts_node_end_byte(node);
    if (start < 0 || end > index.bytes.length || start >= end) return '';
    return utf8.decode(index.bytes.sublist(start, end));
  }

  bool _hasStaticModifier(TSNode node, _MutableApexDocumentIndex index) {
    TSNode? modifiersNode;

    final childCount = _bindings.ts_node_named_child_count(node);
    for (var i = 0; i < childCount; i++) {
      final child = _bindings.ts_node_named_child(node, i);
      if (_nodeType(child) == 'modifiers') {
        modifiersNode = child;
        break;
      }
    }

    if (modifiersNode == null || _isNullNode(modifiersNode)) return false;

    final count = _bindings.ts_node_named_child_count(modifiersNode);
    for (var i = 0; i < count; i++) {
      final child = _bindings.ts_node_named_child(modifiersNode, i);
      final text = _nodeText(child, index);
      if (text.toLowerCase() == 'static') return true;
    }
    return false;
  }

  List<TSNode> _collectDirectChildrenByType(TSNode root, String typeName) {
    final matches = <TSNode>[];
    final namedCount = _bindings.ts_node_named_child_count(root);

    for (var i = 0; i < namedCount; i++) {
      final child = _bindings.ts_node_named_child(root, i);
      if (_nodeType(child) == typeName) {
        matches.add(child);
      }
    }

    return matches;
  }

  String? _extractSuperclass(
    TSNode classNode,
    _MutableApexDocumentIndex index,
  ) {
    final superclassNode = _getField(classNode, 'superclass');
    if (_isNullNode(superclassNode)) return null;

    return _extractTypeName(superclassNode, index);
  }

  String? _extractTypeName(TSNode node, _MutableApexDocumentIndex index) {
    final typeNode = _getField(node, 'type');
    final candidate = _isNullNode(typeNode) ? node : typeNode;

    final typeIdentifier = _findFirstNamedDescendantOfType(
      candidate,
      'type_identifier',
    );

    if (typeIdentifier != null && !_isNullNode(typeIdentifier)) {
      return _nodeText(typeIdentifier, index);
    }

    final identifier = _findFirstNamedDescendantOfType(candidate, 'identifier');
    if (identifier != null && !_isNullNode(identifier)) {
      return _nodeText(identifier, index);
    }

    return null;
  }

  String? _extractDeclaratorName(
    TSNode declarator,
    _MutableApexDocumentIndex index,
  ) {
    final nameNode = _getField(declarator, 'name');
    if (!_isNullNode(nameNode)) {
      return _nodeText(nameNode, index);
    }

    final fallback = _findFirstNamedDescendantOfType(declarator, 'identifier');
    if (fallback != null && !_isNullNode(fallback)) {
      return _nodeText(fallback, index);
    }

    return null;
  }

  String? _extractMemberName(TSNode node, _MutableApexDocumentIndex index) {
    final nameNode = _getField(node, 'name');
    if (!_isNullNode(nameNode)) {
      return _nodeText(nameNode, index);
    }

    final fallback = _findFirstNamedDescendantOfType(node, 'identifier');
    if (fallback != null && !_isNullNode(fallback)) {
      return _nodeText(fallback, index);
    }

    return null;
  }

  TSNode? _findFirstNamedDescendantOfType(TSNode node, String typeName) {
    final stack = <TSNode>[node];

    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      if (_nodeType(current) == typeName) {
        return current;
      }

      final namedCount = _bindings.ts_node_named_child_count(current);
      for (var i = 0; i < namedCount; i++) {
        stack.add(_bindings.ts_node_named_child(current, i));
      }
    }

    return null;
  }
}

final class _MutableApexDocumentIndex {
  _MutableApexDocumentIndex({required this.text, required this.bytes});

  final String text;
  final List<int> bytes;

  final List<TypeInfo> types = <TypeInfo>[];
  final List<ApexVariableInfo> variables = <ApexVariableInfo>[];

  ApexDocumentIndex toPublicIndex() {
    return ApexDocumentIndex(
      types: List<TypeInfo>.from(types),
      variables: List<ApexVariableInfo>.from(variables),
    );
  }
}
