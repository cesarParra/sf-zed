import 'package:apex_reflection/apex_reflection.dart' as apex_reflection;

/// Contract for indexed classes completion data.
abstract class IndexedClassProvider {
  Iterable<String> get classNames;

  Future<IndexedClass?> classByNameAsync(String name);
}

abstract class IndexedClass {
  List<String> get memberNames;
  bool hasMemberPrefix(String prefix);
}

/// Represents an indexed class.
class ClassMirrorWrapper implements IndexedClass {
  ClassMirrorWrapper({required this.classMirror});

  final apex_reflection.ClassMirror classMirror;

  /// Combined member list in a stable, sorted order.
  @override
  List<String> get memberNames {
    final all = <String>{
      ...classMirror.fields.map((f) => f.name),
      ...classMirror.properties.map((p) => p.name),
      ...classMirror.methods.map((m) => m.name),
    };
    final result = all.toList()..sort();
    return result;
  }

  /// Returns true if any member matches [prefix] (case-insensitive).
  @override
  bool hasMemberPrefix(String prefix) {
    final lower = prefix.toLowerCase();
    return memberNames.any(
      (current) => current.toLowerCase().startsWith(lower),
    );
  }
}
