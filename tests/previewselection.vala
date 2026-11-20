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
        two == "First **bold** para.\n\n- one\n- two [link][x]");

    yield select_between (preview, "irs", "irs");
    string? part = yield preview.selected_source ();
    check ("part of one paragraph gives the whole paragraph, got %s".printf (part ?? "null"),
        part == "First **bold** para.");

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
