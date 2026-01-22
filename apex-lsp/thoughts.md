# In the future we will also want keywords here (and even built-in snippets)
CompletionCandidate
  | None # no candidates
  | Type # the top level type (class, enum, interface)
  | Member # a member of a type
  | Variable # a locally declared variable (for anon apex)
  
Type
  | Indexed { Name::String } # Somewhere in the index (in another file)
  | Local { Name::String } # Somewhere local but not the class being edited (for anon apex)
  | Self # the class being edited itself
  
Member {
  Type::MemberType
}

MemberType
  | Static
  | Instance
