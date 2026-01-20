enum CompletionKind { none, className, member }

sealed class CompletionContext {
  const CompletionContext({required this.kind});
  final CompletionKind kind;
}

final class CompletionContextNone extends CompletionContext {
  const CompletionContextNone() : super(kind: CompletionKind.none);
}

final class CompletionContextClass extends CompletionContext {
  const CompletionContextClass({required this.className})
    : super(kind: CompletionKind.className);

  final String className;
}

final class CompletionContextMember extends CompletionContext {
  const CompletionContextMember({this.objectName, required this.prefix})
    : super(kind: CompletionKind.member);

  final String? objectName;
  final String prefix;
}
