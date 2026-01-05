; Bracket matching for Apex
; Captures:
; - @open  opening bracket/quote
; - @close closing bracket/quote

; Grouping delimiters
("(" @open ")" @close)
("[" @open "]" @close)
("{" @open "}" @close)

; String delimiters
; This grammar exposes the single-quote token (') but does not expose a standalone
; double-quote token ("), so only include the one that exists to avoid query errors.
("'" @open "'" @close)

; Generic type arguments and shifting operators can conflict in some grammars.
; Still, angle brackets are commonly used for generics in Apex, so include them.
("<" @open ">" @close)
