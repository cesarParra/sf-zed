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
