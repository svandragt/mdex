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

const run = (id, md) => sandbox.window.mdex.run(id, md);

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

console.log("ok");
