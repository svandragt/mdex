# mdex

A two-pane markdown editor for elementary OS. Write GitHub-flavoured markdown on the left, see it rendered on the right, then export it to the format the destination actually wants.

The editor is the easy half. The point is what happens next: text drafted once leaves as a Slack message, as ADF for Jira and Confluence Cloud, or as plain GitHub markdown, without reformatting it by hand — or goes straight to your blog as a post.

## Build and run

You need elementary OS 8 or another distribution with GTK 4, Granite 7, WebKitGTK 6 and GtkSourceView 5.

```
sudo apt install libgtksourceview-5-dev libwebkitgtk-6.0-dev libgranite-7-dev \
                 libgtk-4-dev valac meson ninja-build
make run
```

`make test` runs the unwrapping checks.

`make install` puts `mdex` in `~/.local/bin` and its launcher in the applications menu, neither of which needs sudo. For a system-wide install:

```
sudo make install PREFIX=/usr/local
```

## Use it

Start an empty scratch buffer with the first header button or Ctrl+Shift+N, a new file with the next one or Ctrl+N, open an existing one with Ctrl+O, save a copy of the text to another file with the save button or Ctrl+Shift+S, pass a path on the command line, or pipe text in. Ctrl+Q saves and quits:

```
mdex notes.md
claude -p "draft the release notes" | mdex
```

A file opened from the command line, or brought forward by a second launch, starts read-only, so typing meant for another window cannot end up in it. A banner says so, and a click in the text makes it editable.

With no input, mdex reopens the document you had last time, or a scratch buffer if there wasn't one. Everything autosaves a second after you stop typing — to the file you opened, or to `~/.cache/mdex/scratch.md` when there isn't one, so an unnamed session survives a restart. Every launch is a separate instance, so run `mdex` twice to work on two documents side by side. A document that is already open in a window opens only there: opening it again from the command line, Ctrl+O or New file brings that window to the front.

The preview shows what a document says but does not run it: scripts and styles inside a Markdown file are ignored, and audio, video and embedded frames do not load. A link opens in your browser or mail program only when it starts with `http:`, `https:` or `mailto:`.

Export from the header bar menu, or with a shortcut:

| Format | Shortcut | Goes to |
| --- | --- | --- |
| GitHub Markdown | Ctrl+Shift+G | GitHub, and anywhere that takes CommonMark |
| Slack message | Ctrl+Shift+S | Slack |
| ADF | Ctrl+Shift+J | Jira and Confluence Cloud |

The result lands on the clipboard, ready to paste.

## Revisions

A draft often starts as generated key points and ends as a finished message. mdex keeps snapshots along the way so you can see what changed. Press Ctrl+H or the clock button to open the revisions window, pick any two snapshots (or a snapshot and the current text) and read the unified diff. The Restore button puts the left-hand snapshot back in the editor, after snapshotting what it replaces.

Each snapshot is labelled with when and why it was taken:

| Label | Taken |
| --- | --- |
| Original | when a document is opened or piped in |
| export, publish | when you export or publish, because that version went out |
| external | when the file changes on disk while you have unsaved edits, because autosave then replaces that text |
| before reload | when a change on disk replaces the text in the editor, whether you pressed Reload or mdex reloaded by itself, so the text you had can be restored; skipped when a snapshot already holds it |
| pause | on the first edit after five minutes away, keeping the version that sat still |
| manual | when you press Ctrl+S |
| before restore | when you restore an older snapshot |

Snapshots live in `~/.cache/mdex/revisions/`, one directory per document; starting a new scratch buffer clears the old scratch history.

## Comments

To comment on a passage, select it in the preview and press C, or click the Comment button that appears by the selection. Type your comment and press Enter. The first comment on a document also opens the Comments pane. The passage is underlined in the preview. A comment on text that appears more than once stays on the occurrence you selected. Hover over it to read the comment and any reply, or click it to open the Comments pane at that comment.

The Comments button in the header bar opens a pane on the right. It lists open comments first, each with Resolve and Dismiss, and Edit until someone has replied. Resolved and dismissed comments wait in a collapsed list below. Click a comment to scroll the preview to its passage. A comment whose passage is no longer in the document says "Text changed".

