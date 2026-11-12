# Editor.vala compiles into the test directly — unwrap is a static string
# function, so the test needs no widgets and stays a single binary.
unwrap_test = executable(
  'test-unwrap',
  files('unwrap.vala') + editor_source,
  dependencies: dependencies,
)

test('unwrap', unwrap_test)

# Builds an Editor, so it needs a display; the test skips (exit 77) without one.
lock_test = executable(
  'test-lock',
  files('lock.vala') + editor_source,
  dependencies: dependencies,
)

test('lock', lock_test)

# DocClaim.bus_name is a static string function too, so it compiles in on its
# own; the D-Bus half needs a session bus and a second window, so it has no test.
claim_test = executable(
  'test-docclaim',
  files('docclaim.vala') + claim_source,
  dependencies: dependencies,
)

test('docclaim', claim_test)

# The exporters are JavaScript, so this one runs under node when there is one.
node = find_program('node', required: false)
if node.found()
  test('exporters', node, args: [files('exporters.js')])
endif
