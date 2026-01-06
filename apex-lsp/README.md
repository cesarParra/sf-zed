# apex-lsp

An Apex Language Server Protocol (LSP) server written in Dart.

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

```sh
cd sf-zed/apex-lsp
dart run bin/apex_lsp.dart
```

## Contributing

### Linting

```sh
dart analyze
```
