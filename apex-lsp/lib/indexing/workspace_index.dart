library;

/// Contract for workspace completion data.
abstract class WorkspaceIndexProvider {
  Iterable<String> get classNames;

  Future<WorkspaceClassInfo?> classByNameAsync(String name);
}

/// Represents a workspace-wide completion index loaded from `.sf-zed` JSON.
final class WorkspaceIndex implements WorkspaceIndexProvider {
  WorkspaceIndex({required Map<String, WorkspaceClassInfo> classesByName})
    : _classesByName = classesByName;

  final Map<String, WorkspaceClassInfo> _classesByName;

  @override
  Iterable<String> get classNames => _classesByName.keys;

  WorkspaceClassInfo? classByName(String name) => _classesByName[name];

  @override
  Future<WorkspaceClassInfo?> classByNameAsync(String name) async {
    return classByName(name);
  }

  /// Returns all member names for a class, sorted.
  List<String> memberNamesFor(String className) {
    final info = _classesByName[className];
    if (info == null) return const [];
    return info.memberNames;
  }

  // TODO: Where is this used?
  /// Merge another index into this one, preferring existing entries.
  WorkspaceIndex mergedWith(WorkspaceIndex other) {
    final merged = Map<String, WorkspaceClassInfo>.from(_classesByName);
    other._classesByName.forEach((name, info) {
      merged.putIfAbsent(name, () => info);
    });
    return WorkspaceIndex(classesByName: merged);
  }
}

/// Workspace representation of a class and its members.
final class WorkspaceClassInfo {
  WorkspaceClassInfo({
    required this.name,
    required this.fields,
    required this.properties,
    required this.methods,
    this.superclass,
  });

  final String name;
  final List<String> fields;
  final List<String> properties;
  final List<String> methods;
  final String? superclass;

  /// Combined member list in a stable, sorted order.
  List<String> get memberNames {
    final all = <String>{...fields, ...properties, ...methods};
    final result = all.toList()..sort();
    return result;
  }

  /// Returns true if any member matches [prefix] (case-insensitive).
  bool hasMemberPrefix(String prefix) {
    final lower = prefix.toLowerCase();
    return fields.any((m) => m.toLowerCase().startsWith(lower)) ||
        properties.any((m) => m.toLowerCase().startsWith(lower)) ||
        methods.any((m) => m.toLowerCase().startsWith(lower));
  }

  /// Returns members that match [prefix] (case-insensitive), sorted.
  List<String> membersMatching(String prefix) {
    if (prefix.isEmpty) return memberNames;
    final lower = prefix.toLowerCase();
    final matches = <String>{
      ...fields.where((m) => m.toLowerCase().startsWith(lower)),
      ...properties.where((m) => m.toLowerCase().startsWith(lower)),
      ...methods.where((m) => m.toLowerCase().startsWith(lower)),
    };
    final result = matches.toList()..sort();
    return result;
  }
}

// TODO: This means we have more than a single source of truth (conflicts with ApexClassInfo). We want to get rid of this
/// Simple builder for workspace class info.
final class WorkspaceClassBuilder {
  WorkspaceClassBuilder(this.name);

  final String name;
  final Set<String> _fields = <String>{};
  final Set<String> _properties = <String>{};
  final Set<String> _methods = <String>{};
  String? superclass;

  void addField(String name) => _fields.add(name);
  void addProperty(String name) => _properties.add(name);
  void addMethod(String name) => _methods.add(name);

  WorkspaceClassInfo build() {
    final fields = _fields.toList()..sort();
    final properties = _properties.toList()..sort();
    final methods = _methods.toList()..sort();
    return WorkspaceClassInfo(
      name: name,
      fields: fields,
      properties: properties,
      methods: methods,
      superclass: superclass,
    );
  }
}
