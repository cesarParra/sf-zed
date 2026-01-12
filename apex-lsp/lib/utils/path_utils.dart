import 'dart:io';

/// Minimal filesystem path utilities.
final class PathUtils {
  const PathUtils._();

  /// Joins two filesystem path segments using the current platform separator.
  static String join(String left, String right) {
    if (left.isEmpty) return right;
    if (right.isEmpty) return left;

    final sep = Platform.pathSeparator;
    if (left.endsWith(sep)) return '$left$right';
    return '$left$sep$right';
  }
}
