; SOQL indentation rules for Zed (Tree-sitter indents query)
;
; IMPORTANT: Zed will fail to load the language if this query references tokens
; that are not present in the SOQL grammar.
;
; The SOQL grammar provides tokens for "(" and ")" (and also "<" and ">"), but
; does NOT provide "["/"]" or "{"/"}" tokens. So we only indent via parentheses.
;
; Captures:
; - @indent: node that introduces an indentation context
; - @end:    the closing delimiter that ends the indentation context

(_ "(" ")" @end) @indent
