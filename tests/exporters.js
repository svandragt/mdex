// Loads the real shell bridge and exporters in Node and checks their output.
// The page's <script> blocks are extracted rather than duplicated, so this
// tests what ships.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const web = path.join(__dirname, "..", "data", "web");
const read = (p) => fs.readFileSync(path.join(web, p), "utf8");

const bridge = read("shell.html").match(/<script[^>]*>\s*\(function \(\) \{[\s\S]*?<\/script>/)[0]
  .replace(/^<script[^>]*>|<\/script>$/g, "");

// A minimal DOM, just enough for markQuotes: text nodes (no tagName) and
// elements, with the node methods the bridge calls.
class FakeNode {
  constructor(tagName, data) {
    this.tagName = tagName;
    this.nodeType = tagName ? 1 : 3;
    this.nodeName = tagName ? tagName.toUpperCase() : "#text";
    this.data = data;
    this.className = "";
    this.title = "";
    this.attrs = {};
    this.dataset = {};
    this.listeners = {};
    this.parentNode = null;
    this.childNodes = [];
  }
  appendChild(c) {
    if (c.parentNode) c.parentNode.childNodes.splice(c.parentNode.childNodes.indexOf(c), 1);
    c.parentNode = this;
    this.childNodes.push(c);
    return c;
  }
  replaceChild(n, old) {
    this.childNodes[this.childNodes.indexOf(old)] = n;
    n.parentNode = this;
    old.parentNode = null;
    return old;
  }
  replaceWith(...ns) {
    this.parentNode.childNodes.splice(this.parentNode.childNodes.indexOf(this), 1, ...ns);
    ns.forEach((n) => (n.parentNode = this.parentNode));
  }
  splitText(at) {
    const tail = text(this.data.slice(at));
    this.data = this.data.slice(0, at);
    tail.parentNode = this.parentNode;
    this.parentNode.childNodes.splice(this.parentNode.childNodes.indexOf(this) + 1, 0, tail);
    return tail;
  }
  normalize() {
    const kids = [];
    for (const c of this.childNodes) {
      const prev = kids[kids.length - 1];
      if (c.tagName) { c.normalize(); kids.push(c); }
      else if (prev && !prev.tagName) prev.data += c.data;
      else if (c.data) kids.push(c);
    }
    this.childNodes = kids;
  }
  // Selectors like "mark.a, mark.b" or ".c": an optional tag and the classes the element must carry. With none, every mark.
  querySelectorAll(selector = "mark") {
    const wants = selector.split(",").map((s) => s.trim().split("."));
    const matches = (c) => wants.some(([tag, ...classes]) => (!tag || c.tagName === tag) && classes.every((k) => c.className.split(" ").includes(k)));
    const found = [];
    for (const c of this.childNodes) if (c.tagName) { if (matches(c)) found.push(c); found.push(...c.querySelectorAll(selector)); }
    return found;
  }
  get classList() {
    return { toggle: (name, on) => { const rest = this.className.split(" ").filter((k) => k && k !== name); this.className = (on ? [...rest, name] : rest).join(" "); } };
  }
  setAttribute(name, value) { this.attrs[name] = String(value); }
  getAttribute(name) { return name in this.attrs ? this.attrs[name] : null; }
  hasAttribute(name) { return name in this.attrs; }
  addEventListener(type, f) {
    this.listeners[type] = f;
  }
  // Only the one selector the bridge uses, "mark.mdex-comment".
  closest() {
    for (let n = this; n; n = n.parentNode) if (n.tagName === "mark") return n;
    return null;
  }
  contains(n) {
    for (; n; n = n.parentNode) if (n === this) return true;
    return false;
  }
}
const text = (data) => new FakeNode(undefined, data);
const el = (tag, ...kids) => kids.reduce((e, k) => (e.appendChild(typeof k === "string" ? text(k) : k), e), new FakeNode(tag));
const html = (n) => (n.tagName ? `<${n.tagName}>${n.childNodes.map(html).join("")}</${n.tagName}>` : n.data);

const root = el("div");
const commentButton = { hidden: true, style: {}, offsetWidth: 80, offsetHeight: 24, listeners: {}, addEventListener(type, f) { this.listeners[type] = f; }, contains(n) { return n === this; } };
const docListeners = {};
const tops = new Map();
const scrolls = [];
let walks = 0;
const sandbox = {
  document: {
    getElementById: (id) => (id === "output" ? root : commentButton),
    createElement: (tag) => el(tag),
    // Like the real one, hands out the node kinds whatToShow asks for, in document order.
    createTreeWalker(r, whatToShow) {
      walks++;
      const found = [];
      (function walk(n) { n.childNodes.forEach((c) => { if (whatToShow & (c.tagName ? 1 : 4)) found.push(c); if (c.tagName) walk(c); }); })(r);
      return { nextNode: () => found.shift() || null };
    },
    addEventListener: (type, f) => { docListeners[type] = f; },
    // A range remembers its start node; its rect comes from the tops the test sets per node.
    createRange: () => ({
      setStart(n, o) { this.node = n; this.start = o; },
      setEnd(n, o) { this.endNode = n; this.end = o; },
      getBoundingClientRect() { return { top: tops.get(this.node), height: 20 }; },
    }),
    documentElement: { setAttribute() {} },
  },
  NodeFilter: { SHOW_ELEMENT: 1, SHOW_TEXT: 4 },
  setTimeout: (f) => f(),
  innerWidth: 800,
  innerHeight: 600,
  scrollX: 0,
  scrollY: 0,
  scrollBy: (x, y) => scrolls.push([x, y]),
};
sandbox.window = sandbox;
vm.createContext(sandbox);
vm.runInContext(read("marked.min.js"), sandbox);
vm.runInContext(bridge, sandbox);
["github", "slack", "adf"].forEach((e) => vm.runInContext(read(`exporters/${e}.js`), sandbox));

const run = (id, md) => JSON.parse(sandbox.window.mdex.run(id, md)).text;
const runHtml = (id, md) => JSON.parse(sandbox.window.mdex.run(id, md)).html;

// Entities from marked's escaping must not reach the exported text.
const md = "Merged after James's review of \"the\" thing & more.";
const slack = run("slack", md);
assert.ok(!/&(#\d+|amp|quot|lt|gt);/.test(slack), `entities in slack export: ${slack}`);
assert.ok(slack.includes("James's review"), slack);
assert.ok(slack.includes('"the" thing & more'), slack);

const adf = run("adf", md);
assert.ok(!/&(#\d+|amp|quot|lt|gt);/.test(adf), `entities in adf export: ${adf}`);

// Codespans and code blocks go through the same escaping.
const code = run("slack", "Use `a && b` here.\n\n```\nx > y && z\n```");
assert.ok(!/&(#\d+|amp|quot|lt|gt);/.test(code), code);

// Links carry their own label rather than trailing a bare URL.
const link = run("slack", "See [burohappold#558](https://example.com/pull/558) today.");
assert.strictEqual(link, "See [burohappold#558](https://example.com/pull/558) today.");
assert.strictEqual(run("slack", "<https://example.com/bare>"), "https://example.com/bare");

// A heading exports as one bold line, so emphasis inside it adds no markers
// of its own: nested asterisks make Slack pair them wrongly. Italic inside
// bold is valid Slack and stays.
assert.strictEqual(run("slack", "#### H4 with **bold** inside"), "*H4 with bold inside*");
assert.strictEqual(run("slack", "## H2 with *italic* inside"), "*H2 with _italic_ inside*");
assert.strictEqual(run("slack", "*outer _inner_ outer*"), "_outer inner outer_");
assert.strictEqual(run("slack", "**outer __inner__ outer**"), "*outer inner outer*");
// Headings and emphasis without nesting are unchanged.
assert.strictEqual(run("slack", "## Plain heading"), "*Plain heading*");
assert.strictEqual(run("slack", "Some **bold** and *italic* text."), "Some *bold* and _italic_ text.");

// Slack's HTML flavour carries the preview pane's links.
const linkHtml = runHtml("slack", "See [burohappold#558](https://example.com/pull/558) today.");
assert.ok(linkHtml.includes('<a href="https://example.com/pull/558"'), linkHtml);

// Slack drops the gap between pasted blocks, so the HTML flavour separates
// them with a spacer paragraph that survives the paste.
const sections = runHtml("slack", "**Key points**\n- one\n\n**Tomorrow**\n- two");
assert.strictEqual(sections.match(/<p>&nbsp;<\/p>/g).length, 3, sections);
// Reference links still resolve, so the per-block parse keeps tokens.links.
assert.ok(runHtml("slack", "See [ref][1].\n\n[1]: https://example.com/ref").includes('href="https://example.com/ref"'));

// github has no HTML flavour.
assert.strictEqual(runHtml("github", md), "");

// markQuotes wraps each quote's first occurrence in rendered text and reports
// which quotes it found. Results are compared as JSON because arrays made
// inside the vm sandbox have a different prototype.
const mdex = sandbox.window.mdex;
const json = JSON.stringify;
const setContent = (...kids) => { root.childNodes = []; kids.forEach((k) => root.appendChild(k)); };
const mark = (quotes) => json(mdex.markQuotes(quotes.map((quote, i) => ({ id: "c" + i, quote: quote, title: "t" + i }))));

// A quote inside one text node; only its first occurrence is marked.
setContent(el("p", "The quick brown fox, the quick one"));
assert.strictEqual(mark(["quick brown"]), "[true]");
assert.strictEqual(html(root), "<div><p>The <mark>quick brown</mark> fox, the quick one</p></div>");

// A quote across **bold** and across a link is marked piece by piece.
setContent(el("p", "Some ", el("strong", "bold"), " text here"));
assert.strictEqual(mark(["Some bold text"]), "[true]");
assert.strictEqual(html(root), "<div><p><mark>Some </mark><strong><mark>bold</mark></strong><mark> text</mark> here</p></div>");
setContent(el("p", "See ", el("a", "the docs"), " now."));
assert.strictEqual(mark(["the docs now"]), "[true]");
assert.strictEqual(html(root), "<div><p>See <a><mark>the docs</mark></a><mark> now</mark>.</p></div>");

// Whitespace is collapsed on both sides, also across a node boundary.
setContent(el("p", "alpha\n  beta   gamma"));
assert.strictEqual(mark(["  alpha beta\tgamma \n"]), "[true]");
assert.strictEqual(html(root), "<div><p><mark>alpha\n  beta   gamma</mark></p></div>");
setContent(el("p", "alpha ", el("em", "beta")));
assert.strictEqual(mark(["alpha\n\nbeta"]), "[true]");

// A hard line break counts as whitespace, as in the selection's text, so a quote across it is found; the <br> itself is not marked.
setContent(el("p", "Line one", el("br"), "line two"));
assert.strictEqual(mark(["Line one line two"]), "[true]");
assert.strictEqual(html(root), "<div><p><mark>Line one</mark><br></br><mark>line two</mark></p></div>");
setContent(el("p", "Line one ", el("br"), " line two"), el("p", "x"));
assert.strictEqual(mark(["one line"]), "[true]");
assert.strictEqual(html(root), "<div><p>Line <mark>one </mark><br></br><mark> line</mark> two</p><p>x</p></div>");

// A quote that is not there, or is blank, returns false and marks nothing.
setContent(el("p", "The quick brown fox"));
assert.strictEqual(mark(["quick", "slow", "", "  "]), "[true,false,false,false]");
assert.strictEqual(html(root), "<div><p>The <mark>quick</mark> brown fox</p></div>");

// An empty list is safe and clears earlier marks.
assert.strictEqual(mark([]), "[]");
assert.strictEqual(html(root), "<div><p>The quick brown fox</p></div>");
assert.strictEqual(root.childNodes[0].childNodes.length, 1);

// Calling again replaces the earlier marks instead of adding to them.
mark(["quick"]);
assert.strictEqual(mark(["fox"]), "[true]");
assert.strictEqual(html(root), "<div><p>The quick brown <mark>fox</mark></p></div>");

// Every piece of a quote carries its comment's id and tooltip; marking again replaces both.
const marks = () => json(root.querySelectorAll().map((m) => [m.dataset.id, m.title, m.childNodes.map(html).join("")]));
setContent(el("p", "Some ", el("strong", "bold"), " text here, and another passage"));
const first = "First comment\n↳ A reply";
assert.strictEqual(json(mdex.markQuotes([{ id: "a", quote: "Some bold text", title: first }, { id: "b", quote: "another passage", title: "Second" }])), "[true,true]");
assert.strictEqual(marks(), json([["a", first, "Some "], ["a", first, "bold"], ["a", first, " text"], ["b", "Second", "another passage"]]));
mdex.markQuotes([{ id: "a", quote: "Some bold", title: "Now answered" }]);
assert.strictEqual(marks(), json([["a", "Now answered", "Some "], ["a", "Now answered", "bold"]]));

// Comments are located on the unmarked text in one pass, so any number of them in one text node, nested or overlapping, each keep their own marks.
setContent(el("p", "alpha beta gamma delta epsilon"));
walks = 0;
assert.strictEqual(mark(["alpha", "gamma", "epsilon"]), "[true,true,true]");
assert.strictEqual(walks, 1, "one walk of the page for the whole list");
assert.strictEqual(html(root), "<div><p><mark>alpha</mark> beta <mark>gamma</mark> delta <mark>epsilon</mark></p></div>");
assert.strictEqual(mark(["beta gamma delta", "gamma"]), "[true,true]");
assert.strictEqual(html(root), "<div><p>alpha <mark>beta </mark><mark><mark>gamma</mark></mark><mark> delta</mark> epsilon</p></div>");
assert.strictEqual(marks(), json([["c0", "t0", "beta "], ["c0", "t0", "<mark>gamma</mark>"], ["c1", "t1", "gamma"], ["c0", "t0", " delta"]]));
assert.strictEqual(mark(["alpha beta", "beta gamma"]), "[true,true]");
assert.strictEqual(html(root), "<div><p><mark>alpha </mark><mark><mark>beta</mark></mark><mark> gamma</mark> delta epsilon</p></div>");
assert.strictEqual(mark(["alpha", "alpha", "nope"]), "[true,true,false]");
assert.strictEqual(html(root), "<div><p><mark><mark>alpha</mark></mark> beta gamma delta epsilon</p></div>");
setContent(el("p", "Some ", el("strong", "bold"), " text"), el("p", "Some bold text again"));
assert.strictEqual(mark(["Some bold text", "bold text again", "text again"]), "[true,true,true]");
assert.strictEqual(html(root), "<div><p><mark>Some </mark><strong><mark>bold</mark></strong><mark> text</mark></p><p>Some <mark>bold </mark><mark><mark>text again</mark></mark></p></div>");

// revealQuote scrolls the first piece of a quote to the middle of the window, selects nothing, and says whether it found it.
sandbox.getSelection = () => { throw new Error("revealQuote must not touch the selection"); };
const revealed = (quote, occurrence) => { scrolls.length = 0; const found = mdex.revealQuote(quote, occurrence); return json([found, scrolls]); };
setContent(el("p", "See ", el("a", "the docs"), " now.", el("strong", " Bold")), el("p", "A second paragraph"));
const [see, docs, now] = root.childNodes[0].childNodes.flatMap((n) => (n.tagName ? n.childNodes : [n]));
tops.set(see, 100).set(docs, 500).set(now, 900);
// Window height 600, rect height 20: the piece's middle goes to 300.
assert.strictEqual(revealed("See the docs now."), json([true, [[0, 100 + 10 - 300]]]));
// A quote starting later in the paragraph scrolls to the piece it starts in, whatever it spans.
assert.strictEqual(revealed("the docs now. Bold"), json([true, [[0, 500 + 10 - 300]]]));
assert.strictEqual(revealed("docs\n  now"), json([true, [[0, 500 + 10 - 300]]]));
// A quote that is not there, or is blank, finds nothing and scrolls nowhere.
assert.strictEqual(revealed("not in the page"), json([false, []]));
assert.strictEqual(revealed("  "), json([false, []]));
// It reads the text only: no mark is added.
assert.strictEqual(html(root).includes("<mark>"), false);
// It still finds a quote the page has already marked, since marks split the text nodes.
mark(["the docs now"]);
assert.strictEqual(mdex.revealQuote("See the docs now."), true);
assert.ok(html(root).includes("<mark>"));

// A repeated phrase is marked at the occurrence the comment is on: the 1st by default, the last when the page has fewer, none when it has none.
const repeated = "red fox, red fox and a red fox";
const markAt = (occurrence) => { setContent(el("p", repeated)); return json(mdex.markQuotes([{ id: "a", quote: "red fox", occurrence: occurrence, title: "t" }])); };
assert.strictEqual(markAt(2), "[true]");
assert.strictEqual(html(root), "<div><p>red fox, <mark>red fox</mark> and a red fox</p></div>");
markAt(3);
assert.strictEqual(html(root), "<div><p>red fox, red fox and a <mark>red fox</mark></p></div>");
markAt(1);
assert.strictEqual(html(root), "<div><p><mark>red fox</mark>, red fox and a red fox</p></div>");
markAt(undefined);
assert.strictEqual(html(root), "<div><p><mark>red fox</mark>, red fox and a red fox</p></div>", "no occurrence means the first");
assert.strictEqual(markAt(7), "[true]");
assert.strictEqual(html(root), "<div><p>red fox, red fox and a <mark>red fox</mark></p></div>", "an earlier copy was removed, so the last one is marked");
setContent(el("p", "nothing to see"));
assert.strictEqual(json(mdex.markQuotes([{ id: "a", quote: "red fox", occurrence: 2, title: "t" }])), "[false]");
assert.strictEqual(html(root), "<div><p>nothing to see</p></div>");
// A repeated phrase that spans bold is found in the right place too.
setContent(el("p", "the ", el("strong", "red"), " fox, the red fox"));
mdex.markQuotes([{ id: "a", quote: "the red fox", occurrence: 2, title: "t" }]);
assert.strictEqual(html(root), "<div><p>the <strong>red</strong> fox, <mark>the red fox</mark></p></div>");
// Two comments on the same phrase keep their own marks.
setContent(el("p", repeated));
assert.strictEqual(json(mdex.markQuotes([{ id: "a", quote: "red fox", occurrence: 1, title: "A" }, { id: "b", quote: "red fox", occurrence: 2, title: "B" }])), "[true,true]");
assert.strictEqual(marks(), json([["a", "A", "red fox"], ["b", "B", "red fox"]]));
assert.strictEqual(html(root), "<div><p><mark>red fox</mark>, <mark>red fox</mark> and a red fox</p></div>");

// revealQuote scrolls to the same occurrence.
setContent(el("p", "alpha one"), el("p", "alpha two"), el("p", "alpha three"));
const [one, two, three] = root.childNodes.map((p) => p.childNodes[0]);
tops.set(one, 100).set(two, 500).set(three, 900);
assert.strictEqual(revealed("alpha", 2), json([true, [[0, 500 + 10 - 300]]]));
assert.strictEqual(revealed("alpha", 3), json([true, [[0, 900 + 10 - 300]]]));
assert.strictEqual(revealed("alpha"), json([true, [[0, 100 + 10 - 300]]]));
assert.strictEqual(revealed("alpha", 9), json([true, [[0, 900 + 10 - 300]]]), "fewer than asked scrolls to the last");
assert.strictEqual(revealed("beta", 2), json([false, []]));

// reveal (Ctrl+F in the editor) selects the nth case-insensitive occurrence of the search text, scrolls it to 30% of the window, and returns "". Past the last occurrence it takes the last.
// Text split by marks, bold or line breaks counts as one text, so marks change neither what is found nor how many matches come first.
let selection = null;
sandbox.getSelection = () => ({ removeAllRanges() { selection = null; }, addRange(range) { selection = range; } });
const reveals = (needle, n) => {
  selection = null;
  scrolls.length = 0;
  const returned = mdex.reveal(needle, n);
  return json([returned, selection && [selection.node.data, selection.start, selection.endNode.data, selection.end], scrolls]);
};
setContent(el("p", "The Fox, the fox and a FOX"));
const [fox] = root.childNodes[0].childNodes;
tops.set(fox, 700);
assert.strictEqual(reveals("fox", 1), json(["", ["The Fox, the fox and a FOX", 4, "The Fox, the fox and a FOX", 7], [[0, 700 - 180]]]));
assert.strictEqual(reveals("fox", 2), json(["", ["The Fox, the fox and a FOX", 13, "The Fox, the fox and a FOX", 16], [[0, 700 - 180]]]));
assert.strictEqual(reveals("FOX", 3), json(["", ["The Fox, the fox and a FOX", 23, "The Fox, the fox and a FOX", 26], [[0, 700 - 180]]]));
assert.strictEqual(reveals("fox", 9), reveals("fox", 3), "past the last takes the last");
assert.strictEqual(reveals("fox", undefined), reveals("fox", 1));
assert.strictEqual(reveals("not here", 1), json(["", null, []]), "no match changes nothing");
// A match across bold, a link, a mark or a line break.
setContent(el("p", "Some ", el("strong", "bold"), " text here"));
const [some] = root.childNodes[0].childNodes;
tops.set(some, 300);
assert.strictEqual(reveals("some bold TEXT", 1), json(["", ["Some ", 0, " text here", 5], [[0, 300 - 180]]]));
setContent(el("p", "the red fox, the red fox, the red fox"));
mdex.markQuotes([{ id: "a", quote: "red fox", occurrence: 1, title: "t" }]);
const [before, markEl, rest] = root.childNodes[0].childNodes;
const marked = markEl.childNodes.find((n) => n.data);
assert.strictEqual(marked.data, "red fox");
tops.set(before, 100).set(marked, 200).set(rest, 300);
assert.strictEqual(reveals("the red fox", 1), json(["", ["the ", 0, "red fox", 7], [[0, 100 - 180]]]));
assert.strictEqual(reveals("red fox", 1), json(["", ["red fox", 0, "red fox", 7], [[0, 200 - 180]]]));
assert.strictEqual(reveals("red fox", 2), json(["", [", the red fox, the red fox", 6, ", the red fox, the red fox", 13], [[0, 300 - 180]]]), "the 2nd match is the 2nd, with the 1st marked");
assert.strictEqual(reveals("fox, the", 1), json(["", ["red fox", 4, ", the red fox, the red fox", 5], [[0, 200 - 180]]]));
setContent(el("p", "Line one", el("br"), "line two"));
tops.set(root.childNodes[0].childNodes[0], 400);
assert.strictEqual(reveals("one line", 1), json(["", ["Line one", 5, "line two", 4], [[0, 400 - 180]]]));

// The Comment button posts the selected text, whitespace collapsed, to Vala.
const posted = [];
sandbox.webkit = { messageHandlers: { mdex: { postMessage: (m) => posted.push(m) } } };
setContent(el("p", "Pick this passage"));
const inside = root.childNodes[0].childNodes[0];
// Where a boundary point lies in document order: a text offset follows the nodes before it, an element offset sits before the child at that offset.
const position = (node, offset) => {
  const order = [];
  (function walk(n) { order.push(n); n.childNodes.forEach(walk); })(root);
  if (!node.tagName) return order.indexOf(node) * 1e6 + offset;
  let end = node.childNodes[offset];
  if (end) return order.indexOf(end) * 1e6;
  for (end = node; end.childNodes.length;) end = end.childNodes[end.childNodes.length - 1];
  return (order.indexOf(end) + 1) * 1e6;
};
const select = (anchor, quote, collapsed = false, [startContainer, startOffset] = [anchor, 0]) => {
  sandbox.getSelection = () => ({
    isCollapsed: collapsed,
    rangeCount: 1,
    getRangeAt: () => ({
      commonAncestorContainer: anchor,
      startContainer: startContainer,
      startOffset: startOffset,
      // Only the start side of the DOM's comparePoint: -1 when the point is before the range, else 0.
      comparePoint: (n, o) => (position(n, o) < position(startContainer, startOffset) ? -1 : 0),
      getClientRects: () => [{ bottom: 10, right: 20 }],
    }),
    toString: () => quote,
  });
};
select(inside, "  this \n passage ");
commentButton.listeners.click();
assert.strictEqual(posted.length, 1);
assert.strictEqual(json(posted[0]), '{"type":"comment","quote":"this passage","occurrence":1}');

// The message says which occurrence of the quote was selected: the matches that start before the selection, plus one.
const occurrenceOf = (quote, from) => { posted.length = 0; select(from[0], quote, false, from); commentButton.listeners.click(); return posted[0].occurrence; };
setContent(el("p", repeated));
const para = root.childNodes[0].childNodes[0];
assert.strictEqual(occurrenceOf("red fox", [para, 0]), 1);
assert.strictEqual(occurrenceOf("red fox", [para, 9]), 2);
assert.strictEqual(occurrenceOf("red fox", [para, 23]), 3);
// The same when the selection starts inside another element, or at an element boundary, or the text is split by marks, or whitespace differs.
setContent(el("p", "red fox, ", el("em", "red fox"), " and a red fox"));
assert.strictEqual(occurrenceOf("red fox", [root.childNodes[0].childNodes[1].childNodes[0], 0]), 2);
setContent(el("p", "red fox, red fox and a ", el("strong", "red fox")));
assert.strictEqual(occurrenceOf("red fox", [root.childNodes[0], 1]), 3);
setContent(el("p", repeated));
mdex.markQuotes([{ id: "a", quote: "red fox", occurrence: 1, title: "t" }, { id: "b", quote: "red fox", occurrence: 3, title: "t" }]);
const [, comma] = root.childNodes[0].childNodes;
assert.strictEqual(occurrenceOf("red fox", [comma, 2]), 2);
setContent(el("p", "red  fox,\n red fox"));
assert.strictEqual(occurrenceOf("red fox", [root.childNodes[0].childNodes[0], 11]), 2);
// A line break is one character of the page text, so it counts before a selection that comes after it.
setContent(el("p", "aaaa", el("br"), "aa"));
assert.strictEqual(occurrenceOf("a", [root.childNodes[0].childNodes[2], 1]), 6);
assert.strictEqual(occurrenceOf("a", [root.childNodes[0].childNodes[2], 0]), 5);
// A selection that is not in the page text counts as the first.
setContent(el("p", repeated));
assert.strictEqual(occurrenceOf("blue fox", [root.childNodes[0].childNodes[0], 9]), 1);
setContent(el("p", inside));

// The C key does the same, unless a modifier is held, focus is in a field, or nothing is selected.
const keydown = (e) => docListeners.keydown({ key: "c", target: { closest: () => null }, preventDefault() {}, ...e });
keydown({});
assert.strictEqual(posted.length, 2);
keydown({ ctrlKey: true });
keydown({ metaKey: true });
keydown({ altKey: true });
keydown({ key: "x" });
keydown({ target: { closest: () => ({}) } });
assert.strictEqual(posted.length, 2);
select(inside, "this passage", true);
keydown({});
commentButton.listeners.click();
select(text("elsewhere"), "elsewhere");
keydown({});
assert.strictEqual(posted.length, 2);

// The button shows after a selection in the output and hides when it is cleared.
select(inside, "this passage");
docListeners.mouseup({ target: inside });
assert.strictEqual(commentButton.hidden, false);
select(inside, "", true);
docListeners.selectionchange();
assert.strictEqual(commentButton.hidden, true);

// A click on the button ends with a mouseup on it, before the click. Its deferred check must not show the button again once the click has hidden it, or a second click posts the comment twice.
const timers = [];
sandbox.setTimeout = (f) => timers.push(f);
select(inside, "this passage");
posted.length = 0;
docListeners.mouseup({ target: commentButton });
commentButton.listeners.click();
timers.splice(0).forEach((f) => f());
assert.strictEqual(commentButton.hidden, true);
assert.strictEqual(posted.length, 1);
docListeners.mouseup({ target: inside });
timers.splice(0).forEach((f) => f());
assert.strictEqual(commentButton.hidden, false, "a mouseup in the text still shows it");
sandbox.setTimeout = (f) => f();

// Without a message handler (Node, an older build) commenting does nothing.
select(inside, "this passage");
delete sandbox.webkit;
assert.doesNotThrow(() => { commentButton.listeners.click(); keydown({}); });
sandbox.webkit = { messageHandlers: {} };
assert.doesNotThrow(() => { commentButton.listeners.click(); keydown({}); });

console.log("ok");

// A plain click on a highlighted passage asks Vala to open its comment. The end of a text selection, a click elsewhere and a page without the handler do not.
sandbox.webkit = { messageHandlers: { mdex: { postMessage: (m) => posted.push(m) } } };
setContent(el("p", "Plain text, ", el("strong", "highlighted words"), " here"));
mdex.markQuotes([{ id: "c7", quote: "highlighted words", title: "t" }]);
const [highlight] = root.querySelectorAll();
const paragraph = root.childNodes[0];
posted.length = 0;
select(highlight.childNodes[0], "", true);
root.listeners.click({ target: highlight });
assert.strictEqual(json(posted), '[{"type":"open","id":"c7"}]');
select(highlight.childNodes[0], "highlighted");
root.listeners.click({ target: highlight });
select(paragraph, "", true);
root.listeners.click({ target: paragraph });
assert.strictEqual(posted.length, 1);
delete sandbox.webkit;
select(highlight.childNodes[0], "", true);
assert.doesNotThrow(() => root.listeners.click({ target: highlight }));

// markCoverage shows what a plan's criteria cover of a ticket: the quoted text gets a mark that carries the criterion's number and, as its tooltip, its text. Not covered quotes get a muted mark with the reason.
const covered = (items) => json(mdex.markCoverage({ covered: items, gaps: [] }));
const coverageMarks = () => json(root.querySelectorAll("mark.mdex-covered, mark.mdex-gap").map((m) => [m.className, String(m.dataset.n || ""), m.title, m.childNodes.map(html).join("")]));
setContent(el("p", "The tool lists every ", el("strong", "version"), " offered, and more."));
assert.strictEqual(covered([{ n: 2, quote: "lists every version", title: "All versions are listed" }]), '{"missing":[]}');
assert.strictEqual(coverageMarks(), json([
  ["mdex-covered", "2", "All versions are listed", "lists every "],
  ["mdex-covered mdex-badge", "2", "All versions are listed", "version"],
]), "every piece has the number and the tooltip, and the last piece has the badge");

setContent(el("p", "Hello team, please check this."));
assert.strictEqual(json(mdex.markCoverage({ covered: [], gaps: [{ quote: "Hello team", reason: "a greeting" }] })), '{"missing":[]}');
assert.strictEqual(coverageMarks(), json([["mdex-gap", "", "a greeting", "Hello team"]]), "a gap is muted, shows its reason and has no number");

// A quote the ticket does not hold is returned, by criterion number (0 for a Not covered quote), and marks nothing.
setContent(el("p", "Only this text."));
assert.strictEqual(json(mdex.markCoverage({ covered: [{ n: 1, quote: "this text", title: "a" }, { n: 3, quote: "not here", title: "b" }, { n: 4, quote: "  ", title: "c" }], gaps: [{ quote: "gone", reason: "r" }] })),
  '{"missing":[{"n":3,"quote":"not here"},{"n":4,"quote":"  "},{"n":0,"quote":"gone"}]}');
assert.strictEqual(html(root), "<div><p>Only <mark>this text</mark>.</p></div>");

// A plan copies its quotes from the ticket file, so one can hold markdown syntax the page's text does not: code, bold and a link match as their text. A quote that is not found is returned as written.
setContent(el("p", el("code", "viv show <package> --all"), " lists the ", el("strong", "available"), " versions of ", el("a", "the docs"), "."));
assert.strictEqual(covered([{ n: 1, quote: "`viv show <package> --all` lists the **available** versions of [the docs](https://x.example).", title: "a" }]), '{"missing":[]}');
assert.strictEqual(root.querySelectorAll("mark.mdex-covered").map((m) => m.childNodes.map(html).join("")).join("|"), "viv show <package> --all| lists the |available| versions of |the docs|.");
setContent(el("p", "Plain text"));
assert.strictEqual(covered([{ n: 2, quote: "`not` here", title: "a" }]), '{"missing":[{"n":2,"quote":"`not` here"}]}');

// Two criteria that quote the same text each mark it.
setContent(el("p", "alpha beta"));
covered([{ n: 1, quote: "alpha", title: "one" }, { n: 2, quote: "alpha", title: "two" }]);
assert.strictEqual(coverageMarks(), json([["mdex-covered mdex-badge", "1", "one", '<mark>alpha</mark>'], ["mdex-covered mdex-badge", "2", "two", "alpha"]]));

// A paragraph or list item of the description that no mark falls in gets the bar. The description is the ticket body: after the title and its metadata table, up to the ## Comments heading.
const bars = () => json(root.querySelectorAll(".mdex-uncovered").map((e) => e.nodeName + ":" + e.childNodes.filter((c) => !c.tagName).map((c) => c.data).join("")));
setContent(
  el("h1", "A ticket"), el("table", el("tr", el("td", "Ticket"), el("td", "Some metadata"))),
  el("p", "Covered words here."), el("p", "Nobody covers this."),
  el("p", "A greeting."),
  el("pre", el("code", "code is not a paragraph")),
  el("ul", el("li", "covered item"), el("li", "forgotten item"), el("li", "outer item ", el("ul", el("li", "covered inner")))),
  el("blockquote", el("p", "quoted and forgotten")),
  el("h2", "Done when"),
  el("h2", "Comments"), el("p", "Oldest first."), el("p", el("strong", "Someone"), " said something"));
mdex.markCoverage({ covered: [{ n: 1, quote: "Covered words", title: "a" }, { n: 2, quote: "covered item", title: "b" }, { n: 3, quote: "covered inner", title: "c" }], gaps: [{ quote: "A greeting", reason: "r" }] });
assert.strictEqual(bars(), json(["P:Nobody covers this.", "LI:forgotten item", "LI:outer item ", "P:quoted and forgotten"]),
  "a gap mark counts as an answer; the title, table, code, headings and everything after ## Comments are not checked; a list item is checked by its own text, not its nested items'");

// Without the title or table the description starts at the top.
setContent(el("p", "Plain document."));
mdex.markCoverage({ covered: [{ n: 1, quote: "nothing there", title: "a" }], gaps: [] });
assert.strictEqual(bars(), json(["P:Plain document."]));
// A loose list puts its text in paragraphs; the paragraph is the block, not its item.
setContent(el("ul", el("li", el("p", "loose and forgotten")), el("li", el("p", "loose covered"))));
mdex.markCoverage({ covered: [{ n: 1, quote: "loose covered", title: "a" }], gaps: [] });
assert.strictEqual(bars(), json(["P:loose and forgotten"]));
// A block with no text of its own is not a gap in the coverage.
setContent(el("p", el("img")), el("ul", el("li", el("ul", el("li", "only nested")))));
mdex.markCoverage({ covered: [], gaps: [] });
assert.strictEqual(bars(), json(["LI:only nested"]));

// Calling again replaces the earlier marks and bars; without a plan nothing is left of either.
setContent(el("p", "first part"), el("p", "second part"));
mdex.markCoverage({ covered: [{ n: 1, quote: "first", title: "a" }], gaps: [] });
assert.strictEqual(bars(), json(["P:second part"]));
mdex.markCoverage({ covered: [{ n: 1, quote: "second", title: "a" }], gaps: [] });
assert.strictEqual(bars(), json(["P:first part"]));
assert.strictEqual(html(root), "<div><p>first part</p><p><mark>second</mark> part</p></div>");
assert.strictEqual(json(mdex.markCoverage(null)), '{"missing":[]}');
assert.strictEqual(html(root), "<div><p>first part</p><p>second part</p></div>");
assert.strictEqual(bars(), "[]");
assert.strictEqual(root.childNodes[1].childNodes.length, 1);

// Coverage and comments keep their own marks: each call clears only its own, whichever went first.
setContent(el("p", "alpha beta gamma"));
mdex.markCoverage({ covered: [{ n: 1, quote: "beta gamma", title: "criterion" }], gaps: [] });
mdex.markQuotes([{ id: "a", quote: "alpha beta", title: "comment" }]);
const kinds = () => json(root.querySelectorAll().map((m) => m.className.split(" ")[0]));
assert.strictEqual(kinds(), json(["mdex-comment", "mdex-covered", "mdex-comment"]), "a comment goes inside the coverage mark, so its tooltip is the innermost");
mdex.markQuotes([]);
assert.strictEqual(html(root), "<div><p>alpha <mark>beta gamma</mark></p></div>", "clearing the comments leaves the coverage");
mdex.markQuotes([{ id: "a", quote: "alpha beta", title: "comment" }]);
mdex.markCoverage(null);
assert.strictEqual(kinds(), json(["mdex-comment", "mdex-comment"]), "clearing the coverage leaves the comments");
assert.strictEqual(html(root), "<div><p><mark>alpha </mark><mark>beta</mark> gamma</p></div>");

// revealQuote reads a quote copied from the ticket file as markCoverage does, so a click on a criterion in the pane finds its text.
setContent(el("p", el("code", "viv show"), " lists the ", el("strong", "available"), " versions"));
tops.set(root.childNodes[0].childNodes[0].childNodes[0], 700);
assert.strictEqual(revealed("`viv show` lists the **available** versions"), json([true, [[0, 700 + 10 - 300]]]));
assert.strictEqual(revealed("viv show lists"), json([true, [[0, 700 + 10 - 300]]]), "a quote found as written is not read as markdown");
assert.strictEqual(revealed("`not` there"), json([false, []]));

console.log("ok coverage");

// render() gives a <q> with a cite attribute its source as a tooltip, keeps a title the author wrote, and leaves a <q> without cite, or with an empty one, alone.
// The fake innerHTML does not parse, so render() keeps the nodes the test built.
const quote = (attrs, body) => Object.assign(el("q", body), { attrs });
setContent(el("p", quote({ cite: "391.ticket.md" }, "cited"), " ", quote({}, "plain"), " ", quote({ cite: "a.md", title: "mine" }, "titled"), " ", quote({ cite: "" }, "empty")));
mdex.render("");
assert.strictEqual(json(root.querySelectorAll("q").map((q) => q.getAttribute("title"))), json(["Quoted from 391.ticket.md", null, "mine", null]));

console.log("ok quote titles");
