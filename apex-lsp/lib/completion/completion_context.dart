import 'dart:convert';

import 'package:apex_lsp/completion/helpers.dart';
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
      return CompletionContextMember(
        typeName: _resolveTypeForObject(
          objectName: objectName,
          cursorByteOffset: cursorByteOffset,
        ),
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

    final identifier = text.extractIndentifierPrefixAt(i + 1);
    return identifier.isNotEmpty ? identifier : null;
  }

  String? _resolveTypeForObject({
    required String objectName,
    required int cursorByteOffset,
  }) {
    if (objectName == 'this') {
      final containing = _findClassAtOffset(_index, cursorByteOffset);
      return containing?.name;
    }
    if (objectName == 'super') {
      final containing = _findClassAtOffset(_index, cursorByteOffset);
      return containing?.superclass ?? containing?.name;
    }

    final variable = _resolveVariable(_index, objectName, cursorByteOffset);
    if (variable != null) {
      return variable.typeName;
    }

    // If the object name itself is a class name, treat as that type.
    final classInfo = _index.classByName(objectName);
    if (classInfo != null) {
      return classInfo.name;
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
