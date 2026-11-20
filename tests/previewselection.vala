// Checks that selected_source returns the Markdown of every block a selection in the rendered page touches.
//
// It builds a WebView, so it needs a display and skips (exit 77) without one.

private int failures = 0;

private void check (string name, bool ok) {
    print ("%s %s\n", ok ? "ok  " : "FAIL", name);
    if (!ok) {
        failures++;
    }
}

// Selects the rendered text from the first occurrence of from to the end of the first occurrence of to.
private async void select_between (Mdex.Preview preview, string from, string to) {
    var b = new GLib.VariantBuilder (new GLib.VariantType ("a{sv}"));
    b.add ("{sv}", "from", new GLib.Variant.string (from));
    b.add ("{sv}", "to", new GLib.Variant.string (to));
    const string JS = """
        const walker = document.createTreeWalker(document.getElementById("output"), NodeFilter.SHOW_TEXT);
        const range = document.createRange();
        let started = false;
        for (let n = walker.nextNode(); n; n = walker.nextNode()) {
          const i = n.data.indexOf(from);
          if (!started && i >= 0) { range.setStart(n, i); started = true; }
          if (!started) continue;
          const j = n.data.indexOf(to);
          if (j >= 0) { range.setEnd(n, j + to.length); break; }
        }
        const s = window.getSelection();
        s.removeAllRanges();
        s.addRange(range);
    """;
    try {
        yield preview.call_async_javascript_function (JS, -1, b.end (), null, null, null);
    } catch (GLib.Error e) {
        check ("the selection is made: %s".printf (e.message), false);
    }
}

private async void run_js (Mdex.Preview preview, string js) {
    try {
        yield preview.call_async_javascript_function (js, -1, null, null, null, null);
    } catch (GLib.Error e) {
        check ("the script runs: %s".printf (e.message), false);
    }
}

private async void clear_selection (Mdex.Preview preview) {
    try {
        yield preview.call_async_javascript_function (
            "window.getSelection().removeAllRanges();", -1, null, null, null, null);
    } catch (GLib.Error e) {
        check ("the selection is cleared: %s".printf (e.message), false);
    }
}

private async void check_page (Mdex.Preview preview) {
    try {
        yield preview.load_shell ();
    } catch (GLib.Error e) {
        check ("the shell loads: %s".printf (e.message), false);
        return;
    }
    yield preview.render ("# Title\n\nFirst **bold** para.\n\n- one\n- two [link][x]\n\nLast para.\n\n[x]: https://example.com\n");

    string? none = yield preview.selected_source ();
    check ("no selection gives null", none == null);

    yield select_between (preview, "bold", "on");
    string? two = yield preview.selected_source ();
    check ("a selection over two blocks gives both blocks' Markdown, got %s".printf (two ?? "null"),
        two == "First **bold** para.\n\n- one\n- two [link][x]\n\n[x]: https://example.com");

    yield select_between (preview, "irs", "irs");
    string? part = yield preview.selected_source ();
    check ("part of one paragraph gives the whole paragraph, got %s".printf (part ?? "null"),
        part == "First **bold** para.");

    yield select_between (preview, "link", "link");
    string? linked = yield preview.selected_source ();
    check ("a selection keeps the definitions of its reference links, got %s".printf (linked ?? "null"),
        linked == "- one\n- two [link][x]\n\n[x]: https://example.com");

    yield preview.render ("Intro.\n\n<div>a</div>\n<div>b</div>\n\n<!-- note --><p>c</p>\n");
    yield select_between (preview, "b", "b");
    string? html = yield preview.selected_source ();
    check ("a selection in the second element of raw HTML gives that HTML, got %s".printf (html ?? "null"),
        html == "<div>a</div>\n<div>b</div>");
    yield select_between (preview, "c", "c");
    string? commented = yield preview.selected_source ();
    check ("raw HTML that opens with a comment maps to its source, got %s".printf (commented ?? "null"),
        commented == "<!-- note --><p>c</p>");

    yield preview.render ("Before.\n\n![logo](a.png) caption\n");
    yield run_js (preview, """
        const range = document.createRange();
        range.setStart(document.getElementById("output").querySelector("p").firstChild, 0);
        range.setEndAfter(document.querySelector("img"));
        window.getSelection().removeAllRanges();
        window.getSelection().addRange(range);
    """);
    string? image = yield preview.selected_source ();
    check ("a selection that ends after an image includes the image's paragraph, got %s".printf (image ?? "null"),
        image == "Before.\n\n![logo](a.png) caption");

    yield preview.render ("See [the\nspec][Big  Spec] and [odd].\n\n[big spec]: https://x.test\n[odd]: <https://x.test/a b> \"say \\\"hi\\\"\"\n");
    yield select_between (preview, "See", "See");
    string? wrapped = yield preview.selected_source ();
    check ("a wrapped label keeps its definition and an odd destination stays valid, got %s".printf (wrapped ?? "null"),
        wrapped == "See [the\nspec][Big  Spec] and [odd].\n\n[big spec]: https://x.test\n[odd]: <https://x.test/a b> \"say \\\"hi\\\"\"");

    yield preview.render ("Intro.\n\n<!-- was <b>old</b> --><p>c</p>\n");
    yield select_between (preview, "c", "c");
    string? tagged = yield preview.selected_source ();
    check ("a tag inside a leading comment is skipped, got %s".printf (tagged ?? "null"),
        tagged == "<!-- was <b>old</b> --><p>c</p>");

    yield clear_selection (preview);
    string? cleared = yield preview.selected_source ();
    check ("a cleared selection gives null", cleared == null);
}

public static int main (string[] args) {
    if (!Gtk.init_check ()) {
        print ("skip: no display\n");
        return 77;
    }

    var loop = new GLib.MainLoop ();
    var preview = new Mdex.Preview ();
    var window = new Gtk.Window ();
    window.set_default_size (800, 600);
    window.child = preview;
    window.present ();
    check_page.begin (preview, (obj, res) => {
        check_page.end (res);
        loop.quit ();
    });
    loop.run ();
    return failures == 0 ? 0 : 1;
}
