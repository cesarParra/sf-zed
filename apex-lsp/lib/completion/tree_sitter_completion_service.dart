import 'dart:convert';
import 'dart:ffi';

import 'package:apex_lsp/completion/helpers.dart';
import 'package:apex_lsp/di.dart';
import 'package:apex_lsp/lsp_out.dart';
import 'package:ffi/ffi.dart';

import 'tree_sitter_bindings.dart';
import 'tree_sitter_completion_types.dart';

final logger = locator<LspOut>();

final class TreeSitterCompletionService {
  TreeSitterCompletionService({
    required TreeSitterBindings bindings,
    ApexIndexBuilder? indexBuilder,
  }) : _bindings = bindings {
    _indexBuilder = indexBuilder ?? _parseAndIndex;
    _parser = _bindings!.ts_parser_new();
    final language = _bindings.tree_sitter_apex();
    final ok = _bindings.ts_parser_set_language(_parser!, language);
    if (ok == 0) {
      throw StateError('Failed to set Tree-sitter Apex language.');
    }
  }

  // TODO: Get rid of this testOnly stuff.
  TreeSitterCompletionService.testOnly({required ApexIndexBuilder indexBuilder})
    : _bindings = null,
      _indexBuilder = indexBuilder,
      _parser = null;

  final TreeSitterBindings? _bindings;
  late final ApexIndexBuilder _indexBuilder;
  late final Pointer<TSParser>? _parser;

  void dispose() {
    final parser = _parser;
    final bindings = _bindings;
    if (parser == null || bindings == null) return;
    bindings.ts_parser_delete(parser);
  }

  CompletionCandidates suggest({
    required String text,
    required int cursorOffset,
  }) {
    final context = _detectContext(text, cursorOffset);
    if (context.kind == CompletionKind.none) {
      return CompletionCandidates(kind: CompletionKind.none, labels: const []);
    }

    final cursorByteOffset = _byteOffset(text, cursorOffset);
    final index = _indexBuilder(text);
    for (final currentClass in index.classes) {
      logger.debug('Indexed open file: ${currentClass.name}');
      logger.debug('Indexed open file - fields: ${currentClass.fields}');
      logger.debug(
        'Indexed open file - properties: ${currentClass.properties}',
      );
      logger.debug('Indexed open methods: ${currentClass.methods}');
    }

    for (final variable in index.variables) {
      logger.debug('Indexeed variable: ${variable.name}');
    }

    if (context.kind == .member) {
      final objectName = context.objectName;
      if (objectName == null || objectName.isEmpty) {
        return CompletionCandidates(kind: .member, labels: const []);
      }

      final resolvedType = _resolveTypeForObject(
        objectName: objectName,
        cursorByteOffset: cursorByteOffset,
        index: index,
      );

      if (resolvedType == null) {
        return CompletionCandidates(
          kind: CompletionKind.member,
          labels: const [],
        );
      }

      final classInfo = index.classByName(resolvedType);
      if (classInfo == null) {
        return CompletionCandidates(
          kind: .member,
          labels: const [],
          memberOfType: resolvedType,
          memberTypeResolvedFromDocument: false,
        );
      }

      final prefix = context.prefix.toLowerCase();
      final memberSet = <String>{
        ...classInfo.fields,
        ...classInfo.properties,
        ...classInfo.methods,
      };
      final members =
          memberSet
              .where(
                (name) =>
                    prefix.isEmpty || name.toLowerCase().startsWith(prefix),
              )
              .toList()
            ..sort();

      return CompletionCandidates(
        kind: .member,
        labels: members,
        memberOfType: resolvedType,
        memberTypeResolvedFromDocument: true,
      );
    }

    // Class name and local variable declaration completion.
    // TODO: The way we are treating local variable declarations is pretty naive, since we don't
    // care in which scope they were found. Variable declarations should only show up if the user
    // is typing within the scope where it was declared (and before the currrent index)
    final prefix = context.prefix.toLowerCase();
    final all = {
      ...index.variables.map((v) => v.name).toList()..sort(),
      ...index.classes.map((c) => c.name).toList()..sort(),
    };
    final classNames = all
        .where(
          (name) => prefix.isEmpty || name.toLowerCase().startsWith(prefix),
        )
        .toList();

    return CompletionCandidates(kind: .className, labels: classNames);
  }

