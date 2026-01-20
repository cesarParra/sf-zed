import 'package:apex_lsp/completion/completion_context.dart';

typedef ApexIndexBuilder = ApexDocumentIndex Function(String text);

/// Public completion result payload produced by completion services.
final class CompletionCandidates {
  CompletionCandidates({
    required this.kind,
    required this.labels,
    this.memberOfType,
    this.memberTypeResolvedFromDocument = false,
  });

  final CompletionKind kind;
  final List<String> labels;

  /// When [kind] is [CompletionKind.member], this is the resolved type name.
  final String? memberOfType;

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
}
