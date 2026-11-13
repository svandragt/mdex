// Checks the banner that stays above the editor when the open file changes on
// disk while the editor holds unsaved edits. A toast timed out before a typist
// saw it, so the banner stays until the user picks Reload or Keep mine.
//
// It builds widgets, so it needs a display and skips (exit 77) without one.

private int failures = 0;

private void check (string name, bool ok) {
    print ("%s %s\n", ok ? "ok  " : "FAIL", name);
    if (!ok) {
        failures++;
    }
}

private Gtk.Button? button (Gtk.Widget banner, string label) {
    for (var child = banner.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var b = child as Gtk.Button;
        if (b != null && b.label == label) {
            return b;
        }
    }
    return null;
}

private bool has_label (Gtk.Widget banner, string text) {
    for (var child = banner.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var l = child as Gtk.Label;
        if (l != null && l.label == text) {
            return true;
        }
    }
    return false;
}

public static int main (string[] args) {
    if (!Gtk.init_check ()) {
        print ("skip: no display\n");
        return 77;
    }

    var editor = new Mdex.Editor ();
    string? requested = null;
    int requests = 0;
    editor.reload_requested.connect ((text) => {
        requested = text;
        requests++;
    });

    check ("no banner until a change is offered", !editor.reload_banner.visible);

    editor.offer_reload ("from disk");
    check ("offering shows the banner", editor.reload_banner.visible);
    check ("the banner says the file changed", has_label (editor.reload_banner, "The file changed on disk"));
    check ("the banner has Reload and Keep mine", button (editor.reload_banner, "Reload") != null && button (editor.reload_banner, "Keep mine") != null);
    check ("offering does not reload by itself", requests == 0);

    // The read-only banner and this one are independent.
    editor.lock_until_click ();
    check ("both banners show at once", editor.banner.visible && editor.reload_banner.visible);
    editor.unlock ();
    check ("lifting the lock leaves the reload banner", editor.reload_banner.visible);
    editor.lock_until_click ();
    button (editor.reload_banner, "Keep mine").clicked ();
    check ("Keep mine leaves the read-only banner", editor.banner.visible);
    editor.unlock ();

    editor.offer_reload ("from disk");
    button (editor.reload_banner, "Keep mine").clicked ();
    check ("Keep mine hides the banner", !editor.reload_banner.visible);
    check ("Keep mine asks for nothing", requests == 0);

    // A newer change replaces the pending text; there is one banner.
    editor.offer_reload ("first change");
    editor.offer_reload ("second change");
    check ("a second offer keeps one banner showing", editor.reload_banner.visible);
    button (editor.reload_banner, "Reload").clicked ();
    check ("Reload hands over the newest text", requests == 1 && requested == "second change");
    check ("Reload hides the banner", !editor.reload_banner.visible);

    // Withdrawing is what a document switch or a clean later change does.
    editor.offer_reload ("stale");
    editor.withdraw_reload_offer ();
    check ("withdrawing hides the banner", !editor.reload_banner.visible);
    check ("withdrawing asks for nothing", requests == 1);
    editor.withdraw_reload_offer ();
    check ("withdrawing with no banner is harmless", !editor.reload_banner.visible);

    return failures == 0 ? 0 : 1;
}
