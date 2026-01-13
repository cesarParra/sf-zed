import 'dart:async';
import 'dart:io';

import 'package:apex_lsp/di.dart';
import 'package:apex_lsp/server.dart';

/// Apex Language Server Protocol (LSP) server over stdio.
Future<void> main(List<String> args) async {
  // Initialize dependency injection before constructing the server.
  initializeDependencies();

  final server = Server(input: stdin);

  try {
    await server.run();
  } catch (e, st) {
    await server.logMessage(.error, 'Fatal error: $e\n$st');
    exitCode = 1;
  }
}
