# Shared with tests/, which compiles Editor.vala and DocClaim.vala on their own.
editor_source = files('Editor.vala')
claim_source = files('DocClaim.vala')

mdex_sources = files(
  'Application.vala',
  'MainWindow.vala',
  'DocClaim.vala',
  'Editor.vala',
  'Preview.vala',
  'Revisions.vala',
)

executable(
  'mdex',
  mdex_sources,
  mdex_resources,
  dependencies: dependencies,
  install: true,
)
