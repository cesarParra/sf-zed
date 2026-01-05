; Apex indentation rules for Zed (Tree-sitter indents query)
;
; Keep this intentionally minimal and robust by basing indentation on
; bracket/brace/paren pairs, similar to the Java extension.
;
; Captures:
; - @indent: node that introduces an indentation context
; - @end:    the closing delimiter that ends the indentation context

(_ "{" "}" @end) @indent
(_ "[" "]" @end) @indent
(_ "(" ")" @end) @indent
