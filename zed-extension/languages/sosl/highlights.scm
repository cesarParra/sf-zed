;; SOSL highlights for Zed (Tree-sitter)
;;
;; This query is aligned to the upstream grammar query shipped in:
;; `grammars/apex/sosl/queries/highlights.scm`
;;
;; Notes:
;; - Zed will refuse to load this language if any referenced node/token type
;;   doesn't exist in the SOSL grammar. Keep this file aligned to upstream.
;; - Map upstream captures to Zed theme captures (avoid non-standard captures).

;------------------------------------------------------------------------------
; Core clauses / literals
;------------------------------------------------------------------------------

(find_clause
  (term) @string)

(sobject_return
  (identifier) @type)

;------------------------------------------------------------------------------
; Operators
;------------------------------------------------------------------------------

(with_type
  (_ "=" @operator))

;------------------------------------------------------------------------------
; Keywords (token-based)
;------------------------------------------------------------------------------

[
  "ALL"
  "DIVISION"
  "EMAIL"
  "FIND"
  "ListView"
  "HIGHLIGHT"
  "IN"
  "METADATA"
  "NAME"
  "NETWORK"
  "PHONE"
  "PricebookId"
  "RETURNING"
  "SIDEBAR"
  "SNIPPET"
  "SPELL_CORRECTION"
  "target_length"
  "USING"
] @keyword
