import 'dart:convert';
import 'dart:ffi';

import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/indexing/revamped.dart';
import 'package:apex_lsp/type_name.dart';
import 'package:ffi/ffi.dart';

class LocalIndexer {
  LocalIndexer({required TreeSitterBindings bindings})
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

  List<Declaration> parseAndIndex(String text) {
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

      List<int> bytes = sourceBytes;

      final indexedResult = _visit(root, bytes);

      bindings.ts_tree_delete(tree);
      return indexedResult;
    } finally {
      malloc.free(sourcePtr);
    }
  }

  List<Declaration> _visit(TSNode node, List<int> bytes, {int? scopeEnd}) {
    List<Declaration> results = [];
    final type = _nodeType(node);

    switch (type) {
      case 'enum_declaration':
        results.add(_extractEnum(node, bytes));
      case 'interface_declaration':
        results.add(_extractInterface(node, bytes));
      case 'method_declaration':
        results.addAll(_extractMethod(node, bytes));
      case 'local_variable_declaration':
        results.addAll(_extractVariables(node, bytes, scopeEnd: scopeEnd));
      default:
        results.addAll(_visitChildren(node, bytes, scopeEnd: scopeEnd));
    }
    return results;
  }

  List<Declaration> _visitChildren(
    TSNode node,
    List<int> bytes, {
    int? scopeEnd,
  }) {
    List<Declaration> results = [];
    final count = _bindings.ts_node_named_child_count(node);
    for (var i = 0; i < count; i++) {
      final child = _bindings.ts_node_named_child(node, i);
      results.addAll(_visit(child, bytes, scopeEnd: scopeEnd));
    }
    return results;
  }

  String _nodeType(TSNode node) {
    final ptr = _bindings.ts_node_type(node);
    return ptr.toDartString();
  }

  IndexedEnum _extractEnum(TSNode node, List<int> bytes) {
    final nameNode = _getField(node, 'name');

    final enumName = _nodeText(nameNode, bytes);

    final members = <EnumValueMember>[];
    final bodyNode = _getField(node, 'body');
    if (!_isNullNode(bodyNode)) {
      final constants = _collectDirectChildrenByType(bodyNode, 'enum_constant');
      for (final constant in constants) {
        final name = _nodeText(constant, bytes);
        if (name.isNotEmpty) {
          members.add(EnumValueMember(TypeName(name)));
        }
      }
    }

    return IndexedEnum(
      TypeName(enumName),
      location: (
        _bindings.ts_node_start_byte(node),
        _bindings.ts_node_end_byte(node),
      ),
      values: members,
    );
  }

  IndexedInterface _extractInterface(TSNode node, List<int> bytes) {
    final nameNode = _getField(node, 'name');
    final interfaceName = _nodeText(nameNode, bytes);

    final methods = <MethodDeclaration>[];
    final bodyNode = _getField(node, 'body');
    if (!_isNullNode(bodyNode)) {
      final methodNodes = _collectDirectChildrenByType(
        bodyNode,
        'method_declaration',
      );
      for (final methodNode in methodNodes) {
        final methodNameNode = _getField(methodNode, 'name');
        final name = _nodeText(methodNameNode, bytes);
        if (name.isNotEmpty) {
          methods.add(MethodDeclaration(TypeName(name), isStatic: false));
        }
      }
    }

    return IndexedInterface(
      TypeName(interfaceName),
      methods: methods,
      location: (
        _bindings.ts_node_start_byte(node),
        _bindings.ts_node_end_byte(node),
      ),
    );
  }

  List<Declaration> _extractMethod(TSNode node, List<int> bytes) {
    final nameNode = _getField(node, 'name');
    final name = _nodeText(nameNode, bytes);

    final results = <Declaration>[
      MethodDeclaration(
        TypeName(name),
        isStatic: false,
        location: (
          _bindings.ts_node_start_byte(node),
          _bindings.ts_node_end_byte(node),
        ),
      ),
    ];

    final bodyNode = _getField(node, 'body');
    final bodyScopeEnd = _isNullNode(bodyNode)
        ? null
        : _bindings.ts_node_end_byte(bodyNode);

    final parametersNode = _getField(node, 'parameters');
    if (!_isNullNode(parametersNode)) {
      final scopeVisibility = bodyScopeEnd != null
          ? VisibleBetweenDeclarationAndScopeEnd(scopeEnd: bodyScopeEnd)
          : null;
      final params = _collectDirectChildrenByType(
        parametersNode,
        'formal_parameter',
      );
      for (final param in params) {
        final paramTypeNode = _getField(param, 'type');
        final paramNameNode = _getField(param, 'name');
        final paramType = _nodeText(paramTypeNode, bytes);
        final paramName = _nodeText(paramNameNode, bytes);
        if (paramName.isNotEmpty) {
          results.add(
            IndexedVariable(
              TypeName(paramName),
              typeName: TypeName(paramType),
              location: (
                _bindings.ts_node_start_byte(param),
                _bindings.ts_node_end_byte(param),
              ),
              visibility: scopeVisibility,
            ),
          );
        }
      }
    }

    if (!_isNullNode(bodyNode)) {
      results.addAll(
        _visitChildren(bodyNode, bytes, scopeEnd: bodyScopeEnd),
      );
    }

    return results;
  }

  List<IndexedVariable> _extractVariables(
    TSNode node,
    List<int> bytes, {
    int? scopeEnd,
  }) {
    final typeNode = _getField(node, 'type');
    final typeName = _nodeText(typeNode, bytes);

    final visibility = scopeEnd != null
        ? VisibleBetweenDeclarationAndScopeEnd(scopeEnd: scopeEnd)
        : null;

    final results = <IndexedVariable>[];
    final childCount = _bindings.ts_node_named_child_count(node);
    for (var i = 0; i < childCount; i++) {
      final child = _bindings.ts_node_named_child(node, i);
      if (_nodeType(child) == 'variable_declarator') {
        final nameNode = _getField(child, 'name');
        final name = _nodeText(nameNode, bytes);
        if (name.isNotEmpty) {
          results.add(
            IndexedVariable(
              TypeName(name),
              typeName: TypeName(typeName),
              location: (
                _bindings.ts_node_start_byte(child),
                _bindings.ts_node_end_byte(child),
              ),
              visibility: visibility,
            ),
          );
        }
      }
    }
    return results;
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

  String _nodeText(TSNode node, List<int> bytes) {
    final start = _bindings.ts_node_start_byte(node);
    final end = _bindings.ts_node_end_byte(node);
    if (start < 0 || end > bytes.length || start >= end) return '';
    return utf8.decode(bytes.sublist(start, end));
  }

  bool _isNullNode(TSNode node) => node.id.address == 0;

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
}
