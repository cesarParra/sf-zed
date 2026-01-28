import 'package:apex_lsp/indexing/scope.dart';

typedef ApexIndexBuilder = ApexDocumentIndex Function(String text);

/// Represents any named entity in Apex (Class, Interface, Enum, Method, Variable, etc.)
sealed class ApexEntity {}

/// Public representation of a parsed Apex document index.
final class ApexDocumentIndex {
  ApexDocumentIndex({required this.rootScope});

  final Scope rootScope;

  TypeInfo? typeByName(String name) {
    final parts = name.split('.');
    TypeInfo? current;

    for (final entity in rootScope.definitions) {
      if (entity is TypeInfo &&
          // TODO: "Name" should not be a string, it should be a custom type with
          // an "equals" override that doesn't care about lowercases
          entity.name.toLowerCase() == parts[0].toLowerCase()) {
        current = entity;
        break;
      }
    }

    if (current == null || parts.length == 1) return current;

    for (var i = 1; i < parts.length; i++) {
      final part = parts[i];
      TypeInfo? next;
      final TypeInfo nonNullCurrent = current!;
      for (final member in nonNullCurrent.members) {
        if (member is NestedTypeMember &&
            member.name.toLowerCase() == part.toLowerCase()) {
          next = member.typeInfo;
          break;
        }
      }
      if (next == null) return null;
      current = next;
    }

    return current;
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
  ApexMemberInfo({required this.name, required this.isStatic, this.typeName});

  final String name;
  final bool isStatic;
  final String? typeName;

  @override
  String toString() =>
      'ApexMemberInfo(name: $name, isStatic: $isStatic, typeName: $typeName)';
}

final class NestedTypeMember extends ApexMemberInfo {
  NestedTypeMember({required this.typeInfo})
    : super(name: typeInfo.name, isStatic: true);

  final TypeInfo typeInfo;

  @override
  String toString() => 'NestedTypeMember(name: $name, typeInfo: $typeInfo)';
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
