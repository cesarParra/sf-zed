import 'dart:async';
import 'dart:io';

import 'package:apex_lsp/lsp_out.dart';
import 'package:apex_lsp/server.dart';

/// Apex Language Server Protocol (LSP) server over stdio.
Future<void> main(List<String> args) async {
  final server = Server(
    input: stdin,
    output: LspOut(output: stdout),
    logger: stderr,
  );

  // If something goes wrong at top-level:
  // - If the server is initialized, prefer LSP logging via `window/logMessage`.
  // - Otherwise, fall back to stderr (there is no client connection yet).
  try {
    await server.run();
  } catch (e, st) {
    await server.logError('Fatal error: $e\n$st');
    exitCode = 1;
  }
}
