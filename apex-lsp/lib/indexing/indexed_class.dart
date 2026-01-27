import 'package:apex_lsp/completion/completion.dart';
import 'package:apex_lsp/indexing/indexer.dart' as indexer;
import 'package:apex_reflection/apex_reflection.dart' as apex_reflection;

/// Contract for indexed classes completion data.
abstract class IndexedClassProvider {
  Iterable<String> get classNames;

  Future<IndexedType?> typeByNameAsync(String name);
}

/// Adapter to expose [ApexIndexer] as a [IndexedClassProvider].
final class ApexIndexerWorkspaceIndexAdapter implements IndexedClassProvider {
  ApexIndexerWorkspaceIndexAdapter(this._indexer);

  final indexer.ApexIndexer _indexer;

  @override
  Iterable<String> get classNames => _indexer.indexedClassNames;

  @override
  Future<IndexedType?> typeByNameAsync(String name) async {
    final typeMirror = await _indexer.getIndexedClassInfo(name);

    return switch (typeMirror) {
      indexer.ClassMirrorWrapper(:final typeMirror) => ClassMirrorWrapper(
        classMirror: typeMirror,
      ),
      indexer.EnumMirrorWrapper(:final typeMirror) => EnumMirrorWrapper(
        enumMirror: typeMirror,
      ),
      indexer.InterfaceMirrorWrapper(:final typeMirror) =>
        InterfaceMirrorWrapper(interfaceMirror: typeMirror),
      null => null,
    };
  }
}

abstract class IndexedType {
  List<String> get memberNames;
  List<String> memberNamesByType(MemberType type);
  bool hasMemberPrefix(String prefix);
}

/// Represents an indexed class.
class ClassMirrorWrapper implements IndexedType {
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

class EnumMirrorWrapper implements IndexedType {
  EnumMirrorWrapper({required this.enumMirror});

  final apex_reflection.EnumMirror enumMirror;

  /// Combined member list.
  @override
  List<String> get memberNames {
    final all = <String>{...enumMirror.values.map((v) => v.name)};
    return all.toList();
  }

  @override
  List<String> memberNamesByType(MemberType type) {
    return switch (type) {
      .static => [...enumMirror.values.map((v) => v.name)],
      .instance => [],
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

class InterfaceMirrorWrapper implements IndexedType {
  InterfaceMirrorWrapper({required this.interfaceMirror});

  final apex_reflection.InterfaceMirror interfaceMirror;

  @override
  List<String> get memberNames {
    final all = <String>{...interfaceMirror.methods.map((m) => m.name)};
    return all.toList();
  }

  @override
  List<String> memberNamesByType(MemberType type) {
    return switch (type) {
      .static => [],
      .instance => [...interfaceMirror.methods.map((m) => m.name)],
    };
  }

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
