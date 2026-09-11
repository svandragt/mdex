# Editor.vala compiles into the test directly — unwrap is a static string
# function, so the test needs no widgets and stays a single binary.
unwrap_test = executable(
  'test-unwrap',
  files('unwrap.vala') + editor_source,
  dependencies: dependencies,
)

test('unwrap', unwrap_test)
