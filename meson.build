project('mdex', 'vala', 'c',
  version: '0.1.0',
)

gnome = import('gnome')
valac = meson.get_compiler('vala')

dependencies = [
  dependency('gtk4'),
  dependency('granite-7'),
  dependency('webkitgtk-6.0'),
  dependency('javascriptcoregtk-6.0'),
  dependency('gtksourceview-5'),
  dependency('json-glib-1.0'),
  dependency('gee-0.8'),
  valac.find_library('posix'),
]

subdir('data')
subdir('src')

subdir('tests')
