(function () {
  // Collapse hard-wrap softbreaks and runs of whitespace to a single space.
  // Applied once per assembled block of inline text.
  function collapse(s) {
    return (s || "").replace(/\s+/g, " ").trim();
  }

  // Renders a list of inline tokens (marked's Lexer output) to Slack markup.
  function inline(tokens) {
    return (tokens || []).map(inlineToken).join("");
  }

  function inlineToken(t) {
    switch (t.type) {
      case "strong":
        return "*" + inline(t.tokens) + "*";
      case "em":
        return "_" + inline(t.tokens) + "_";
      case "del":
        return "~" + inline(t.tokens) + "~";
      case "codespan":
        return "`" + t.text + "`";
      case "br":
        return " ";
      case "link": {
        const label = inline(t.tokens).trim();
        if (!label || label === t.href) return t.href;
        // Bracket syntax is never valid Slack markup — fall back to the
        // label followed by the bare URL on its own line.
        return label + "\n" + t.href;
      }
      case "image":
        return t.href || "";
      case "escape":
        return t.text || "";
      case "html":
        return "";
      default:
        return t.text || "";
    }
  }

  function inlineBlock(tokens) {
    return collapse(inline(tokens));
  }

  // Renders a list of block tokens, joining sibling blocks with a blank line.
  function blocks(tokens) {
    return (tokens || [])
      .map(block)
      .filter(function (s) { return s !== "" && s !== null && s !== undefined; })
      .join("\n\n");
  }

  function block(t) {
    switch (t.type) {
      case "space":
        return "";
      case "hr":
        return "---";
      case "heading":
        // No heading levels in Slack — a bold line stands in for all of them.
        return "*" + inlineBlock(t.tokens) + "*";
      case "paragraph":
        return inlineBlock(t.tokens);
      case "text":
        return t.tokens ? inlineBlock(t.tokens) : collapse(t.text);
      case "code":
        return "```\n" + t.text + "\n```";
      case "blockquote":
        return blocks(t.tokens)
          .split("\n")
          .map(function (l) { return l ? "> " + l : ">"; })
          .join("\n");
      case "list":
        return list(t, 0);
      case "table":
        return table(t);
      default:
        return t.tokens ? inlineBlock(t.tokens) : t.text ? collapse(t.text) : "";
    }
  }

  function list(listToken, depth) {
    const indent = "  ".repeat(depth);
    let n = Number(listToken.start) || 1;
    return listToken.items
      .map(function (item) {
        const marker = listToken.ordered ? n++ + ". " : "• ";
        const lines = listItem(item, depth);
        lines[0] = indent + marker + lines[0];
        return lines.join("\n");
      })
      .join("\n");
  }

  // Returns the item's own text as lines[0], with any nested block content
  // (sublists, nested code/quotes) as further already-indented lines.
  function listItem(item, depth) {
    const lines = [];
    (item.tokens || []).forEach(function (t) {
      if (t.type === "list") {
        lines.push(list(t, depth + 1));
      } else if (t.type === "text") {
        lines.push(inlineBlock(t.tokens || []));
      } else if (t.type === "paragraph") {
        lines.push(inlineBlock(t.tokens));
      } else {
        const s = block(t);
        if (s) lines.push(s);
      }
    });
    if (!lines.length) lines.push(collapse(item.text || ""));
    return lines;
  }

  // No native table support in Slack — fall back to "Label: value" lines,
  // one blank line between rows.
  function table(t) {
    const headers = t.header.map(function (c) { return inlineBlock(c.tokens); });
    return t.rows
      .map(function (row) {
        return row
          .map(function (cell, i) {
            return (headers[i] || "Column " + (i + 1)) + ": " + inlineBlock(cell.tokens);
          })
          .join("\n");
      })
      .join("\n\n");
  }

  window.mdex.registerExporter("slack", "Slack message", function (tokens, raw) {
    return blocks(tokens).trim();
  });
})();
