def is_kebab?(case_name)
  ! (case_name =~ /[A-Z]+/ or case_name =~ /_+/)
end