  _CompletionContext _detectContext(String text, int cursorOffset) {
    if (text.isEmpty || cursorOffset <= 0) {
      return const _CompletionContext(kind: .none);
    }

    final prefix = text.extractIndentifierPrefixAt(cursorOffset);

    // Member access: "foo." or "foo?."
    var dotIndex = _findMemberDotIndex(text, cursorOffset);

    // If we're typing a member name (e.g., "foo.ba"), look just before the prefix
    // to detect the member access.
    if (dotIndex == null && prefix.isNotEmpty) {
      final probeIndex = cursorOffset - prefix.length - 1;
      if (probeIndex >= 0) {
        final ch = text.codeUnitAt(probeIndex);
        if (ch == 0x2E /* . */ ) {
          dotIndex = probeIndex;
        } else if (ch == 0x3F /* ? */ ) {
          final next = probeIndex + 1;
          if (next < text.length && text.codeUnitAt(next) == 0x2E /* . */ ) {
            dotIndex = next;
          }
        }
      }
    }

    if (dotIndex != null) {
      var objectIndex = dotIndex - 1;
      if (objectIndex >= 0 && text.codeUnitAt(objectIndex) == 0x3F /* ? */ ) {
        objectIndex--;
      }
      final objectName = _extractIdentifierBefore(text, objectIndex);
      return _CompletionContext(
        kind: CompletionKind.member,
        prefix: prefix,
        objectName: objectName,
      );
    }

    return _CompletionContext(kind: CompletionKind.className, prefix: prefix);
  }

  int _byteOffset(String text, int codeUnitOffset) {
    if (codeUnitOffset <= 0) return 0;
    if (codeUnitOffset >= text.length) {
      return utf8.encode(text).length;
    }
    return utf8.encode(text.substring(0, codeUnitOffset)).length;
  }

  int? _findMemberDotIndex(String text, int cursorOffset) {
    var i = cursorOffset - 1;
    if (i < 0) return null;

    // Skip whitespace between dot and cursor (rare but possible).
    while (i >= 0 && _isWhitespace(text.codeUnitAt(i))) {
      i--;
    }
    if (i < 0) return null;

    final ch = text.codeUnitAt(i);

    if (ch == 0x2E /* . */ ) {
      return i;
    }

    if (ch == 0x3F /* ? */ ) {
      final next = i + 1;
      if (next < text.length && text.codeUnitAt(next) == 0x2E /* . */ ) {
        return next;
      }

      final prev = i - 1;
      if (prev >= 0 && text.codeUnitAt(prev) == 0x2E /* . */ ) {
        return prev;
      }
    }

    return null;
  }

  String? _extractIdentifierBefore(String text, int index) {
    var i = index;
    while (i >= 0 && _isWhitespace(text.codeUnitAt(i))) {
      i--;
    }
    if (i < 0) return null;

    var end = i + 1;
    var start = i;
    while (start >= 0 && text.codeUnitAt(start).isIdentifierChar) {
      start--;
    }
    start++;

    if (start < end) {
      return text.substring(start, end);
    }
    return null;
  }

  bool _isWhitespace(int ch) {
    return ch == 32 || ch == 9 || ch == 10 || ch == 13;
  }

  String? _resolveTypeForObject({
    required String objectName,
    required int cursorByteOffset,
    required ApexDocumentIndex index,
  }) {
    if (objectName == 'this') {
      final containing = _findClassAtOffset(index, cursorByteOffset);
      return containing?.name;
    }
    if (objectName == 'super') {
      final containing = _findClassAtOffset(index, cursorByteOffset);
      return containing?.superclass ?? containing?.name;
    }

    final variable = _resolveVariable(index, objectName, cursorByteOffset);
    if (variable != null) {
      return variable.typeName;
    }

    // If the object name itself is a class name, treat as that type.
    final classInfo = index.classByName(objectName);
    if (classInfo != null) {
      return classInfo.name;
    }

    return null;
  }

