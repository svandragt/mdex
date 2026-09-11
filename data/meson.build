mdex_resources = gnome.compile_resources(
  'mdex-resources',
  'mdex.gresource.xml',
  source_dir: '.',
  c_name: 'mdex',
)

install_data(
  'com.github.svandragt.mdex.desktop',
  install_dir: get_option('datadir') / 'applications',
)
