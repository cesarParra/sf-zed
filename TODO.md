## Misc

- [x] CI GH Action

## Zed Extension

- [x] Syntax highlight
- [ ] Download latest LSP version on install

# LSP

## Indexing
- [x] Index local Apex files
- [ ] Index local SObject files
- [ ] Index standard library (e.g. System namespace)
- [ ] Index metadata in org
- [ ] Intelligent re-indexing instead of always recreating it

### Autocomplete
- [x] Indexed class names appear
- [x] Static members of indexed files
- [x] Instance members of indexed files
- [x] Static members of the opened file
- [x] Instance members of the opened file
- [ ] Enum members of indexed files
- [ ] Other classes of the opened file
- [ ] Interfaces of the opened file
- [ ] Enums of the opened file
- [ ] Subclasses of indexed files
- [ ] Subinterfaces of indexed files
- [ ] Subenums of indexed files
- [ ] `this`
- [ ] `super`
- [ ] Multiple multi-level instance references (`foo.bar.baz`)
- [ ] Rank logic
- [ ] Params and return type information
- [ ] Apexdocs information
- [ ] Private members (of other files) should not be shown
- [ ] @TestVisible members are surfaced only when inside a test file

### Block support
- [ ] Local declaration of the current block
- [ ] Scoped params of the current block

Block support notes
* When in a static block, can only call into static members
* When in an instance block, can call into both static and instance members

## Namespaces
- [ ] Can work on a namespaced scratch org (e.g. autocomplete works when referencing a file in the same namespace)
- [ ] Can work with namespaced packages

## Go-to Definition

### Trigger file support

---

All capabilities include:
* completionProvider
* hoverProvider
* signatureHelperProvider
* declarationProvider - go to declaration support
* definitionProvider - go to definition support
* typeDefinitionProvider - go to type definition
* implementationProvider - go to implementation
* referencesProvider - find references support
* documentHighlightProvider
* documentSymbolProvider
* codeActionProvider
* codeLensProvider
* documentLinkProvider
* colorProvider
* documentFormattingProvider
* documentRangeFormattingProvider
* documentOnTypeFormattingProvider
* renameProvider
* foldingRangeProvider
* executeCommandProvider
* selectionRangeProvider
* linkedEditingRangeProvider
* callHierarchyProvider
* semanticTokensProvider
* monikerProvider
* typeHierarchyProvider
* inlineValueProvider
* inlayHintProvider
* diagnosticProvider
* workspaceSymbolProvider
* workspace
  * workspaceFolders
  * fileOperations
    * didCreate
    * willCreate
    * didRename
    * willRename
    * didDelete
    * willDelete
