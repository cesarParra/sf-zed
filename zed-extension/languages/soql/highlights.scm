;; SOQL highlights for Zed (Tree-sitter)
;;
;; Aligned with the upstream SOQL highlights query shipped in the grammar repo:
;; `grammars/apex/soql/queries/highlights.scm`
;;
;; Notes:
;; - Zed will refuse to load the language if any node/token type referenced here
;;   does not exist in the SOQL grammar. So keep this file tightly aligned with
;;   the grammar’s REAL node/token names.
;; - Zed themes understand a fixed set of capture names; avoid non-standard ones.
;;   (The upstream query contains TextMate/VSC-ish captures like
;;   @variable.readonly.defaultLibrary; we map those to standard Zed captures.)

;------------------------------------------------------------------------------
; Identifiers / fields / labels
;------------------------------------------------------------------------------

(field_identifier
  (identifier) @property)

(field_identifier
  (dotted_identifier
    (identifier) @property))

(type_of_clause
  (identifier) @property)

(when_expression
  (identifier) @type)

(when_expression
  (field_list
    (identifier) @property))

(when_expression
  (field_list
    (dotted_identifier
      (identifier) @property )))

(else_expression
  (field_list
    (identifier) @property ))

(else_expression
  (field_list
    (dotted_identifier
      (identifier) @property )))

(alias_expression
  (identifier) @label)

(storage_identifier) @type

(_ function_name:(identifier) @function)

;------------------------------------------------------------------------------
; Punctuation
;------------------------------------------------------------------------------

[
  ","
  "."
  ":"
  "("
  ")"
] @punctuation

;------------------------------------------------------------------------------
; Operators
;------------------------------------------------------------------------------

[
  "AND"
  "OR"
  "NOT"
  "="
  "!="
  "LIKE"
  "NOT_IN"
  "INCLUDES"
  "EXCLUDES"
] @operator

(value_comparison_operator "<" @operator)
"<=" @operator
(value_comparison_operator ">" @operator)
">=" @operator

(set_comparison_operator "IN" @operator)

;------------------------------------------------------------------------------
; Literals
;------------------------------------------------------------------------------

(int) @number
(decimal) @number
(currency_literal) @number

(string_literal) @string

; Dates/times: no dedicated capture in Zed, treat them as constants.
(date) @constant
(date_time) @constant

; TRUE/FALSE/NULL are keywords-ish constants in SOQL.
[
  "TRUE"
  "FALSE"
  (null_literal)
] @constant

;------------------------------------------------------------------------------
; Keywords
;------------------------------------------------------------------------------

[
  "ABOVE"
  "ABOVE_OR_BELOW"
  "ALL"
  "AS"
  "ASC"
  "AT"
  "BELOW"
  "CUSTOM"
  "DATA_CATEGORY"
  "DESC"
  "ELSE"
  "END"
  "FIELDS"
  "FOR"
  "FROM"
  "GROUP_BY"
  "HAVING"
  "LIMIT"
  "NULLS_FIRST"
  "NULLS_LAST"
  "OFFSET"
  "ORDER_BY"
  "REFERENCE"
  "SELECT"
  "STANDARD"
  "THEN"
  "TRACKING"
  "TYPEOF"
  "UPDATE"
  "USING"
  "SCOPE"
  "LOOKUP"
  "BIND"
  "VIEW"
  "VIEWSTAT"
  "WITH"
  "WHERE"
  "WHEN"
] @keyword

;------------------------------------------------------------------------------
; Enum-like keyword sets (mapped to @type / @constant for Zed)
;------------------------------------------------------------------------------

; Using Scope
[
  "delegated"
  "everything"
  "mine"
  "mine_and_my_groups"
  "my_territory"
  "my_team_territory"
  "team"
] @type

; WITH clause options / parameters
[
  "maxDescriptorPerRecord"
  "RecordVisibilityContext"
  "Security_Enforced"
  "supportsDomains"
  "supportsDelegates"
  "System_Mode"
  "User_Mode"
  "UserId"
] @type
