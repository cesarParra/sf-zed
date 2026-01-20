import 'package:apex_lsp/completion/completion_context.dart';

extension IntCompletionExtension on int {
  /// Whether the character is an Apex identifier or not.
  /// An identifier matches the following rules:
  /// - Letters (A-Z, a-z)
  /// - Digits (0-9)
  /// - Underscore (_)
  /// - Dollar sign ($)
  bool get isIdentifierChar {
    return (this >= 48 && this <= 57) || // 0-9
        (this >= 65 && this <= 90) || // A-Z
        (this >= 97 && this <= 122) || // a-z
        this == 95 || // _
        this == 36; // $
  }
}

extension StringCompletionExtension on String {
  /// Extracts the identifier prefix immediately before the cursor offset.
  /// Scans backward from the cursor position to find the start of an identifier.
  ///
  /// This prefix is used to filter completion candidates and compute ranking.
  ///
  /// - [text]: The complete text content.
  /// - [cursorOffset]: Zero-based byte offset of the cursor position.
  ///
  /// Returns the identifier prefix as a string, which may be empty if the cursor
  /// is not positioned after an identifier character.
  ///
  /// Example:
  /// ```dart
  /// final prefix = _extractPrefixFromText(
  ///   text: 'System.debug(myVar)',
  ///   cursorOffset: 12, // Position after 'myVar'
  /// );
  /// print(prefix); // 'myVar'
  /// ```
  String extractIndentifierPrefixAt(int cursorOffset) {
    var i = cursorOffset;
    if (i > length) i = length;

    var start = i;
    while (start > 0 && codeUnitAt(start - 1).isIdentifierChar) {
      start--;
    }
    return substring(start, i);
  }

  CompletionContext detectContext(int cursorOffset) {
    if (isEmpty || cursorOffset <= 0) {
      return const CompletionContextNone();
    }

    final prefix = extractIndentifierPrefixAt(cursorOffset);

    // Member access: "foo." or "foo?."
    var dotIndex = _findMemberDotIndex(this, cursorOffset);

    // If we're typing a member name (e.g., "foo.ba"), look just before the prefix
    // to detect the member access.
    if (dotIndex == null && prefix.isNotEmpty) {
      final probeIndex = cursorOffset - prefix.length - 1;
      if (probeIndex >= 0) {
        final ch = codeUnitAt(probeIndex);
        if (ch == 0x2E /* . */ ) {
          dotIndex = probeIndex;
        } else if (ch == 0x3F /* ? */ ) {
          final next = probeIndex + 1;
          if (next < length && codeUnitAt(next) == 0x2E /* . */ ) {
            dotIndex = next;
          }
        }
      }
    }

    if (dotIndex != null) {
      var objectIndex = dotIndex - 1;
      if (objectIndex >= 0 && codeUnitAt(objectIndex) == 0x3F /* ? */ ) {
        objectIndex--;
      }
      final objectName = _extractIdentifierBefore(this, objectIndex);
      return CompletionContextMember(objectName: objectName, prefix: prefix);
    }

    return CompletionContextClass(className: prefix);
  }
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

  final identifier = text.extractIndentifierPrefixAt(i + 1);
  return identifier.isNotEmpty ? identifier : null;
}

bool _isWhitespace(int ch) {
  return ch == 32 || ch == 9 || ch == 10 || ch == 13;
}
