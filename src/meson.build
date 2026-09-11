# Shared with tests/, which compiles Editor.vala on its own.
editor_source = files('Editor.vala')

mdex_sources = files(
  'Application.vala',
  'MainWindow.vala',
  'Editor.vala',
  'Preview.vala',
)

executable(
  'mdex',
  mdex_sources,
  mdex_resources,
  dependencies: dependencies,
  install: true,
)
