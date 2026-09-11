(function () {
  // GitHub export is a passthrough — the source is already GitHub-flavoured
  // markdown, so no token walk needed.
  window.mdex.registerExporter("github", "GitHub Markdown", function (tokens, raw) {
    return raw;
  });
})();
