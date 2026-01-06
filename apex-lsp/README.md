# apex-lsp

A minimal “hello world” Language Server Protocol (LSP) server written in Dart.

This server is intentionally bare-bones:
- Runs over **stdio** (stdin/stdout)
- Uses **LSP framing** (`Content-Length: ...\r\n\r\n{json}`)
- Implements only the lifecycle essentials:
  - `initialize` request → returns minimal server capabilities
  - `initialized` notification → ignored
  - `shutdown` request → responds with `null`
  - `exit` notification → terminates the process
- Unknown methods:
  - If a **request**: responds with JSON-RPC error `-32601` (Method not found)
  - If a **notification**: ignored

## Requirements

- Dart SDK (>= 3.0)

## Run

From the repo root:

```/dev/null/sh#L1-3
cd sf-zed/apex-lsp
dart run bin/apex_lsp.dart
```

You can also run the entrypoint directly:

```/dev/null/sh#L1-2
cd sf-zed/apex-lsp
dart bin/apex_lsp.dart
```

## Notes on the protocol

LSP messages are transmitted using an HTTP-like header with a `Content-Length` followed by `\r\n\r\n` and then a UTF-8 JSON payload, for example:

```/dev/null/text#L1-6
Content-Length: 85\r\n
\r\n
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
```

This server reads from `stdin`, parses messages using the LSP framing, and writes responses to `stdout` using the same framing.

## Layout

- `bin/apex_lsp.dart`: entrypoint (stdio LSP loop)
- `pubspec.yaml`: Dart package metadata