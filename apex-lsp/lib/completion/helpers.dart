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

  bool startsWithIgnoreCase(String prefix) {
    return toLowerCase().startsWith(prefix.toLowerCase());
  }
}
