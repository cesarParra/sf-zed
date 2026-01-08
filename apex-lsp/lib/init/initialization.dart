import '../lsp_out.dart';
import '../message.dart';

/// Helpers for LSP lifecycle wiring around initialization.
final class Initialization {
  const Initialization._();

  /// Extracts workspace roots from the `initialize` request.
  static List<Uri> extractWorkspaceRoots(InitializeRequest req) {
    final folders = req.params.workspaceFolders;
    if (folders == null || folders.isEmpty) return const <Uri>[];

    final uris = <Uri>[];
    for (final folder in folders) {
      final uri = Uri.tryParse(folder.uri);
      if (uri != null) uris.add(uri);
    }
    return uris;
  }

  /// Sends a generic "Indexing Apex files" work-done progress begin message.
  ///
  /// Returns the progress token used for subsequent progress reports/ending.
  static Future<ProgressToken> beginIndexingProgress(LspOut out) async {
    final token = ProgressToken.string(
      'apex-lsp-indexing-${DateTime.now().millisecondsSinceEpoch}',
    );

    await out.workDoneProgressCreate(token: token);
    await out.progress(
      token: token,
      value: const WorkDoneProgressBegin(
        title: 'Indexing Apex files',
        message: 'Preparing workspace index…',
        cancellable: false,
      ),
    );

    return token;
  }
}
