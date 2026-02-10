final class TypeName {
  final String value;
  const TypeName(this.value);

  bool startsWith(String prefix) =>
      value.toLowerCase().startsWith(prefix.toLowerCase());

  @override
  bool operator ==(Object other) =>
      other is TypeName && value.toLowerCase() == other.value.toLowerCase();

  @override
  int get hashCode => value.toLowerCase().hashCode;

  @override
  String toString() => value;
}
