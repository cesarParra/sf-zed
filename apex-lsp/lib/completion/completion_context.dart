import 'dart:convert';

import 'package:apex_lsp/completion/helpers.dart';
import 'package:apex_lsp/indexing/scope.dart';
import 'package:apex_lsp/indexing/tree_sitter_completion_types.dart';

sealed class CompletionContext {
  const CompletionContext();
}

final class CompletionContextNone extends CompletionContext {
  const CompletionContextNone();

  @override
  String toString() {
    return 'CompletionContextNone()';
  }
}

final class CompletionContextTopLevel extends CompletionContext {
  const CompletionContextTopLevel({
    required this.prefix,
    required this.text,
    required this.cursorOffset,
  });

  final String prefix;
  final String text;
  final int cursorOffset;

  @override
  String toString() {
    return 'CompletionContextClass(className: $prefix)';
  }
}

final class CompletionContextMember extends CompletionContext {
  const CompletionContextMember({
    required this.objectName,
    required this.typeName,
    required this.prefix,
    required this.text,
    required this.cursorOffset,
  });

  final String? typeName;
  final String? objectName;
  final String prefix;
  final String text;
  final int cursorOffset;

  @override
  String toString() {
    return 'CompletionContextMember(objectName: $objectName, prefix: $prefix)';
  }
}

final class ContextDetector {
  ContextDetector({required ApexDocumentIndex index}) : _index = index;

  final ApexDocumentIndex _index;

  CompletionContext detect({required String text, required int cursorOffset}) {
    if (text.isEmpty || cursorOffset <= 0) {
      return const CompletionContextNone();
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
      if (objectName == null) {
        return CompletionContextNone();
      }

      final cursorByteOffset = _byteOffset(text, cursorOffset);
      final typeName =
          _resolveTypeForObject(
            objectName: objectName,
            cursorByteOffset: cursorByteOffset,
          ) ??
          objectName;
      return CompletionContextMember(
        typeName: typeName,
        objectName: objectName,
        prefix: prefix,
        text: text,
        cursorOffset: cursorOffset,
      );
    }

    return CompletionContextTopLevel(
      prefix: prefix,
      text: text,
      cursorOffset: cursorOffset,
    );
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

  bool _isWhitespace(int ch) {
    return ch == 32 || ch == 9 || ch == 10 || ch == 13;
  }

  String? _extractIdentifierBefore(String text, int index) {
    var i = index;
    while (i >= 0 && _isWhitespace(text.codeUnitAt(i))) {
      i--;
    }
    if (i < 0) return null;

    // Search backwards to include qualified names (e.g. A.B)
    final end = i + 1;
    while (i >= 0) {
      final ch = text.codeUnitAt(i);
      if (ch == 0x2E || ch.isIdentifierChar) {
        i--;
      } else {
        break;
      }
    }

    final start = i + 1;
    final identifier = text.substring(start, end).trim();
    return identifier.isNotEmpty ? identifier : null;
  }

  String? _resolveTypeForObject({
    required String objectName,
    required int cursorByteOffset,
  }) {
    if (objectName.toLowerCase() == 'this') {
      final containing = _findTypeAtOffset(_index, cursorByteOffset);
      return containing?.name;
    }
    if (objectName.toLowerCase() == 'super') {
      final containing = _findTypeAtOffset(_index, cursorByteOffset);
      if (containing is ApexClassInfo) {
        return containing.superclass ?? containing.name;
      }
      return containing?.name;
    }

    final variable = _resolveVariable(_index, objectName, cursorByteOffset);
    if (variable != null) {
      return variable.typeName;
    }

    // If the object name itself is a class name, treat as that type.
    final typeInfo = _index.typeByName(objectName);
    if (typeInfo != null) {
      // Return the qualified name to ensure it can be resolved again later.
      return objectName;
    }

    return null;
  }

  int _byteOffset(String text, int codeUnitOffset) {
    if (codeUnitOffset <= 0) return 0;
    if (codeUnitOffset >= text.length) {
      return utf8.encode(text).length;
    }
    return utf8.encode(text.substring(0, codeUnitOffset)).length;
  }

  TypeInfo? _findTypeAtOffset(ApexDocumentIndex index, int offset) {
    for (final typeInfo in index.rootScope.definitions.whereType<TypeInfo>()) {
      if (offset >= typeInfo.startByte && offset <= typeInfo.endByte) {
        return typeInfo;
      }
    }
    return null;
  }

  ApexVariableInfo? _resolveVariable(
    ApexDocumentIndex index,
    String name,
    int cursorByteOffset,
  ) {
    var scope = _findScope(index.rootScope, cursorByteOffset);
    while (scope != null) {
      for (final def in scope.definitions) {
        if (def is ApexVariableInfo && def.name == name) {
          if (def.startByte < cursorByteOffset) {
            return def;
          }
        }
      }
      scope = scope.parent;
    }
    return null;
  }

  Scope? _findScope(Scope scope, int offset) {
    if (offset < scope.startByte || offset > scope.endByte) {
      return null;
    }

    for (final child in scope.children) {
      final result = _findScope(child, offset);
      if (result != null) return result;
    }

    return scope;
  }
}
