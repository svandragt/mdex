// Checks that the preview does not run script a document carries.
//
// An <img onerror> in the Markdown reaches the page through innerHTML, where
// only the page's Content-Security-Policy stops it. The same document holds a
// <br> in a table cell, which must still render, and every read goes through
// call_async_javascript_function, so the test also shows Vala can still call
// into the page under the policy. The Comment button is placed by writing its
// style from script, which the policy must still allow. A document's meta
// refresh must not replace the shell, which is what carries the policy.
//
// It builds a WebView, so it needs a display and skips (exit 77) without one.

private int failures = 0;

private void check (string name, bool ok) {
    print ("%s %s\n", ok ? "ok  " : "FAIL", name);
    if (!ok) {
        failures++;
    }
}

private async void wait_ms (uint ms) {
    GLib.Timeout.add (ms, () => {
        wait_ms.callback ();
        return GLib.Source.REMOVE;
    });
    yield;
}

/** The page's answer to a script that returns a string. */
private async string ask (Mdex.Preview preview, string js) {
    try {
        var result = yield preview.call_async_javascript_function (js, -1, null, null, null, null);
        return result.to_string ();
    } catch (GLib.Error e) {
        return "error: %s".printf (e.message);
    }
}

private async void check_page (Mdex.Preview preview) {
    try {
        yield preview.load_shell ();
    } catch (GLib.Error e) {
        check ("the shell loads: %s".printf (e.message), false);
        return;
    }
    string shell_uri = preview.get_uri ();

    yield preview.render ("<img src=x onerror=\"window.pwned=1\">\n\n| a |\n| - |\n| one<br>two |\n");

    // The image fails to load at once; the error event follows, so give it time before reading.
    for (int i = 0; i < 100 && (yield ask (preview, "return String(document.images[0]?.complete);")) != "true"; i++) {
        yield wait_ms (50);
    }
    yield wait_ms (300);

    check ("an inline onerror handler does not run", (yield ask (preview, "return typeof window.pwned;")) == "undefined");
    check ("a <br> in a table cell still renders", (yield ask (preview, "return String(document.querySelector('td br') !== null);")) == "true");

    yield ask (preview, "getSelection().selectAllChildren(document.getElementById('output')); document.dispatchEvent(new MouseEvent('mouseup', { bubbles: true })); return '';");
    // The page shows the button from a timeout after the mouseup, so poll for it as for the image.
    for (int i = 0; i < 100 && (yield ask (preview, BUTTON_PLACED)) != "true"; i++) {
        yield wait_ms (50);
    }
    check ("the Comment button is shown and placed by script", (yield ask (preview, BUTTON_PLACED)) == "true");

    // A meta refresh navigates without a click and would replace the shell with a page that has no policy.
    // These go last, because without the fix a refresh ends the page. Neither needs the network.
    yield check_meta_refresh (preview, shell_uri, "about:blank?x");
    yield check_meta_refresh (preview, shell_uri, "about:blank");
}

private const string BUTTON_PLACED =
    "const b = document.getElementById('mdex-comment'); return String(!b.hidden && b.style.top !== '' && b.style.left !== '');";

/** Renders a meta refresh to target. The wait is fixed because nothing is expected to happen. */
private async void check_meta_refresh (Mdex.Preview preview, string shell_uri, string target) {
    yield preview.render ("<meta http-equiv=\"refresh\" content=\"0;url=%s\">".printf (target));
    yield wait_ms (1500);
    check ("a meta refresh to %s does not leave the shell".printf (target), preview.get_uri () == shell_uri);
    check ("the page still has its bridge after a meta refresh to %s".printf (target), (yield ask (preview, "return typeof window.mdex;")) == "object");
    yield preview.render ("# after");
    check ("a render after a meta refresh to %s still works".printf (target), (yield ask (preview, "return document.querySelector('h1')?.textContent ?? 'none';")) == "after");
}

public static int main (string[] args) {
    if (!Gtk.init_check ()) {
        print ("skip: no display\n");
        return 77;
    }

    var loop = new GLib.MainLoop ();
    var preview = new Mdex.Preview ();
    // Selected text is read through the page's layout, which an unshown view does not have.
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
