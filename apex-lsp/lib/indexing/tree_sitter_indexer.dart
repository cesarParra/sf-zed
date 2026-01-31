import 'dart:convert';
import 'dart:ffi';

import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/indexing/scope.dart';
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
      final rootScope = Scope(
        type: ScopeType.file,
        startByte: bindings.ts_node_start_byte(root),
        endByte: bindings.ts_node_end_byte(root),
      );

      final index = _MutableApexDocumentIndex(
        text: text,
        bytes: sourceBytes,
        rootScope: rootScope,
      );

      _visit(root, rootScope, index);

      bindings.ts_tree_delete(tree);
      return index.toPublicIndex();
    } finally {
      malloc.free(sourcePtr);
    }
  }

  void _visit(TSNode node, Scope scope, _MutableApexDocumentIndex index) {
    final type = _nodeType(node);

    if (type == 'class_declaration') {
      final info = _extractClass(node, index);
      if (info != null) {
        scope.definitions.add(info);
        final classScope = Scope(
          type: ScopeType.typeDeclaration,
          startByte: _bindings.ts_node_start_byte(node),
          endByte: _bindings.ts_node_end_byte(node),
          parent: scope,
        );
        scope.children.add(classScope);
        for (final member in info.members) {
          if (member is! NestedTypeMember) {
            classScope.definitions.add(member);
          }
        }
        _visitChildren(node, classScope, index);
      }
    } else if (type == 'interface_declaration') {
      final info = _extractInterface(node, index);
      if (info != null) {
        scope.definitions.add(info);
        final interfaceScope = Scope(
          type: ScopeType.typeDeclaration,
          startByte: _bindings.ts_node_start_byte(node),
          endByte: _bindings.ts_node_end_byte(node),
          parent: scope,
        );
        scope.children.add(interfaceScope);
        for (final member in info.members) {
          if (member is! NestedTypeMember) {
            interfaceScope.definitions.add(member);
          }
        }
        _visitChildren(node, interfaceScope, index);
      }
    } else if (type == 'enum_declaration') {
      final info = _extractEnum(node, index);
      if (info != null) {
        scope.definitions.add(info);
        // We don't recurse into enum body for scopes currently.
      }
    } else if (type == 'method_declaration') {
      // If this is a root-level method (scope is file-level), add it as a member
      if (scope.type == ScopeType.file) {
        final name = _extractMemberName(node, index);
        if (name != null && name.isNotEmpty) {
          final isStatic = _hasStaticModifier(node, index);
          final typeName = _extractTypeName(node, index);
          scope.definitions.add(
            ApexMemberInfo(name: name, isStatic: isStatic, typeName: typeName),
          );
        }
      }

      final methodScope = Scope(
        type: ScopeType.methodBody,
        startByte: _bindings.ts_node_start_byte(node),
        endByte: _bindings.ts_node_end_byte(node),
        parent: scope,
        isStatic: _hasStaticModifier(node, index),
      );
      scope.children.add(methodScope);
      _visitChildren(node, methodScope, index);
    } else if (type == 'constructor_declaration') {
      final methodScope = Scope(
        type: ScopeType.methodBody,
        startByte: _bindings.ts_node_start_byte(node),
        endByte: _bindings.ts_node_end_byte(node),
        parent: scope,
        isStatic: false,
      );
      scope.children.add(methodScope);
      _visitChildren(node, methodScope, index);
    } else if (type == 'static_initializer') {
      final blockScope = Scope(
        type: ScopeType.localBlock,
        startByte: _bindings.ts_node_start_byte(node),
        endByte: _bindings.ts_node_end_byte(node),
        parent: scope,
        isStatic: true,
      );
      scope.children.add(blockScope);
      _visitChildren(node, blockScope, index);
    } else if (type == 'block') {
      final blockScope = Scope(
        type: ScopeType.localBlock,
        startByte: _bindings.ts_node_start_byte(node),
        endByte: _bindings.ts_node_end_byte(node),
        parent: scope,
      );
      scope.children.add(blockScope);
      _visitChildren(node, blockScope, index);
    } else if (type == 'local_variable_declaration') {
      final vars = _extractVariables(node, index, kind: type);
      scope.definitions.addAll(vars);
    } else if (type == 'formal_parameter') {
      final vars = _extractVariables(node, index, kind: type);
      scope.definitions.addAll(vars);
    } else if (type == 'field_declaration') {
      // Already handled by _extractClass/Interface for the definition.
      // We do not recurse into field declarations.
    } else {
      _visitChildren(node, scope, index);
    }
  }

  void _visitChildren(
    TSNode node,
    Scope scope,
    _MutableApexDocumentIndex index,
  ) {
    final count = _bindings.ts_node_named_child_count(node);
    for (var i = 0; i < count; i++) {
      final child = _bindings.ts_node_named_child(node, i);
      _visit(child, scope, index);
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
            final member = ApexMemberInfo(
              name: varName,
              isStatic: isStatic,
              typeName: typeName,
            );
            members.add(member);
          }
        }
      }

      final propertyDeclarations = _collectDirectChildrenByType(
        bodyNode,
        'property_declaration',
      );
      for (final propertyDecl in propertyDeclarations) {
        final name = _extractMemberName(propertyDecl, index);
        if (name != null && name.isNotEmpty) {
          final isStatic = _hasStaticModifier(propertyDecl, index);
          final typeName = _extractTypeName(propertyDecl, index);
          members.add(
            ApexMemberInfo(name: name, isStatic: isStatic, typeName: typeName),
          );
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
          final typeName = _extractTypeName(methodDecl, index);
          members.add(
            ApexMemberInfo(name: name, isStatic: isStatic, typeName: typeName),
          );
        }
      }

      final innerClasses = _collectDirectChildrenByType(
        bodyNode,
        'class_declaration',
      );
      for (final innerClass in innerClasses) {
        final info = _extractClass(innerClass, index);
        if (info != null) {
          members.add(NestedTypeMember(typeInfo: info));
        }
      }

      final innerInterfaces = _collectDirectChildrenByType(
        bodyNode,
        'interface_declaration',
      );
      for (final innerInterface in innerInterfaces) {
        final info = _extractInterface(innerInterface, index);
        if (info != null) {
          members.add(NestedTypeMember(typeInfo: info));
        }
      }

      final innerEnums = _collectDirectChildrenByType(
        bodyNode,
        'enum_declaration',
      );
      for (final innerEnum in innerEnums) {
        final info = _extractEnum(innerEnum, index);
        if (info != null) {
          members.add(NestedTypeMember(typeInfo: info));
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

  ApexInterfaceInfo? _extractInterface(
    TSNode node,
    _MutableApexDocumentIndex index,
  ) {
    final nameNode = _getField(node, 'name');
    if (_isNullNode(nameNode)) return null;

    final interfaceName = _nodeText(nameNode, index);
    if (interfaceName.isEmpty) return null;

    final bodyNode = _getField(node, 'body');
    final members = <ApexMemberInfo>[];

    if (!_isNullNode(bodyNode)) {
      final methodDeclarations = _collectDirectChildrenByType(
        bodyNode,
        'method_declaration',
      );
      for (final methodDecl in methodDeclarations) {
        final name = _extractMemberName(methodDecl, index);
        if (name != null && name.isNotEmpty) {
          final isStatic = _hasStaticModifier(methodDecl, index);
          final typeName = _extractTypeName(methodDecl, index);
          members.add(
            ApexMemberInfo(name: name, isStatic: isStatic, typeName: typeName),
          );
        }
      }

      final innerClasses = _collectDirectChildrenByType(
        bodyNode,
        'class_declaration',
      );
      for (final innerClass in innerClasses) {
        final info = _extractClass(innerClass, index);
        if (info != null) {
          members.add(NestedTypeMember(typeInfo: info));
        }
      }

      final innerInterfaces = _collectDirectChildrenByType(
        bodyNode,
        'interface_declaration',
      );
      for (final innerInterface in innerInterfaces) {
        final info = _extractInterface(innerInterface, index);
        if (info != null) {
          members.add(NestedTypeMember(typeInfo: info));
        }
      }

      final innerEnums = _collectDirectChildrenByType(
        bodyNode,
        'enum_declaration',
      );
      for (final innerEnum in innerEnums) {
        final info = _extractEnum(innerEnum, index);
        if (info != null) {
          members.add(NestedTypeMember(typeInfo: info));
        }
      }
    }

    return ApexInterfaceInfo(
      name: interfaceName,
      startByte: _bindings.ts_node_start_byte(node),
      endByte: _bindings.ts_node_end_byte(node),
      members: members,
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

    final scopedTypeIdentifier = _findFirstNamedDescendantOfType(
      candidate,
      'scoped_type_identifier',
    );

    if (scopedTypeIdentifier != null && !_isNullNode(scopedTypeIdentifier)) {
      return _nodeText(scopedTypeIdentifier, index);
    }

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
  _MutableApexDocumentIndex({
    required this.text,
    required this.bytes,
    required this.rootScope,
  });

  final String text;
  final List<int> bytes;
  final Scope rootScope;

  ApexDocumentIndex toPublicIndex() {
    return ApexDocumentIndex(rootScope: rootScope);
  }
}
