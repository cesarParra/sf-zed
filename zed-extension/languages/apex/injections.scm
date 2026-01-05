;; Inject SOQL (and SOSL) highlighting into Apex files.
;;
;; The Apex grammar (from aheber/tree-sitter-sfapex) represents inline queries
;; with a `query_expression` node whose child is `soql_query_body` or
;; `sosl_query_body`.
;;
;; Important: Only `@injection.content` / `@injection.language` captures are
;; recognized in `injections.scm`. Do not add highlight captures here.

;------------------------------------------------------------------------------
; SOQL injection
;------------------------------------------------------------------------------

(query_expression
  (soql_query_body) @injection.content
  (#set! injection.language "soql"))

;------------------------------------------------------------------------------
; SOSL injection (optional; will only take effect if you register a SOSL language)
;------------------------------------------------------------------------------

(query_expression
  (sosl_query_body) @injection.content
  (#set! injection.language "sosl"))
