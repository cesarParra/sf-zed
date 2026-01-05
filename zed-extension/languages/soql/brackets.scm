; Bracket matching for SOQL
; Captures:
; - @open  opening bracket/quote
; - @close closing bracket/quote
;
; Keep this aligned with the SOQL grammar token set.
;
; The SOQL grammar provides tokens for "(" and ")" and for "<" and ">".
; It does NOT provide "[" / "]" or "{" / "}" tokens, so including them causes
; Zed to fail loading this language with "Invalid node type [".

; Grouping delimiters
("(" @open ")" @close)

; Angle brackets (present in the grammar token set)
("<" @open ">" @close)
