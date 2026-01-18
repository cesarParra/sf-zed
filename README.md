# sf-zed

Zed language support for **Salesforce Apex**.

This repository’s main focus is a **Zed plugin/extension for the Apex programming language**. It currently provides syntax highlighting (via Tree-sitter grammars) and includes an in-progress Apex Language Server implementation.

⚠️ Experimental work in progress and not production-ready.

## Directory structure

- `zed-extension/`: Rust (WASM) Zed extension that registers the language + launches the LSP.
- `apex-lsp/`: Apex Language Server (LSP) written in Dart.

## Building locally

You can build and load the extension locally by following Zed’s extension docs:
https://zed.dev/docs/extensions/languages

Use the `zed-extension` directory as the root of the extension.

### Requirements

- **Dart** is required at the moment (the extension launches the LSP via `dart run`).

## Features

- Apex code syntax highlighting

## Credits

This project makes use of the following open-source components:

- **Syntax Highlighting**: Powered by the [tree-sitter-sfapex](https://github.com/aheber/tree-sitter-sfapex) grammar (MIT License), created by [aheber](https://github.com/aheber).
