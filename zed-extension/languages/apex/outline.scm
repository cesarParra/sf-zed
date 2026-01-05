; Zed outline query for Apex (tree-sitter-apex)
; Minimal rules: surface top-level declarations and method signatures.
;
; Captures:
; - @item: the whole node that becomes an outline entry
; - @name: the display name for the outline entry
; Optional:
; - @context / @context.extra: qualifiers (modifiers, type, etc.)

; ------------------------
; Types
; ------------------------

(class_declaration
  name: (identifier) @name) @item

(interface_declaration
  name: (identifier) @name) @item

(enum_declaration
  name: (identifier) @name) @item

(trigger_declaration
  name: (identifier) @name) @item

; ------------------------
; Members
; ------------------------

(method_declaration
  name: (identifier) @name) @item

(constructor_declaration
  name: (identifier) @name) @item

(field_declaration
  declarator: (variable_declarator
    name: (identifier) @name)) @item
