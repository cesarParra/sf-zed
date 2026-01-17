/// Contract for indexed classes completion data.
abstract class IndexedClassProvider {
  Iterable<String> get classNames;

  Future<IndexedClass?> classByNameAsync(String name);
}

/// Represents an indexed class.
final class IndexedClass {
  IndexedClass({
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

final class IndexedClassBuilder {
  IndexedClassBuilder(this.name);

  final String name;
  final Set<String> _fields = <String>{};
  final Set<String> _properties = <String>{};
  final Set<String> _methods = <String>{};
  String? superclass;

  void addField(String name) => _fields.add(name);
  void addProperty(String name) => _properties.add(name);
  void addMethod(String name) => _methods.add(name);

  IndexedClass build() {
    final fields = _fields.toList()..sort();
    final properties = _properties.toList()..sort();
    final methods = _methods.toList()..sort();
    return IndexedClass(
      name: name,
      fields: fields,
      properties: properties,
      methods: methods,
      superclass: superclass,
    );
  }
}
