// Loads the real shell bridge and exporters in Node and checks their output.
// The page's <script> blocks are extracted rather than duplicated, so this
// tests what ships.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const web = path.join(__dirname, "..", "data", "web");
const read = (p) => fs.readFileSync(path.join(web, p), "utf8");

const bridge = read("shell.html").match(/<script>\s*\(function \(\) \{[\s\S]*?<\/script>/)[0]
  .replace(/^<script>|<\/script>$/g, "");

const sandbox = {
  document: {
    getElementById: () => ({ set innerHTML(_) {} }),
    documentElement: { setAttribute() {} },
  },
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

console.log("ok");
