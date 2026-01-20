sealed class CompletionContext {
  const CompletionContext();
}

final class CompletionContextNone extends CompletionContext {
  const CompletionContextNone();

  @override
  String toString() {
    return 'CompletionContextNone()';
  }
}

final class CompletionContextClass extends CompletionContext {
  const CompletionContextClass({required this.className});

  final String className;

  @override
  String toString() {
    return 'CompletionContextClass(className: $className)';
  }
}

final class CompletionContextMember extends CompletionContext {
  const CompletionContextMember({this.objectName, required this.prefix});

  final String? objectName;
  final String prefix;

  @override
  String toString() {
    return 'CompletionContextMember(objectName: $objectName, prefix: $prefix)';
  }
}
