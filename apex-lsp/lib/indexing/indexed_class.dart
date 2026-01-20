import 'package:apex_reflection/apex_reflection.dart' as apex_reflection;

/// Contract for indexed classes completion data.
abstract class IndexedClassProvider {
  Iterable<String> get classNames;

  Future<IndexedClass?> classByNameAsync(String name);
}

enum MemberType { static, instance }

abstract class IndexedClass {
  List<String> get memberNames;
  List<String> memberNamesByType(MemberType type);
  bool hasMemberPrefix(String prefix);
}

/// Represents an indexed class.
class ClassMirrorWrapper implements IndexedClass {
  ClassMirrorWrapper({required this.classMirror});

  final apex_reflection.ClassMirror classMirror;

  /// Combined member list.
  @override
  List<String> get memberNames {
    final all = <String>{
      ...classMirror.fields.map((f) => f.name),
      ...classMirror.properties.map((p) => p.name),
      ...classMirror.methods.map((m) => m.name),
    };
    return all.toList();
  }

  @override
  List<String> memberNamesByType(MemberType type) {
    return switch (type) {
      .static => [
        ...classMirror.fields.where((f) => f.isStatic).map((f) => f.name),
        ...classMirror.properties.where((f) => f.isStatic).map((f) => f.name),
        ...classMirror.methods.where((f) => f.isStatic).map((f) => f.name),
      ],
      .instance => [
        ...classMirror.fields.where((f) => !f.isStatic).map((f) => f.name),
        ...classMirror.properties.where((f) => !f.isStatic).map((f) => f.name),
        ...classMirror.methods.where((f) => !f.isStatic).map((f) => f.name),
      ],
    };
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

extension on apex_reflection.MemberModifiersAwareness {
  bool get isStatic =>
      memberModifiers.contains(apex_reflection.MemberModifier.static);
}
