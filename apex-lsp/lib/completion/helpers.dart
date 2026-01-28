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
        this == 36;
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
  /// final prefix = text.extractIndentifierPrefixAt(19);
  /// // For 'System.debug(myVar)', returns 'myVar'
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

  /// Extracts a qualified identifier (including periods) immediately before the cursor offset.
  /// Scans backward from the cursor position, accepting identifier characters and periods.
  /// Supports qualified names (e.g., OuterClass.InnerClass).
  ///
  /// - [cursorOffset]: Zero-based byte offset of the cursor position.
  ///
  /// Returns the qualified identifier as a string, which may be empty if the cursor
  /// is not positioned after an identifier character or period.
  ///
  /// Example:
  /// ```dart
  /// final name = text.extractQualifiedIdentifierAt(23);
  /// // For 'OuterClass.InnerClass', returns 'OuterClass.InnerClass'
  /// ```
  String extractQualifiedIdentifierAt(int cursorOffset) {
    var i = cursorOffset;
    if (i > length) i = length;

    var start = i;
    while (start > 0) {
      final ch = codeUnitAt(start - 1);
      if (ch.isIdentifierChar || ch == 0x2E /* . */ ) {
        start--;
      } else {
        break;
      }
    }
    return substring(start, i).trim();
  }

  bool startsWithIgnoreCase(String prefix) {
    return toLowerCase().startsWith(prefix.toLowerCase());
  }
}
