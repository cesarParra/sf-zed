import 'package:apex_lsp/indexing/scope.dart';

typedef ApexIndexBuilder = ApexDocumentIndex Function(String text);

/// Represents any named entity in Apex (Class, Interface, Enum, Method, Variable, etc.)
sealed class ApexEntity {}

/// Public representation of a parsed Apex document index.
final class ApexDocumentIndex {
  ApexDocumentIndex({required this.rootScope});

  final Scope rootScope;

  TypeInfo? typeByName(String name) {
    for (final entity in rootScope.definitions) {
      if (entity is TypeInfo && entity.name == name) {
        return entity;
      }
    }
    return null;
  }

  @override
  String toString() {
    return 'ApexDocumentIndex(rootScope: $rootScope)';
  }
}

/// Base class for top-level types (classes, enums, interfaces).
sealed class TypeInfo implements ApexEntity {
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
    required this.members,
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
  final List<ApexMemberInfo> members;

  // TODO: In Apex, interfaces can have super classes.

  @override
  String toString() {
    return 'ApexInterfaceInfo(name: $name, startByte: $startByte, endByte: $endByte, members: $members)';
  }
}

final class ApexMemberInfo implements ApexEntity {
  ApexMemberInfo({required this.name, required this.isStatic});

  final String name;
  final bool isStatic;

  @override
  String toString() => 'ApexMemberInfo(name: $name, isStatic: $isStatic)';
}

/// Public representation of an Apex variable in a parsed document.
final class ApexVariableInfo implements ApexEntity {
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
