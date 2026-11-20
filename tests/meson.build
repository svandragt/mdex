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

# Builds an Editor, so it needs a display; the test skips (exit 77) without one.
reloadbanner_test = executable(
  'test-reloadbanner',
  files('reloadbanner.vala') + editor_source,
  dependencies: dependencies,
)

test('reloadbanner', reloadbanner_test)

# DocClaim.bus_name is a static string function too, so it compiles in on its
# own. The raise half claims names on the session bus, so it skips (exit 77) without one.
claim_test = executable(
  'test-docclaim',
  files('docclaim.vala') + claim_source,
  dependencies: dependencies,
)

test('docclaim', claim_test)

# Comments is a plain model over a JSON file, so it compiles in on its own and
# the test keeps its sidecars in a temp directory, never in the real cache.
comments_test = executable(
  'test-comments',
  files('comments.vala') + comments_source,
  dependencies: dependencies,
)

test('comments', comments_test)

# Coverage reads a plan's text and compares file names, so it compiles in on its own.
coverage_test = executable(
  'test-coverage',
  files('coverage.vala') + coverage_source,
  dependencies: dependencies,
)

test('coverage', coverage_test)

# Builds the pane's widgets, so it needs a display; the test skips (exit 77) without one.
coveragepane_test = executable(
  'test-coveragepane',
  files('coveragepane.vala') + coverage_source + coveragepane_source,
  dependencies: dependencies,
)

test('coveragepane', coveragepane_test)

# Builds a MainWindow, so it needs a display; the test skips (exit 77) without one.
mainwindow_test = executable(
  'test-mainwindow',
  files('mainwindow.vala') + mainwindow_source + editor_source + preview_source + comments_source + commentspane_source + coverage_source + coveragepane_source,
  mdex_resources,
  dependencies: dependencies,
)

test('mainwindow', mainwindow_test)

# DiskChange.decide is a pure function, so it compiles in on its own.
diskchange_test = executable(
  'test-diskchange',
  files('diskchange.vala') + diskchange_source,
  dependencies: dependencies,
)

test('diskchange', diskchange_test)

# Builds the pane's widgets, so it needs a display; the test skips (exit 77) without one.
commentspane_test = executable(
  'test-commentspane',
  files('commentspane.vala') + comments_source + commentspane_source,
  dependencies: dependencies,
)

test('commentspane', commentspane_test)

# The link allow-list is a static string function on Preview, so no widget is built and no display is needed.
previewlink_test = executable(
  'test-previewlink',
  files('previewlink.vala') + preview_source + comments_source + coverage_source,
  dependencies: dependencies,
)

test('previewlink', previewlink_test)

# Builds a Preview and loads the shell from the gresource, so it needs a display; the test skips (exit 77) without one.
previewcsp_test = executable(
  'test-previewcsp',
  files('previewcsp.vala') + preview_source + comments_source + coverage_source,
  mdex_resources,
  dependencies: dependencies,
)

test('previewcsp', previewcsp_test)

# Builds a Preview and loads the shell from the gresource, so it needs a display; the test skips (exit 77) without one.
previewcoverage_test = executable(
  'test-previewcoverage',
  files('previewcoverage.vala') + preview_source + comments_source + coverage_source,
  mdex_resources,
  dependencies: dependencies,
)

test('previewcoverage', previewcoverage_test)

# Builds a Preview and prints it to a file, so it needs a display; the test skips (exit 77) without one.
previewpdf_test = executable(
  'test-previewpdf',
  files('previewpdf.vala') + preview_source + comments_source + coverage_source,
  mdex_resources,
  dependencies: dependencies,
)

test('previewpdf', previewpdf_test)
# GTK names the Print to File printer in the user's language. Without the Dutch locale installed this runs in English.
test('previewpdf-nl', previewpdf_test, env: {'LANG': 'nl_NL.UTF-8', 'LANGUAGE': 'nl'})

# The exporters are JavaScript, so this one runs under node when there is one.
node = find_program('node', required: false)
if node.found()
  test('exporters', node, args: [files('exporters.js')])
endif

# Builds a Preview and selects text in it, so it needs a display; the test skips (exit 77) without one.
previewselection_test = executable(
  'test-previewselection',
  files('previewselection.vala') + preview_source + comments_source + coverage_source,
  mdex_resources,
  dependencies: dependencies,
)

test('previewselection', previewselection_test)

# Herdr's JSON parsers are static string functions, so the test compiles them in and needs no herdr.
herdr_test = executable(
  'test-herdr',
  files('herdr.vala') + herdr_source,
  dependencies: dependencies,
)

test('herdr', herdr_test)
