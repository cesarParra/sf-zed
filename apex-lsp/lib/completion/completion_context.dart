import 'package:apex_lsp/completion/helpers.dart';

sealed class CompletionContext {
  final String prefix;
  const CompletionContext({required this.prefix});
}

final class CompletionContextNone extends CompletionContext {
  const CompletionContextNone() : super(prefix: '');

  @override
  String toString() {
    return 'CompletionContextNone()';
  }
}

final class CompletionContextTopLevel extends CompletionContext {
  const CompletionContextTopLevel({
    required super.prefix,
    required this.text,
    required this.cursorOffset,
  });

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
    required super.prefix,
    required this.text,
    required this.cursorOffset,
  });

  final String? typeName;
  final String? objectName;
  final String text;
  final int cursorOffset;

  @override
  String toString() {
    return 'CompletionContextMember(objectName: $objectName, prefix: $prefix)';
  }
}

final class ContextDetector {
  const ContextDetector();

  Future<CompletionContext> detect({
    required String text,
    required int cursorOffset,
  }) async {
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

      return CompletionContextMember(
        typeName: objectName,
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

    final identifier = text.extractQualifiedIdentifierAt(i + 1);
    return identifier.isNotEmpty ? identifier : null;
  }
}
