# Shared with tests/, which compiles Editor.vala, DocClaim.vala, Comments.vala, CommentsPane.vala, Coverage.vala, CoveragePane.vala, DiskChange.vala, Herdr.vala, Preview.vala and MainWindow.vala on their own.
editor_source = files('Editor.vala')
claim_source = files('DocClaim.vala')
comments_source = files('Comments.vala')
commentspane_source = files('CommentsPane.vala')
coverage_source = files('Coverage.vala')
coveragepane_source = files('CoveragePane.vala')
diskchange_source = files('DiskChange.vala')
herdr_source = files('Herdr.vala')
preview_source = files('Preview.vala')
mainwindow_source = files('MainWindow.vala')

mdex_sources = files(
  'Application.vala',
  'MainWindow.vala',
  'Comments.vala',
  'CommentsPane.vala',
  'Coverage.vala',
  'CoveragePane.vala',
  'DiskChange.vala',
  'DocClaim.vala',
  'Editor.vala',
  'Herdr.vala',
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
