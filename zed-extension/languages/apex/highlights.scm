;; Apex (Salesforce) highlights for Zed

;------------------------------------------------------------------------------
; Comments
;------------------------------------------------------------------------------

[
  (line_comment)
  (block_comment)
] @comment

;------------------------------------------------------------------------------
; Literals
;------------------------------------------------------------------------------

(string_literal) @string

[
  (int)
  (decimal_floating_point_literal)
] @number

(boolean) @boolean
(null_literal) @constant

;------------------------------------------------------------------------------
; Punctuation / delimiters / brackets
;------------------------------------------------------------------------------

"@" @punctuation.special

[
  "."
  ","
  ";"
  ":"
] @punctuation.delimiter

[
  "("
  ")"
  "{"
  "}"
  "["
  "]"
  "<"
  ">"
] @punctuation.bracket

;------------------------------------------------------------------------------
; Operators
;------------------------------------------------------------------------------

(assignment_operator) @operator
(update_operator) @operator
(safe_navigation_operator) @operator

(binary_expression
  operator: [
    ">"
    "<"
    ">="
    "<="
    "=="
    "==="
    "!="
    "!=="
    "&&"
    "||"
    "+"
    "-"
    "*"
    "/"
    "&"
    "|"
    "^"
    "%"
    "<<"
    ">>"
    ">>>"
  ] @operator)

(unary_expression
  operator: [
    "+"
    "-"
    "!"
    "~"
  ] @operator)

[
  "="
  "=>"
] @operator

;------------------------------------------------------------------------------
; Keywords / modifiers
;------------------------------------------------------------------------------

[
  "break"
  "catch"
  "class"
  "continue"
  "do"
  "else"
  "enum"
  "extends"
  "finally"
  "for"
  "get"
  "if"
  "implements"
  "instanceof"
  "interface"
  "new"
  "on"
  "return"
  "set"
  "switch"
  "throw"
  "try"
  "trigger"
  "when"
  "while"
  "public"
  "private"
  "protected"
  "global"
  "static"
  "final"
  "virtual"
  "abstract"
  "override"
  "transient"
  "webservice"
  "testMethod"
] @keyword

; Sharing modifiers
[
  (with_sharing)
  (without_sharing)
  (inherited_sharing)
] @keyword

;------------------------------------------------------------------------------
; Types
;------------------------------------------------------------------------------

(class_declaration
  name: (identifier) @type)

(interface_declaration
  name: (identifier) @type)

(enum_declaration
  name: (identifier) @type)

(class_declaration
  (superclass) @type)

(interfaces
  (type_list
    (type_identifier) @type))

; Type identifiers in common type positions
(type_identifier) @type
(scoped_type_identifier (type_identifier) @type)

(generic_type
  (type_identifier) @type)

(type_arguments
  (type_identifier) @type)

(array_type
  element: (type_identifier) @type)

(object_creation_expression
  type: (type_identifier) @type)

(array_creation_expression
  type: (type_identifier) @type)

;------------------------------------------------------------------------------
; Enums
;------------------------------------------------------------------------------

(enum_constant
  name: (identifier) @constant)

;------------------------------------------------------------------------------
; Functions / methods
;------------------------------------------------------------------------------

(method_declaration
  name: (identifier) @function)

(method_invocation
  name: (identifier) @function)

; Common builtins
(super) @function

;------------------------------------------------------------------------------
; Variables
;------------------------------------------------------------------------------

; Parameters
(formal_parameter
  name: (identifier) @variable)

(method_declaration
  (formal_parameters
    (formal_parameter
      name: (identifier) @variable)))

; Local variable declarations
(local_variable_declaration
  declarator: (variable_declarator
    name: (identifier) @variable))

; Field declarations
(field_declaration
  declarator: (variable_declarator
    name: (identifier) @property))

; Enhanced for: `for (Type name : value)`
(enhanced_for_statement
  name: (identifier) @variable)

(enhanced_for_statement
  value: (identifier) @variable)

; LHS assignments (helps highlight variables when declared elsewhere)
(assignment_expression
  left: (identifier) @variable)

; Identifier occurrences in common expression contexts
(return_statement
  (identifier) @variable)

(bound_apex_expression
  (identifier) @variable)

(instanceof_expression
  left: (identifier) @variable
  right: (type_identifier) @type)

(cast_expression
  type: (type_identifier) @type
  value: (identifier) @variable)

(binary_expression
  (identifier) @variable)

(switch_expression
  condition: (identifier) @variable)

;------------------------------------------------------------------------------
; Properties / member access
;------------------------------------------------------------------------------

(field_access
  field: (identifier) @property)

; Best-effort: If something looks like a TypeName.member, treat the prefix as a type.
; This is useful for `System.debug`, `Account.SObjectType`, etc.
((scoped_identifier
  scope: (identifier) @type)
 (#match? @type "^[A-Z]"))

((method_invocation
  object: (identifier) @type)
 (#match? @type "^[A-Z]"))

;------------------------------------------------------------------------------
; Annotations
;------------------------------------------------------------------------------

(annotation
  name: (identifier) @attribute)

(annotation_key_value
  (identifier) @property)

;------------------------------------------------------------------------------
; SOQL-ish query constructs (from grammar nodes)
;------------------------------------------------------------------------------

(dml_type) @function

(trigger_declaration
  name: (identifier) @type
  object: (identifier) @type
  (trigger_event) @keyword
  ("," (trigger_event) @keyword)*)

(when_sobject_type
  (type_identifier) @type
  (identifier) @variable)
