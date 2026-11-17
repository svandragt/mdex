// Checks that the preview marks only the plan's quotes of the ticket, and clears the marks when there is no plan.
//
// A <q> that cites another file is not text of the ticket: it must not be
// looked up there, so it marks nothing and is not reported as missing, even
// when the ticket holds the same words.
//
// It builds a WebView, so it needs a display and skips (exit 77) without one.

private int failures = 0;

private void check (string name, bool ok) {
    print ("%s %s\n", ok ? "ok  " : "FAIL", name);
    if (!ok) {
        failures++;
    }
}

private const string PLAN = """## Criteria
1. Lists — <q cite="391.ticket.md">lists every version</q>
2. Greets — <q cite="other.md">a greeting</q>
3. Elsewhere — <q cite="other.md">not in the ticket</q>
4. Path — <q cite="docs/391.ticket.md">and a</q>

Not covered: <q cite="other.md">tool</q> — elsewhere
""";

/** The marks the page holds, as "<criterion number>:<text>" in a JSON list. */
private async string marks_of (Mdex.Preview preview) {
    try {
        var result = yield preview.call_async_javascript_function (
            "return JSON.stringify([...document.querySelectorAll('mark.mdex-covered, mark.mdex-gap')].map((m) => m.dataset.n + ':' + m.textContent));",
            -1, null, null, null, null);
        return result.to_string ();
    } catch (GLib.Error e) {
        return "script failed: %s".printf (e.message);
    }
}

private async void check_page (Mdex.Preview preview) {
    try {
        yield preview.load_shell ();
    } catch (GLib.Error e) {
        check ("the shell loads: %s".printf (e.message), false);
        return;
    }
    yield preview.render ("# Ticket\n\nThe tool lists every version and a greeting.\n");

    var missing = yield preview.mark_coverage (Mdex.Coverage.parse (PLAN), "391.ticket.md");
    check ("the page answers", missing != null);
    check ("a quote of another file is not reported missing", missing != null && missing.is_empty);

    check ("only the ticket's quotes are marked", (yield marks_of (preview)) == "[\"1:lists every version\",\"4:and a\"]");

    // No plan, which is what the window passes when the plan quotes nothing of the ticket, takes the marks away.
    var cleared = yield preview.mark_coverage (null, "391.ticket.md");
    check ("no plan clears the marks", cleared != null && cleared.is_empty && (yield marks_of (preview)) == "[]");
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
