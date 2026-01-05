; Bracket matching for SOSL
; Captures:
; - @open  opening bracket/quote
; - @close closing bracket/quote
;
; IMPORTANT:
; This file must only reference tokens that exist in the SOSL tree-sitter grammar.
; Unlike Apex, SOSL does not necessarily include brackets/braces tokens. Keep this
; minimal and expand only after confirming token presence in the SOSL `node-types.json`.

; Parentheses are commonly used by the grammar (e.g. function-like constructs)
("(" @open ")" @close)

; Angle brackets are sometimes present depending on the grammar/tokenizer
("<" @open ">" @close)
