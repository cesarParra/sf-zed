import 'dart:async';
import 'dart:io';

import 'package:apex_lsp/documents/open_documents.dart';
import 'package:get_it/get_it.dart';

import 'indexing/indexer.dart';
import 'lsp_out.dart';
import 'message.dart';
import 'message_reader.dart';

typedef ExitFn = Never Function(int exitCode);

final class Server {
  factory Server({required Stream<List<int>> input}) =>
      Server._(input: input, locator: GetIt.I);

  Server._({required Stream<List<int>> input, required GetIt locator})
    : _output = locator<LspOut>(),
      _reader = MessageReader(input),
      _exitFn = locator<ExitFn>(),
      _openDocuments = OpenDocuments(),
      _apexIndexer = locator<ApexIndexer>();

  final LspOut _output;
  final MessageReader _reader;
  final ExitFn _exitFn;

  final OpenDocuments _openDocuments;
  final ApexIndexer _apexIndexer;

  bool _initialized = false;
  bool _shutdownRequested = false;
  bool _exiting = false;

  Future<void> logMessage(MessageType type, String message) async {
    if (!_initialized) return;
    await _output.logMessage(type, message);
  }

  Future<void> run() async {
    await for (final message in _reader.messages()) {
      if (_exiting) break;

      switch (message) {
        case RequestMessage():
          await _handleRequest(message);
        case IncomingNotificationMessage():
          await _handleNotification(message);
      }
    }
  }

  Future<void> _handleRequest(RequestMessage req) async {
    if (!_initialized &&
        req.method != 'initialize' &&
        req.method != 'shutdown') {
      await _output.sendError(
        id: req.id,
        code: -32002, // ServerNotInitialized (LSP)
        message: 'Server not initialized',
      );
      return;
    }

    switch (req) {
      case InitializeRequest():
        await _onInitialize(req);
      case ShutdownRequest():
        _shutdownRequested = true;
        await _output.sendResponse(id: req.id, result: null);
      case CompletionRequest(:final id, :final params):
        await _onCompletion(id: id, params: params);
    }
  }

  Future<void> _handleNotification(IncomingNotificationMessage note) async {
    switch (note) {
      case InitializedMessage():
        await logMessage(MessageType.info, 'Apex LSP initialized');
        await _apexIndexer.begingIndexing();

      case TextDocumentDidOpenMessage(:final params):
        _openDocuments.didOpen(params);
      case TextDocumentDidChangeMessage(:final params):
        _openDocuments.didChange(params);
      case TextDocumentDidCloseMessage(:final params):
        _openDocuments.didClose(params);

      case ExitMessage():
        // Spec: If exit is received and shutdown has been requested -> exit 0,
        // otherwise -> exit 1.
        _exiting = true;
        exitCode = _shutdownRequested ? 0 : 1;

        await logMessage(
          MessageType.info,
          'Apex LSP exiting (shutdown=$_shutdownRequested)',
        );
        await _output.flush();
        _exitFn(exitCode);
    }
  }

  Future<void> _onInitialize(InitializeRequest req) async {
    _initialized = true;
    await _apexIndexer.prepare(req);

    // Minimal InitializeResult with full document sync.
    //
    // TODO: Wire up workDoneProgress capability negotiation and proper
    // InitializeResult classes.
    final result = <String, Object?>{
      'capabilities': <String, Object?>{
        'textDocumentSync': 1, // TextDocumentSyncKind.Full
        // Very basic completions using the prebuilt index.
        // We keep it minimal: advertise that we support completion requests.
        'completionProvider': <String, Object?>{},
      },
      // TODO: Get from dynamic JSON or pubspec or something like that
      'serverInfo': <String, Object?>{'name': 'apex-lsp', 'version': '0.0.1'},
    };

    await _output.sendResponse(id: req.id, result: result);
  }

  Future<void> _onCompletion({
    required Object id,
    required CompletionParams params,
  }) async {
    final prefix = _extractPrefixAtPosition(
      uri: params.textDocument.uri,
      line: params.position.line,
      character: params.position.character,
    );

    if (prefix.isEmpty) {
      await _output.sendResponse(
        id: id,
        result: const CompletionList(
          isIncomplete: false,
          items: <CompletionItem>[],
        ).toJson(),
      );
      return;
    }

    final lowerPrefix = prefix.toLowerCase();

    // Score candidates so that "better" matches come first:
    // 1) Prefer closer spelling using a simple edit-distance measure.
    // 2) Then prefer shorter names (helps short class names surface).
    // 3) Finally, fall back to alphabetical order.
    //
    // TODO: We currently only match startsWith(prefix). We want to eventually
    // do fuzzy matching
    final candidates =
        _apexIndexer.indexedClassNames
            .where((name) => name.toLowerCase().startsWith(lowerPrefix))
            .map(
              (name) => (
                name: name,
                // Smaller is better.
                length: name.length,
                // Smaller is better.
                distance: _levenshteinDistance(lowerPrefix, name.toLowerCase()),
              ),
            )
            .toList()
          ..sort((a, b) {
            final byDistance = a.distance.compareTo(b.distance);
            if (byDistance != 0) return byDistance;

            final byLength = a.length.compareTo(b.length);
            if (byLength != 0) return byLength;

            return a.name.compareTo(b.name);
          });

    final items = candidates
        .take(25)
        .map((c) => CompletionItem(label: c.name, insertText: c.name))
        .toList();

    await _output.sendResponse(
      id: id,
      result: CompletionList(isIncomplete: false, items: items).toJson(),
    );
  }

  String _extractPrefixAtPosition({
    required String uri,
    required int line,
    required int character,
  }) {
    final text = _openDocuments.get(uri);
    if (text == null) return '';

    final lines = text.split('\n');
    if (line < 0 || line >= lines.length) return '';

    final lineText = lines[line];

    // LSP character is UTF-16 code unit offset; for now we treat it as a string index.
    final clamped = character.clamp(0, lineText.length);

    // Walk left while we’re in an identifier.
    var start = clamped;
    while (start > 0) {
      final ch = lineText.codeUnitAt(start - 1);
      final isIdent =
          (ch >= 48 && ch <= 57) || // 0-9
          (ch >= 65 && ch <= 90) || // A-Z
          (ch >= 97 && ch <= 122) || // a-z
          ch == 95; // _
      if (!isIdent) break;
      start--;
    }

    return lineText.substring(start, clamped);
  }

  int _levenshteinDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    // Ensure we use less memory by keeping the shorter string as "b".
    if (a.length < b.length) {
      final tmp = a;
      a = b;
      b = tmp;
    }

    final previous = List<int>.generate(b.length + 1, (i) => i);
    final current = List<int>.filled(b.length + 1, 0);

    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      final aChar = a.codeUnitAt(i - 1);

      for (var j = 1; j <= b.length; j++) {
        final cost = aChar == b.codeUnitAt(j - 1) ? 0 : 1;

        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        final substitution = previous[j - 1] + cost;

        var best = deletion;
        if (insertion < best) best = insertion;
        if (substitution < best) best = substitution;

        current[j] = best;
      }

      for (var j = 0; j < current.length; j++) {
        previous[j] = current[j];
      }
    }

    return previous[b.length];
  }
}
