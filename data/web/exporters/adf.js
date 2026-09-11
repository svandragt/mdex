(function () {
  // Collapse hard-wrap softbreaks and runs of whitespace to a single space.
  // Not trimmed here — trimming happens once per assembled content array
  // (trimContent), since a single word can be split across text nodes by
  // marks (bold, links, ...).
  function collapseWs(s) {
    return (s || "").replace(/\s+/g, " ");
  }

  function pushText(out, text, marks) {
    const collapsed = window.mdex.unescape(collapseWs(text));
    if (!collapsed) return;
    const node = { type: "text", text: collapsed };
    if (marks && marks.length) node.marks = marks;
    out.push(node);
  }

  // Renders inline tokens to an ADF inline content array, threading marks
  // down through nested emphasis/links. ADF forbids empty text nodes, so
  // trimContent() strips leading/trailing space and drops any that end up
  // empty.
  function inline(tokens, marks) {
    marks = marks || [];
    const out = [];
    (tokens || []).forEach(function (t) {
      switch (t.type) {
        case "strong":
          out.push.apply(out, inline(t.tokens, marks.concat([{ type: "strong" }])));
          break;
        case "em":
          out.push.apply(out, inline(t.tokens, marks.concat([{ type: "em" }])));
          break;
        case "del":
          out.push.apply(out, inline(t.tokens, marks.concat([{ type: "strike" }])));
          break;
        case "codespan":
          pushText(out, t.text, marks.concat([{ type: "code" }]));
          break;
        case "link":
          out.push.apply(
            out,
            inline(t.tokens, marks.concat([{ type: "link", attrs: { href: t.href } }]))
          );
          break;
        case "br":
          pushText(out, " ", marks);
          break;
        case "image":
          pushText(out, t.text || t.href || "", marks);
          break;
        case "escape":
          pushText(out, t.text, marks);
          break;
        case "html":
          break;
        default:
          pushText(out, t.text || "", marks);
      }
    });
    return out;
  }

  function trimContent(nodes) {
    if (!nodes.length) return nodes;
    const first = nodes[0];
    if (first.type === "text") first.text = first.text.replace(/^ +/, "");
    const last = nodes[nodes.length - 1];
    if (last.type === "text") last.text = last.text.replace(/ +$/, "");
    return nodes.filter(function (n) { return n.type !== "text" || n.text !== ""; });
  }

  function paragraph(tokens) {
    const content = trimContent(inline(tokens));
    return content.length ? { type: "paragraph", content: content } : null;
  }

  function blocks(tokens) {
    const out = [];
    (tokens || []).forEach(function (t) {
      const node = block(t);
      if (node) out.push(node);
    });
    return out;
  }

  function block(t) {
    switch (t.type) {
      case "space":
        return null;
      case "hr":
        return { type: "rule" };
      case "heading": {
        const content = trimContent(inline(t.tokens));
        return content.length
          ? { type: "heading", attrs: { level: t.depth || 1 }, content: content }
          : null;
      }
      case "paragraph":
        return paragraph(t.tokens);
      case "text":
        return t.tokens ? paragraph(t.tokens) : null;
      case "code":
        return {
          type: "codeBlock",
          attrs: t.lang ? { language: t.lang } : {},
          content: t.text ? [{ type: "text", text: t.text }] : [],
        };
      case "blockquote": {
        const content = blocks(t.tokens);
        return content.length ? { type: "blockquote", content: content } : null;
      }
      case "list":
        return list(t);
      case "table":
        return table(t);
      default:
        return null;
    }
  }

  function list(listToken) {
    const node = {
      type: listToken.ordered ? "orderedList" : "bulletList",
      content: listToken.items.map(listItem),
    };
    if (listToken.ordered && Number(listToken.start) > 1) {
      node.attrs = { order: Number(listToken.start) };
    }
    return node;
  }

  function listItem(item) {
    const content = [];
    (item.tokens || []).forEach(function (t) {
      if (t.type === "text") {
        const p = t.tokens ? paragraph(t.tokens) : null;
        if (p) content.push(p);
      } else {
        const node = block(t);
        if (node) content.push(node);
      }
    });
    return { type: "listItem", content: content };
  }

  function tableCell(cellType, cell) {
    const p = paragraph(cell.tokens) || { type: "paragraph", content: [] };
    return { type: cellType, content: [p] };
  }

  function table(t) {
    const headerRow = { type: "tableRow", content: t.header.map(function (c) { return tableCell("tableHeader", c); }) };
    const rows = t.rows.map(function (row) {
      return { type: "tableRow", content: row.map(function (c) { return tableCell("tableCell", c); }) };
    });
    return { type: "table", content: [headerRow].concat(rows) };
  }

  window.mdex.registerExporter("adf", "ADF (Jira / Confluence)", function (tokens, raw) {
    const doc = { version: 1, type: "doc", content: blocks(tokens) };
    return JSON.stringify(doc, null, 2);
  });
})();
