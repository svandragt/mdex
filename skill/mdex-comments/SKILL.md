---
name: mdex-comments
description: Answer the review comments a person left on a Markdown document in the mdex editor. Use when asked to address, answer or work through mdex comments on a file.
---

# Answer mdex review comments

A person reviews a Markdown document in mdex by selecting text in the rendered preview and commenting on it. The comments live in a JSON file outside the document. You read them, edit the document, and write a reply on each comment you answered. mdex shows the reply and reloads the document.

## Find the comments file

Run `mdex --comments-path <file>`. It prints the path and exits. It needs a display, because mdex starts a GTK application first.

Without a display, build the path yourself: `~/.cache/mdex/comments/<md5>.json`, where `<md5>` is the MD5 of the document's absolute path with no trailing newline (`printf '%s' /abs/path/notes.md | md5sum`). Use `$XDG_CACHE_HOME` in place of `~/.cache` when it is set. mdex does not resolve symbolic links, so hash the path as it was opened.

If the file does not exist, there are no comments.

## Format

The file is a JSON list:

```json
[
  {
    "id": "c1",
    "quote": "Some bold text here for review.",
    "occurrence": 1,
    "body": "Tighten this wording.",
    "status": "open",
    "reply": null,
    "change_quote": null,
    "created": "2026-11-12T18:18:40+00:00"
  }
]
```

- `quote` is the rendered text the person selected, with Markdown syntax removed and whitespace collapsed. Find it in the document by its words, not by its source characters: `**bold**` and link URLs are not in the quote.
- `occurrence` is which occurrence of `quote` in the rendered text the comment is on, counting from 1. When `quote` appears more than once, use it to pick the passage the person meant. A comment without it is on occurrence 1.
- `status` is `open`, `resolved` or `dismissed`.
- `reply` is `null` until a session answers.

## Protocol

1. Read the file. The comments to answer are those with `status` `open` and an empty `reply`.
2. For each one, edit the document as the comment asks. If you decide not to, leave the document alone and say why in the reply.
3. Set `reply` to one or two plain sentences on what you did or why you did not. Set `change_quote` to a short phrase from the new text. mdex underlines and scrolls to that phrase instead of the old `quote`, so the person finds the change. mdex looks for that phrase from its first occurrence, so choose one that appears once in the document.
4. Read the file again just before writing, because mdex may have added a comment or changed a status in the meantime. Change only `reply` and `change_quote` on the comments you answered.
5. Write the whole list back atomically: write a temporary file in the same directory, then rename it over the comments file.

## Rules

- Never change `status`, `body`, `quote`, `occurrence`, `id` or `created`. The person resolves or dismisses a comment in mdex.
- Keep every member you do not know, on every comment.
- Do not delete, reorder or add comments.
- If the file is not valid JSON, do not write to it. Tell the person.
