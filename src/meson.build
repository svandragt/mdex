# Shared with tests/, which compiles Editor.vala, DocClaim.vala, Comments.vala, CommentsPane.vala, DiskChange.vala and Preview.vala on their own.
editor_source = files('Editor.vala')
claim_source = files('DocClaim.vala')
comments_source = files('Comments.vala')
commentspane_source = files('CommentsPane.vala')
diskchange_source = files('DiskChange.vala')
preview_source = files('Preview.vala')

mdex_sources = files(
  'Application.vala',
  'MainWindow.vala',
  'Comments.vala',
  'CommentsPane.vala',
  'DiskChange.vala',
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
