; SOSL indentation rules for Zed (Tree-sitter indents query)
;
; IMPORTANT:
; Zed will fail to load this language if this file references tokens that are not
; present in the SOSL grammar. Keep indentation rules minimal and based only on
; widely-supported delimiter tokens.
;
; Captures:
; - @indent: node that introduces an indentation context
; - @end:    the closing delimiter that ends the indentation context

(_ "(" ")" @end) @indent
(_ "<" ">" @end) @indent
