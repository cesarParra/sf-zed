import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'message.dart';

/// Reads LSP-framed messages from stdin.
///
/// Assumes:
/// - UTF-8 JSON payload
/// - Header includes Content-Length
/// - Headers are ASCII and delimited by \r\n, with an empty line \r\n\r\n.
final class MessageReader {
  MessageReader(this._input);

  final Stdin _input;

  Stream<IncomingMessage> messages() async* {
    // Buffer of bytes read so far.
    final buffer = BytesBuilder(copy: false);

    await for (final chunk in _input) {
      buffer.add(chunk);

      while (true) {
        final data = buffer.toBytes();

        // Find header terminator: \r\n\r\n
        final headerEnd = _indexOfCrlfCrlf(data);
        if (headerEnd == -1) break;

        // Header is ASCII up to headerEnd (exclusive).
        final headerBytes = data.sublist(0, headerEnd);
        final headerText = ascii.decode(headerBytes, allowInvalid: true);

        final contentLength = _parseContentLength(headerText);
        if (contentLength == null) {
          // Invalid framing; drop this header and continue searching.
          // In a real server, you would probably send a parse error.
          _consume(buffer, headerEnd + 4);
          continue;
        }

        final bodyStart = headerEnd + 4; // skip \r\n\r\n
        final bodyEnd = bodyStart + contentLength;

        if (data.length < bodyEnd) {
          // Wait for more bytes.
          break;
        }

        final bodyBytes = data.sublist(bodyStart, bodyEnd);
        final bodyText = utf8.decode(bodyBytes, allowMalformed: true);

        // Consume used bytes from the buffer.
        _consume(buffer, bodyEnd);

        final decoded = _tryDecodeJson(bodyText);
        if (decoded == null) {
          // TODO: Handle? Ignore malformed JSON in this minimal implementation.
          continue;
        }

        final msg = _parseJsonRpcMessage(decoded);
        if (msg != null) {
          yield msg;
        }
      }
    }
  }

  static int _indexOfCrlfCrlf(Uint8List data) {
    // Search for "\r\n\r\n" (13,10,13,10)
    for (var i = 0; i + 3 < data.length; i++) {
      if (data[i] == 13 &&
          data[i + 1] == 10 &&
          data[i + 2] == 13 &&
          data[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  static int? _parseContentLength(String headers) {
    // Small parser for Content-Length: <number>
    // Header fields are separated by \r\n.
    final lines = headers.split('\r\n');
    for (final line in lines) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;

      final name = line.substring(0, idx).trim().toLowerCase();
      if (name != 'content-length') continue;

      final value = line.substring(idx + 1).trim();
      final parsed = int.tryParse(value);
      if (parsed == null || parsed < 0) return null;
      return parsed;
    }
    return null;
  }

  // TODO: Return proper error object rather than null. That will allow us to not have to be checking for `Object`
  // types in the code above
  static Object? _tryDecodeJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static IncomingMessage? _parseJsonRpcMessage(Object decoded) {
    if (decoded is! Map) return null;

    final jsonrpc = decoded['jsonrpc'];
    if (jsonrpc != '2.0') return null;

    final method = decoded['method'];
    final hasMethod = method is String;

    final hasId = decoded.containsKey('id');
    final id = decoded['id'];

    // Per JSON-RPC:
    // - Requests have "method" + "id"
    // - Notifications have "method" and no "id"
    if (hasMethod && hasId && id != null) {
      final rawParams = decoded['params'];
      return switch (method) {
        'initialize' => InitializeRequest(
          id as Object,
          InitializedParams.fromJson(rawParams as Map<String, dynamic>),
        ),
        _ => null,
      };
    } else if (hasMethod && (!hasId || id == null)) {
      final rawParams = decoded['params'];

      return switch (method) {
        'initialized' => InitializedMessage(),
        'exit' => ExitMessage(),

        'textDocument/didOpen' => switch (rawParams) {
          final Map<String, Object?> paramsJson => TextDocumentDidOpenMessage(
            DidOpenTextDocumentParams.fromJson(paramsJson),
          ),
          _ => null,
        },

        'textDocument/didChange' => switch (rawParams) {
          final Map<String, Object?> paramsJson => TextDocumentDidChangeMessage(
            DidChangeTextDocumentParams.fromJson(paramsJson),
          ),
          _ => null,
        },

        'textDocument/didClose' => switch (rawParams) {
          final Map<String, Object?> paramsJson => TextDocumentDidCloseMessage(
            DidCloseTextDocumentParams.fromJson(paramsJson),
          ),
          _ => null,
        },

        _ => null,
      };
    }

    // TODO: Responses are ignored by servers in this minimal implementation,
    // let's handle them (and avoid returning null)
    return null;
  }

  static void _consume(BytesBuilder buffer, int count) {
    final data = buffer.toBytes();
    final remaining = data.sublist(count);
    buffer.clear();
    if (remaining.isNotEmpty) buffer.add(remaining);
  }
}