A coding session that edits the same file can answer your comments. Its reply appears under the comment, and mdex reloads the document. If you have unsaved edits, a banner above the editor offers Reload or Keep mine and stays until you pick one. If the session rewrote the passage, the underline and the scroll follow it to the new text. When you have unsaved edits, mdex keeps the text now on disk as an "external" snapshot, so Restore in the revisions window brings it back after autosave has replaced it.

Comments are kept outside the document, in `~/.cache/mdex/comments/`, so they never end up in the file, its exports or its git diff. `mdex --comments-path notes.md` prints where the comments for `notes.md` live, for a session to find.

## Publish to your blog

The send button in the header bar publishes the document to your Micropub endpoint through [mp](https://github.com/mjdescy/mp), so mdex never handles your endpoint or token. The button appears once mp is on your PATH. Install and configure it once:

```
cargo install --git https://github.com/mjdescy/mp --tag v0.1.1 -p mpcli
mp configure
```

A level 1 heading on the first line becomes the post title; without one the post is untitled. Publishing goes live straight away, so mdex asks to confirm first, then opens the published post in your browser.

## Hard-wrapped text

Text from a language model usually arrives hard-wrapped at about 80 columns. mdex treats those wraps as an artefact of how the text was written, not as meaning:

- Anything you open, pipe in, paste, or restore from the scratch buffer has its   paragraphs unwrapped on load: the hard newlines inside a paragraph go, and it   becomes one line. Headings, lists, quotes, tables and code blocks keep their   shape, and a deliberate line break — two trailing spaces — survives.
- The editor soft-wraps, so those long lines never scroll sideways.
- The preview reflows each paragraph, because the renderer follows CommonMark   rather than turning every newline into a line break.
- The exporters collapse any remaining newlines to single spaces. Slack renders   literal newlines, so without this a message looks ragged even when the preview   looked right.

Unwrapping rewrites the document, and autosave will keep it, so opening a hard-wrapped file and typing one character reformats its paragraphs. Press Ctrl+Shift+U to reflow text that arrived some other way.

## Format as you type

| Shortcut | Does |
|---|---|
| Ctrl+B | Wrap the selection in `**bold**` |
| Ctrl+I | Wrap the selection in `_italic_` |
| Ctrl+L | Turn the selection into `[a link]()`, cursor in the brackets |
| Ctrl+1 to Ctrl+6 | Make the current line a heading of that level |
| Ctrl+0 | Remove the heading |
| Ctrl+F | Search the document. Enter or Ctrl+G goes to the next match, Shift+Enter to the previous one, and Esc closes the search bar |

With nothing selected, the markers go in at the cursor with the cursor between them. Pasting a URL over selected text links it: select the words, paste, done.

## Write a plugin

An exporter is a JavaScript file in `~/.config/mdex/plugins/`. It gets the parsed token stream and the raw source, and returns a string:

```js
window.mdex.registerExporter('upper', 'Upper case', (tokens, raw) => {
    return raw.toUpperCase();
});
```

`examples/plaintext.js` is a working one: copy it to `~/.config/mdex/plugins/`, restart mdex, and "Plain text" appears in the Export menu alongside the built-in formats. The three built-in exporters register through the same call, so a plugin can do anything they can — including replacing one of them by reusing its id.

A plugin runs in the preview page, where the page's security policy makes `fetch`, `eval` and `new Function` fail. The policy does not contain a plugin, so install only plugins you trust.

## How it works

All markdown parsing happens once, in JavaScript, inside the preview WebView. Rendering and exporting both walk the same token stream from [marked](https://marked.js.org), so the preview and the export can't disagree about what the document says. Vala handles the window, file I/O, autosave, the command line and the clipboard.

Publishing shells out to mp rather than speaking Micropub itself. Your token stays in mp's config, and a blog mp can post to is a blog mdex can post to.

The export menu is built at run time by asking the WebView which exporters are registered. That is why a plugin is a first-class format rather than a second-class one.

## Licence

The bundled [marked](https://github.com/markedjs/marked) and [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) are MIT licensed and keep their own copyright notices.
