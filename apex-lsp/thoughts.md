# Apex LSP Scoping Implementation Plan

This document outlines the rules and implementation strategy for handling variable and member scoping in the Apex LSP autocompletion engine.

## Core Concepts

To correctly suggest completions, the system must understand the **Scope** in which the cursor is currently located. A scope determines which symbols (variables, fields, methods, classes) are visible.

### The Scope Chain

Scopes are hierarchical. When looking up a symbol, we search the current scope; if not found, we traverse up to the parent scope, repeating until we reach the root (file/global) scope.

Proposed Scope Hierarchy:
1.  **File Scope (Root)**: Contains top-level `TypeInfo` (classes, interfaces, enums).
2.  **Type Scope (Class/Enum/Interface)**: Contains `ApexMemberInfo` (fields, properties, methods) and potentially inner types.
3.  **Method/Block Scope**: Contains parameters and local variables (`ApexVariableInfo`). Blocks (like `if`, `for`) can nest further.

### Context Awareness (Static vs Instance)

*   **Instance Methods**: Can access `this` (instance members) AND static members of the enclosing class.
*   **Static Methods**: Can ONLY access static members of the enclosing class. Cannot access `this`.

### Cursor Position Rule

For **local variables** within a Method or Block scope, order matters.
*   A variable is only visible if its declaration `endByte` is **before** the `cursorOffset`.
*   This prevents suggesting a variable that is declared *after* the current typing position in the same block.

## Implementation Strategy

### 1. Data Structures

We will introduce a `Scope` abstraction that represents a region of code.
The `definitions` list will be polymorphic, holding the specific "info" types used by the Tree Sitter parsing layer (`ApexVariableInfo`, `ApexMemberInfo`, `TypeInfo`).

```dart
enum ScopeType {
  file,
  typeDeclaration,
  methodBody,
  localBlock // e.g. for loop, if statement
}

abstract class Scope {
  Scope? get parent;
  int get startByte;
  int get endByte;
  ScopeType get type;

  /// Returns symbols defined immediately within this scope.
  /// Type is dynamic/Object to allow ApexVariableInfo, ApexMemberInfo, TypeInfo, etc.
  /// or a sealed class 'Symbol'.
  List<Object> get definitions;
  
  /// Child scopes (nested blocks, methods, etc.)
  List<Scope> get children;
}
```

### 2. Parsing & Indexing

The `TreeSitterIndexer` currently extracts flat lists. We need to enhance it to build a **Tree of Scopes**.

*   **Top Level**: The file itself is the root scope.
*   **Class Declaration**: Creates a child scope (`typeDeclaration`).
*   **Method Declaration**: Creates a child scope of the class (`methodBody`). It records whether the method is `static`.
*   **Block (`{ ... }`)**: Creates a child scope (`localBlock`).

### 3. Resolution Logic (The "Look Up")

When `onCompletion` is triggered:
1.  **Locate Current Scope**: Find the deepest `Scope` node that contains the `cursorOffset`.
2.  **Collect Candidates**:
    *   Start at current scope.
    *   Add all visible definitions from this scope.
        *   **Filter**: If in Method/Block scope, exclude variables declared *after* cursor.
    *   Move to `parent`.
    *   **Filter**: If traversing from `methodBody` (static) -> `typeDeclaration`, filter out instance members.
    *   Repeat until root.

## Scoping Rules & Examples

### Scenario 1: Top-Level (File Scope)

**Context**: Cursor is outside any class.
**Visible**: Top-level classes, enums, interfaces declared in the file.

```apex
class A {}
interface B {}
// Cursor Here
```
*   **Can see**: `A`, `B`.

### Scenario 2: Inside Class (Type Scope)

**Context**: Inside a class body, but outside methods.
**Visible**: Top-level types.

```apex
class A {
  Integer x;
  // Cursor Here
}
```
*   This is mostly for declaring new members. Autocompletion here usually suggests types (for defining fields/methods).

### Scenario 3: Inside Instance Method

**Context**: Inside a non-static method.
**Visible**:
1.  Local variables declared *before* cursor in current block.
2.  Method parameters.
3.  Instance members of class `A`.
4.  Static members of class `A`.
5.  Top-level types.

```apex
public class A {
  public static String staticField;
  public String instanceField;

  public void method(Integer param) {
    String local = 'hello';
    // Cursor Here
  }
}
```
*   **Can see**: `local`, `param`, `instanceField`, `staticField`.

### Scenario 4: Inside Static Method

**Context**: Inside a static method.
**Visible**:
1.  Local variables/Params.
2.  **Only** Static members of class `A`.
3.  Top-level types.

```apex
public class A {
  public static String staticField;
  public String instanceField;

  public static void main() {
    // Cursor Here
  }
}
```
*   **Can see**: `staticField`.
*   **Cannot see**: `instanceField`.

### Scenario 5: Nested Blocks (Shadowing/Visibility)

**Context**: Inside an `if` block.
**Visible**: Variables in `if` block (before cursor), plus variables in parent method scope (before cursor if same block, or all if parent block).

```apex
public void method() {
  String outer = 'outer';
  if (true) {
    String inner = 'inner';
    // Cursor Here
  }
  // Cursor Here (2)
}
```
*   **Cursor 1**: Can see `inner`, `outer`.
*   **Cursor 2**: Can see `outer`. Cannot see `inner`.

## Data Model Refinement

The `ApexDocumentIndex` will evolve to hold the **Root Scope** instead of just flat lists.

## Next Steps

1.  **Step 1: Scopes Data Structure**: Define `Scope` class and related types.
2.  **Step 2: Tree Sitter Scoping**: Update `TreeSitterIndexer` to build the `Scope` tree instead of flat lists.
3.  **Step 3: Completion Logic**: Update `CompletionAggregator` / `TreeSitterCompletionService` to use the scope tree for resolution.