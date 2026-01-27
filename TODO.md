## Misc

- [x] CI GH Action

## Zed Extension

- [x] Syntax highlight
- [ ] Download latest LSP version on install

## LSP

### Indexing
- [x] Index local Apex files
- [ ] Index local SObject files
- [ ] Index standard library (e.g. System namespace)
- [ ] Index metadata in org
- [ ] Intelligent re-indexing instead of always recreating it

### Autocomplete

#### Indexed files
Class
- [x] Indexed class names appear
- [x] Instance members of indexed classes
- [x] Static members of indexed classes
- [ ] Subclasses names of indexed files
- [ ] Subclass instance members
- [ ] Subinterface names of indexed files
- [ ] Subenum names of indexed files
- [ ] Subenum values of indexed files

Enum
- [x] Indexed enum names appear
- [x] Indexed enum values appear

Interface
- [x] Interfaces names of indexed files
- [x] Interface members
- [ ] Interface superclasses (members inherited from the superclass)

#### Opened file
Class
- [x] Name of other classes of the opened file
- [x] Instance members
- [x] Subclasses (top level names)
- [x] Subenums (top level names)
- [x] Subinterfaces (top level names)
- [x] Members of subclasses
- [ ] Members of subinterfaces
- [ ] Members of subenums

Enum
- [x] Name of other enums of the opened file
- [x] Member of enums of the opened file

Interface
- [x] Name of other interfaces of the opened file
- [x] Interface members
- [ ] Interface superclasses (members inherited from the superclass)

Scoped blocks
- [x] Static members of the class being modified
- [x] Instance members of the class being modified
- [ ] Static members of the superclass(es) (?)
- [ ] Instance member ofthe superclass(es)
- [ ] `this`
- [ ] `super`
- [x] Local declaration of the current block
- [ ] Scoped params of the current block (missing, autocompleting members of passed params)

Block support notes
* When in a static block, can only call into static members
* When in an instance block, can call into both static and instance members

#### Other

- [ ] Multiple multi-level instance references (`foo.bar.baz`)
- [ ] Rank logic
- [ ] Params and return type information
- [ ] Apexdocs information
- [ ] Private members (of other files) should not be shown
- [ ] @TestVisible members are surfaced only when inside a test file
- [ ] Language keywords

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
