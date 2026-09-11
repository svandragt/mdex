# Editor.vala compiles into the test directly — unwrap is a static string
# function, so the test needs no widgets and stays a single binary.
unwrap_test = executable(
  'test-unwrap',
  files('unwrap.vala') + editor_source,
  dependencies: dependencies,
)

test('unwrap', unwrap_test)

# The exporters are JavaScript, so this one runs under node when there is one.
node = find_program('node', required: false)
if node.found()
  test('exporters', node, args: [files('exporters.js')])
endif