  ApexDocumentIndex _parseAndIndex(String text) {
    final bindings = _bindings;
    final parser = _parser;
    if (bindings == null || parser == null) {
      throw StateError('Tree-sitter bindings are not available.');
    }
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
          index.classes.add(classInfo);
        }
      } else if (type == 'field_declaration' ||
          type == 'local_variable_declaration' ||
          type == 'formal_parameter') {
        final variables = _extractVariables(node, index, kind: type);
        index.variables.addAll(variables);
      }

      final namedCount = _bindings!.ts_node_named_child_count(node);
      for (var i = 0; i < namedCount; i++) {
        stack.add(_bindings.ts_node_named_child(node, i));
      }
    }
  }

  ApexClassInfo? _extractClass(TSNode node, _MutableApexDocumentIndex index) {
    final nameNode = _getField(node, 'name');
    if (_isNullNode(nameNode)) return null;

    final className = _nodeText(nameNode, index);
    if (className.isEmpty) return null;

    final bodyNode = _getField(node, 'body');
    final fields = <String>{};
    final properties = <String>{};
    final methods = <String>{};

    if (!_isNullNode(bodyNode)) {
      final fieldDeclarations = _collectClassBodyFieldDeclarations(bodyNode);
      for (final fieldDecl in fieldDeclarations) {
        final typeName = _extractTypeName(fieldDecl, index);
        if (typeName == null || typeName.isEmpty) continue;

        final declarators = _collectNamedDescendantsByType(
          fieldDecl,
          'variable_declarator',
        );
        for (final declarator in declarators) {
          final varName = _extractDeclaratorName(declarator, index);
          if (varName != null && varName.isNotEmpty) {
            fields.add(varName);
          }
        }
      }

      final propertyDeclarations = _collectNamedDescendantsByType(
        bodyNode,
        'property_declaration',
      );
      for (final propertyDecl in propertyDeclarations) {
        final name = _extractMemberName(propertyDecl, index);
        if (name != null && name.isNotEmpty) {
          properties.add(name);
        }
      }

      final methodDeclarations = _collectNamedDescendantsByType(
        bodyNode,
        'method_declaration',
      );
      for (final methodDecl in methodDeclarations) {
        final name = _extractMemberName(methodDecl, index);
        if (name != null && name.isNotEmpty) {
          methods.add(name);
        }
      }
    }

    final superclass = _extractSuperclass(node, index);

    return ApexClassInfo(
      name: className,
      startByte: _bindings!.ts_node_start_byte(node),
      endByte: _bindings.ts_node_end_byte(node),
      fields: fields.toList()..sort(),
      properties: properties.toList()..sort(),
      methods: methods.toList()..sort(),
      superclass: superclass,
    );
  }

  List<ApexVariableInfo> _extractVariables(
    TSNode node,
    _MutableApexDocumentIndex index, {
    required String kind,
  }) {
    final typeName = _extractTypeName(node, index);
    if (typeName == null || typeName.isEmpty) return const [];

    final declarators = _collectNamedDescendantsByType(
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
            startByte: _bindings!.ts_node_start_byte(declarator),
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
          startByte: _bindings!.ts_node_start_byte(node),
          endByte: _bindings.ts_node_end_byte(node),
          kind: kind,
        ),
      );
    }

    return variables;
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

  List<TSNode> _collectClassBodyFieldDeclarations(TSNode classBody) {
    final matches = <TSNode>[];
    final namedCount = _bindings!.ts_node_named_child_count(classBody);

    for (var i = 0; i < namedCount; i++) {
      final child = _bindings.ts_node_named_child(classBody, i);
      if (_nodeType(child) == 'field_declaration') {
        matches.add(child);
      }
    }

    return matches;
  }

  List<TSNode> _collectNamedDescendantsByType(TSNode root, String typeName) {
    final matches = <TSNode>[];
    final stack = <TSNode>[root];

    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (_nodeType(node) == typeName) {
        matches.add(node);
      }

      final namedCount = _bindings!.ts_node_named_child_count(node);
      for (var i = 0; i < namedCount; i++) {
        stack.add(_bindings.ts_node_named_child(node, i));
      }
    }

    return matches;
  }

  TSNode _getField(TSNode node, String fieldName) {
    final fieldPtr = fieldName.toNativeUtf8();
    try {
      return _bindings!.ts_node_child_by_field_name(
        node,
        fieldPtr,
        fieldName.length,
      );
    } finally {
      malloc.free(fieldPtr);
    }
  }

  TSNode? _findFirstNamedDescendantOfType(TSNode node, String typeName) {
    final stack = <TSNode>[node];

    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      if (_nodeType(current) == typeName) {
        return current;
      }

      final namedCount = _bindings!.ts_node_named_child_count(current);
      for (var i = 0; i < namedCount; i++) {
        stack.add(_bindings.ts_node_named_child(current, i));
      }
    }

    return null;
  }

  bool _isNullNode(TSNode node) => node.id.address == 0;

  String _nodeType(TSNode node) {
    final ptr = _bindings!.ts_node_type(node);
    return ptr.toDartString();
  }

  String _nodeText(TSNode node, _MutableApexDocumentIndex index) {
    final start = _bindings!.ts_node_start_byte(node);
    final end = _bindings.ts_node_end_byte(node);
    if (start < 0 || end > index.bytes.length || start >= end) return '';
    return utf8.decode(index.bytes.sublist(start, end));
  }

  ApexClassInfo? _findClassAtOffset(ApexDocumentIndex index, int offset) {
    for (final c in index.classes) {
      if (offset >= c.startByte && offset <= c.endByte) {
        return c;
      }
    }
    return null;
  }

  ApexVariableInfo? _resolveVariable(
    ApexDocumentIndex index,
    String name,
    int cursorByteOffset,
  ) {
    ApexVariableInfo? best;
    for (final v in index.variables) {
      if (v.name != name) continue;
      if (v.startByte > cursorByteOffset) continue;

      if (best == null || v.startByte > best.startByte) {
        best = v;
      }
    }
    return best;
  }
}

final class _CompletionContext {
  const _CompletionContext({
    required this.kind,
    this.prefix = '',
    this.objectName,
  });

  final CompletionKind kind;
  final String prefix;
  final String? objectName;
}

final class _MutableApexDocumentIndex {
  _MutableApexDocumentIndex({required this.text, required this.bytes});

  final String text;
  final List<int> bytes;

  final List<ApexClassInfo> classes = <ApexClassInfo>[];
  final List<ApexVariableInfo> variables = <ApexVariableInfo>[];

  ApexDocumentIndex toPublicIndex() {
    return ApexDocumentIndex(
      classes: List<ApexClassInfo>.from(classes),
      variables: List<ApexVariableInfo>.from(variables),
    );
  }
}
