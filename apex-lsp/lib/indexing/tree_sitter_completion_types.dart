typedef ApexIndexBuilder = ApexDocumentIndex Function(String text);

/// Public representation of a parsed Apex document index.
final class ApexDocumentIndex {
  ApexDocumentIndex({required this.types, required this.variables});

  final List<TypeInfo> types;
  final List<ApexVariableInfo> variables;

  TypeInfo? typeByName(String name) {
    for (final t in types) {
      if (t.name == name) return t;
    }
    return null;
  }

  @override
  String toString() {
    return 'ApexDocumentIndex(types: $types, variables: $variables)';
  }
}

/// Base class for top-level types (classes, enums, interfaces).
sealed class TypeInfo {
  String get name;
  int get startByte;
  int get endByte;
  List<ApexMemberInfo> get members;
}

/// Public representation of an Apex enum in a parsed document.
final class ApexEnumInfo implements TypeInfo {
  ApexEnumInfo({
    required this.name,
    required this.startByte,
    required this.endByte,
    required this.members,
  });

  @override
  final String name;
  @override
  final int startByte;
  @override
  final int endByte;
  @override
  final List<ApexMemberInfo> members;

  @override
  String toString() {
    return 'ApexEnumInfo(name: $name, startByte: $startByte, endByte: $endByte, members: $members)';
  }
}

/// Public representation of an Apex class in a parsed document.
final class ApexClassInfo implements TypeInfo {
  ApexClassInfo({
    required this.name,
    required this.startByte,
    required this.endByte,
    required this.members,
    this.superclass,
  });

  @override
  final String name;
  @override
  final int startByte;
  @override
  final int endByte;
  @override
  final List<ApexMemberInfo> members;
  final String? superclass;

  @override
  String toString() {
    return 'ApexClassInfo(name: $name, startByte: $startByte, endByte: $endByte, members: $members, superclass: $superclass)';
  }
}

/// Public representation of an Apex interface in a parsed document.
final class ApexInterfaceInfo implements TypeInfo {
  ApexInterfaceInfo({
    required this.name,
    required this.startByte,
    required this.endByte,
  });

  @override
  final String name;
  @override
  final int startByte;
  @override
  final int endByte;
  @override
  final List<ApexMemberInfo> members = const [];

  @override
  String toString() {
    return 'ApexInterfaceInfo(name: $name, startByte: $startByte, endByte: $endByte)';
  }
}

final class ApexMemberInfo {
  ApexMemberInfo({required this.name, required this.isStatic});

  final String name;
  final bool isStatic;

  @override
  String toString() => 'ApexMemberInfo(name: $name, isStatic: $isStatic)';
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
