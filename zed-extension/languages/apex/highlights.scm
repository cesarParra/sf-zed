; Apex (Salesforce) highlights for Zed
;
; Goals:
; - Only reference node / token types that exist in the Apex Tree-sitter grammar.
; - Avoid "impossible pattern" / "invalid node type" errors that prevent the language from loading.
; - Keep this conservative and extensible.

; ------------------------------------------------------------------------------
; Comments
; ------------------------------------------------------------------------------

[
  (line_comment)
  (block_comment)
] @comment

; ------------------------------------------------------------------------------
; Literals
; ------------------------------------------------------------------------------

(string_literal) @string

[
  (int)
  (decimal_floating_point_literal)
] @number

(boolean) @boolean

(null_literal) @constant

; ------------------------------------------------------------------------------
; Declarations / identifiers
; ------------------------------------------------------------------------------

; Types
(class_declaration
  name: (identifier) @type)

(interface_declaration
  name: (identifier) @type)

(enum_declaration
  name: (identifier) @type)

; Enum members
(enum_constant
  name: (identifier) @constant)

; Methods: declarations + calls
(method_declaration
  name: (identifier) @function)

(method_invocation
  name: (identifier) @function)

; Constructors
(constructor_declaration
  name: (identifier) @type)

; Parameters and local variables
(formal_parameter
  name: (identifier) @variable)

(local_variable_declaration
  (variable_declarator
    name: (identifier) @variable))

; Fields / properties
(field_declaration
  declarator: (variable_declarator
    name: (identifier) @property))

(field_access
  field: (identifier) @property)

; ------------------------------------------------------------------------------
; Keywords
; ------------------------------------------------------------------------------
; NOTE: Prefer grammar token types over guessed strings.
; In this grammar, many keywords exist as unnamed token types with lowercase names
; (e.g. "class", "public", "return"). Use those token strings directly.

[
  "class"
  "interface"
  "enum"
  "extends"
  "implements"
  "new"
  "return"
  "if"
  "else"
  "switch"
  "when"
  "for"
  "while"
  "do"
  "break"
  "continue"
  "try"
  "catch"
  "finally"
  "throw"
  "trigger"
  "on"

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

  ; Sharing modifiers are distinct token types in this grammar.
  (with_sharing)
  (without_sharing)
  (inherited_sharing)
] @keyword

; ------------------------------------------------------------------------------
; Operators & punctuation
; ------------------------------------------------------------------------------

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

; ------------------------------------------------------------------------------
; Annotations
; ------------------------------------------------------------------------------

(annotation
  name: (identifier) @attribute)

(annotation_key_value
  (identifier) @property)
