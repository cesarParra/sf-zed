typedef ApexIndexBuilder = ApexDocumentIndex Function(String text);

sealed class CompletionCandidates {
  final List<String> labels;

  CompletionCandidates({required this.labels});
}

final class NoCandidates extends CompletionCandidates {
  NoCandidates() : super(labels: const []);
}

final class ClassNameOrLocalCandidates extends CompletionCandidates {
  ClassNameOrLocalCandidates({required super.labels});

  @override
  String toString() {
    return 'ClassNameCandidates(labels: $labels)';
  }
}

final class MemberCandidates extends CompletionCandidates {
  MemberCandidates({
    required super.labels,
    required this.memberOfType,
    required this.objectName,
    required this.memberTypeResolvedFromDocument,
  });

  /// The resolved type name. e.g. `Foo`.
  final String memberOfType;

  // When [kind] is [CompletionKid.member], this represents the name of the
  // object. For example, if the user typed `foo.m`, then this is foo.
  final String objectName;

  /// True when member type resolution came from the document index.
  final bool memberTypeResolvedFromDocument;
}

/// Public representation of a parsed Apex document index.
final class ApexDocumentIndex {
  ApexDocumentIndex({required this.classes, required this.variables});

  final List<ApexClassInfo> classes;
  final List<ApexVariableInfo> variables;

  ApexClassInfo? classByName(String name) {
    for (final c in classes) {
      if (c.name == name) return c;
    }
    return null;
  }

  @override
  String toString() {
    return 'ApexDocumentIndex(classes: $classes, variables: $variables)';
  }
}

/// Public representation of an Apex class in a parsed document.
final class ApexClassInfo {
  ApexClassInfo({
    required this.name,
    required this.startByte,
    required this.endByte,
    required this.fields,
    required this.properties,
    required this.methods,
    this.superclass,
  });

  final String name;
  final int startByte;
  final int endByte;
  final List<String> fields;
  final List<String> properties;
  final List<String> methods;
  final String? superclass;

  @override
  String toString() {
    return 'ApexClassInfo(name: $name, startByte: $startByte, endByte: $endByte, fields: $fields, properties: $properties, methods: $methods, superclass: $superclass)';
  }
}

/// Public representation of an Apex variable in a parsed document.
final class ApexVariableInfo {
  ApexVariableInfo({
    required this.name,
    required this.typeName,
    required this.startByte,
    required this.endByte,
    required this.kind,
  });

  final String name;
  final String typeName;
  final int startByte;
  final int endByte;
  final String kind;

  @override
  String toString() {
    return 'ApexVariableInfo(name: $name, typeName: $typeName, startByte: $startByte, endByte: $endByte, kind: $kind)';
  }
}
