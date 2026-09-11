# mdex

A two-pane markdown editor for elementary OS. Write GitHub-flavoured markdown on
the left, see it rendered on the right, then export it to the format the
destination actually wants.

The editor is the easy half. The point is the export step: text drafted once
leaves as a Slack message, as ADF for Jira and Confluence Cloud, or as plain
GitHub markdown, without reformatting it by hand.

## Build and run

You need elementary OS 8 or another distribution with GTK 4, Granite 7,
WebKitGTK 6 and GtkSourceView 5.

```
sudo apt install libgtksourceview-5-dev libwebkitgtk-6.0-dev libgranite-7-dev \
                 libgtk-4-dev valac meson ninja-build
make run
```

`make test` runs the unwrapping checks.

`make install` puts `mdex` in `~/.local/bin` and its launcher in the
applications menu, neither of which needs sudo. For a system-wide install:

```
sudo make install PREFIX=/usr/local
```

## Use it

Open a file with the button in the header bar, pass a path on the command line,
or pipe text in:

```
mdex notes.md
claude -p "draft the release notes" | mdex
```

With no input, mdex starts on a scratch buffer. Everything autosaves a second
after you stop typing — to the file you opened, or to
`~/.cache/mdex/scratch.md` when there isn't one, so an unnamed session survives
a restart.

Export from the header bar menu, or with a shortcut:

| Format | Shortcut | Goes to |
| --- | --- | --- |
| GitHub Markdown | Ctrl+Shift+G | GitHub, and anywhere that takes CommonMark |
| Slack message | Ctrl+Shift+S | Slack |
| ADF | Ctrl+Shift+J | Jira and Confluence Cloud |

The result lands on the clipboard, ready to paste.

## Hard-wrapped text

Text from a language model usually arrives hard-wrapped at about 80 columns.
mdex treats those wraps as an artefact of how the text was written, not as
meaning:

- Anything you open, pipe in, or restore from the scratch buffer has its
  paragraphs unwrapped on load: the hard newlines inside a paragraph go, and it
  becomes one line. Headings, lists, quotes, tables and code blocks keep their
  shape, and a deliberate line break — two trailing spaces — survives.
- The editor soft-wraps, so those long lines never scroll sideways.
- The preview reflows each paragraph, because the renderer follows CommonMark
  rather than turning every newline into a line break.
- The exporters collapse any remaining newlines to single spaces. Slack renders
  literal newlines, so without this a message looks ragged even when the preview
  looked right.

Unwrapping rewrites the document, and autosave will keep it, so opening a
hard-wrapped file and typing one character reformats its paragraphs. Press
Ctrl+Shift+U, or use the Unwrap button, to reflow text you pasted into an
already-open document.

## Write a plugin

An exporter is a JavaScript file in `~/.config/mdex/plugins/`. It gets the
parsed token stream and the raw source, and returns a string:

```js
window.mdex.registerExporter('upper', 'Upper case', (tokens, raw) => {
    return raw.toUpperCase();
});
```

`examples/plaintext.js` is a working one: copy it to `~/.config/mdex/plugins/`
and "Plain text" appears in the Export menu alongside the built-in formats.

Restart mdex and the format appears in the Export menu. The three built-in
exporters register through the same call, so a plugin can do anything they can —
including replacing one of them by reusing its id.

## How it works

All markdown parsing happens once, in JavaScript, inside the preview WebView.
Rendering and exporting both walk the same token stream from
[marked](https://marked.js.org), so the preview and the export can't disagree
about what the document says. Vala handles the window, file I/O, autosave, the
command line and the clipboard.

The export menu is built at run time by asking the WebView which exporters are
registered. That is why a plugin is a first-class format rather than a
second-class one.

## Licence

The bundled [marked](https://github.com/markedjs/marked) and
[github-markdown-css](https://github.com/sindresorhus/github-markdown-css) are
MIT licensed and keep their own copyright notices.
