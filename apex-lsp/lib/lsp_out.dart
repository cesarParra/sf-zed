import 'dart:io';

class LspOut {
  LspOut({
    required Stdout output,
  }) : _output = output;

  final Stdout _output;

  Future<dynamic> flush() => _output.flush();

  void add(List<int> data) => _output.add(data);
}
