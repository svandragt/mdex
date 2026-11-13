// Checks the comments pane against a sidecar in a temp directory.
//
// It builds widgets, so it needs a display and skips (exit 77) without one.
// Rows are found by their widget name, which is the comment id.

private int failures = 0;

private void check (string name, bool ok) {
    if (ok) {
        print ("ok   %s\n", name);
        return;
    }
    failures++;
    print ("FAIL %s\n", name);
}

private void spit (string path, string text) {
    try {
        FileUtils.set_contents (path, text);
    } catch (GLib.FileError e) {
        error ("cannot write %s: %s", path, e.message);
    }
}

/** Every widget under root, in tree order. A collapsed expander does not parent its child, so that is walked too. */
private void walk (Gtk.Widget root, ref Gee.ArrayList<Gtk.Widget> found) {
    for (var child = root.get_first_child (); child != null; child = child.get_next_sibling ()) {
        found.add (child);
        walk (child, ref found);
    }
    var expander = root as Gtk.Expander;
    if (expander != null && expander.child != null && expander.child.get_parent () == null) {
        found.add (expander.child);
        walk (expander.child, ref found);
    }
}

private bool inside (Gtk.Expander? expander, Gtk.Widget? w) {
    return expander != null && w != null && w in all (expander);
}

private Gee.ArrayList<Gtk.Widget> all (Gtk.Widget root) {
    var found = new Gee.ArrayList<Gtk.Widget> ();
    walk (root, ref found);
    return found;
}

private Gtk.Widget? row (Gtk.Widget pane, string id) {
    foreach (var w in all (pane)) {
        if (w.name == id) {
            return w;
        }
    }
    return null;
}

private Gtk.Button? button (Gtk.Widget? where, string label) {
    if (where == null) {
        return null;
    }
    foreach (var w in all (where)) {
        var b = w as Gtk.Button;
        if (b != null && b.label == label) {
            return b;
        }
    }
    return null;
}

private bool has_label (Gtk.Widget? where, string text) {
    if (where == null) {
        return false;
    }
    foreach (var w in all (where)) {
        var l = w as Gtk.Label;
        if (l != null && l.label.contains (text)) {
            return true;
        }
    }
    return false;
}

/** Ids of the rows in the order they appear. */
private string order (Gtk.Widget pane, string[] ids) {
    var seen = new string[0];
    foreach (var w in all (pane)) {
        if (w.name in ids) {
            seen += w.name;
        }
    }
    return string.joinv (",", seen);
}

/** Presses the row the way a mouse click does. */
private void click (Gtk.Widget? row) {
    var controllers = row.observe_controllers ();
    for (uint i = 0; i < controllers.get_n_items (); i++) {
        var gesture = controllers.get_item (i) as Gtk.GestureClick;
        if (gesture != null) {
            gesture.pressed (1, 0, 0);
        }
    }
}

private string status_of (string file, string id) {
    foreach (var c in new Mdex.Comments (file).load ()) {
        if (c.id == id) {
            return c.status;
        }
    }
    return "";
}

private const string SIDECAR = """[
  {"id": "c1", "quote": "first quote", "body": "first body", "status": "resolved", "reply": null, "created": "x"},
  {"id": "c2", "quote": "second quote", "occurrence": 2, "body": "second body", "status": "open", "reply": null, "created": "x"},
  {"id": "c3", "quote": "third quote", "body": "third body", "status": "open", "reply": "third reply", "created": "x"},
  {"id": "c4", "quote": "fourth quote", "body": "fourth body", "status": "dismissed", "reply": null, "created": "x"},
  {"id": "c5", "quote": "old quote", "occurrence": 3, "body": "fifth body", "status": "open", "reply": "fifth reply", "change_quote": "new phrase", "created": "x"}
]""";

public static int main (string[] args) {
    if (!Gtk.init_check ()) {
        print ("skip: no display\n");
        return 77;
    }

    string dir;
    try {
        dir = DirUtils.make_tmp ("mdex-pane-XXXXXX");
    } catch (GLib.FileError e) {
        error ("no temp dir: %s", e.message);
    }
    string file = Path.build_filename (dir, "doc.json");
    var ids = new string[] { "c1", "c2", "c3", "c4" };

    var pane = new Mdex.CommentsPane ();
    // Focus lives in a window, so the pane needs one; it is never shown.
    var window = new Gtk.Window () {
        child = pane,
    };
    int changes = 0;
    pane.changed.connect (() => changes++);

    // No file, a missing file and an empty list all show the one empty line.
    pane.use (null);
    check ("no document shows the empty state", has_label (pane, "No comments. Select text in the preview and press C."));
    pane.use (file);
    check ("missing sidecar shows the empty state", has_label (pane, "No comments. Select text in the preview and press C."));

    spit (file, SIDECAR);
    pane.refresh ();
    check ("comments hide the empty state", !has_label (pane, "No comments."));
    check ("open first, then resolved and dismissed in file order", order (pane, ids) == "c2,c3,c1,c4");

    // Resolved and dismissed sit inside one collapsed expander.
    Gtk.Expander? expander = null;
    foreach (var w in all (pane)) {
        if (w is Gtk.Expander) {
            check ("only one expander", expander == null);
            expander = (Gtk.Expander) w;
        }
    }
    check ("the expander is collapsed", expander != null && !expander.expanded);
    check ("resolved and dismissed are inside it", inside (expander, row (pane, "c1")) && inside (expander, row (pane, "c4")));
    check ("open comments are outside it", !inside (expander, row (pane, "c2")) && !inside (expander, row (pane, "c3")));

    // Each row shows its quote, body and reply.
    check ("row shows quote and body", has_label (row (pane, "c2"), "second quote") && has_label (row (pane, "c2"), "second body"));
    check ("row shows the reply", has_label (row (pane, "c3"), "third reply"));
    check ("row without a reply shows none", !has_label (row (pane, "c2"), "reply"));

    // Buttons by state.
    check ("open and unanswered has Resolve, Dismiss and Edit",
        button (row (pane, "c2"), "Resolve") != null && button (row (pane, "c2"), "Dismiss") != null && button (row (pane, "c2"), "Edit") != null);
    check ("open and answered has Resolve and Dismiss but no Edit",
        button (row (pane, "c3"), "Resolve") != null && button (row (pane, "c3"), "Dismiss") != null && button (row (pane, "c3"), "Edit") == null);
    check ("resolved has no buttons", button (row (pane, "c1"), "Resolve") == null && button (row (pane, "c1"), "Dismiss") == null && button (row (pane, "c1"), "Edit") == null);
    check ("dismissed has no buttons", button (row (pane, "c4"), "Resolve") == null && button (row (pane, "c4"), "Edit") == null);

    // Text changed shows on open comments whose quote was not found.
    check ("no Text changed without a mark result", !has_label (pane, "Text changed"));
    var missing = new Gee.HashSet<string> ();
    missing.add ("second quote");
    missing.add ("first quote");
    pane.refresh (missing);
    check ("an open comment with a missing quote says Text changed", has_label (row (pane, "c2"), "Text changed"));
    check ("an open comment with a found quote does not", !has_label (row (pane, "c3"), "Text changed"));
    check ("a resolved comment never does", !has_label (row (pane, "c1"), "Text changed"));

    // A session's change_quote says where the text went, so it decides "Text changed"; the row still shows the original quote.
    check ("a row shows the original quote, not the change_quote", has_label (row (pane, "c5"), "old quote") && !has_label (row (pane, "c5"), "new phrase"));
    var moved = new Gee.HashSet<string> ();
    moved.add ("old quote");
    pane.refresh (moved);
    check ("a gone quote whose change_quote is in the text is not flagged", !has_label (row (pane, "c5"), "Text changed"));
    moved.add ("new phrase");
    pane.refresh (moved);
    check ("a change_quote that is gone is flagged", has_label (row (pane, "c5"), "Text changed"));
    pane.refresh (missing);

    // Clicking a row sends the quote to look for, which is the change_quote when there is one, and which occurrence of it.
    string? activated = null;
    int activated_occurrence = 0;
    pane.quote_activated.connect ((quote, occurrence) => {
        activated = quote;
        activated_occurrence = occurrence;
    });
    click (row (pane, "c5"));
    check ("a row with a change_quote activates it", activated == "new phrase");
    check ("a change_quote is looked up from the first occurrence", activated_occurrence == 1);
    click (row (pane, "c2"));
    check ("a row without one activates its quote", activated == "second quote");
    check ("a row activates the occurrence its comment is on", activated_occurrence == 2);
    click (row (pane, "c3"));
    check ("a comment without an occurrence activates the first", activated_occurrence == 1);

    // select puts focus on the row with that id, and an id with no row leaves it where it was.
    pane.select ("c3");
    check ("select focuses the row", window.focus_widget == row (pane, "c3"));
    pane.select ("c2");
    check ("select moves focus to another row", window.focus_widget == row (pane, "c2"));
    pane.select ("nope");
    check ("an unknown id leaves focus alone", window.focus_widget == row (pane, "c2"));

    // A refresh with nothing new keeps the rows, so an open expander or an edit in progress survives.
    var before = row (pane, "c2");
    pane.refresh (missing);
    check ("an unchanged refresh keeps the rows", row (pane, "c2") == before);

    // Resolve writes the file.
    int seen = changes;
    button (row (pane, "c2"), "Resolve").clicked ();
    check ("Resolve updates the file", status_of (file, "c2") == "resolved");
    check ("Resolve tells the window", changes == seen + 1);
    check ("a resolved comment moves into the expander", inside (expander_of (pane), row (pane, "c2")));

    // Dismiss, and Edit through its entry.
    button (row (pane, "c3"), "Dismiss").clicked ();
    check ("Dismiss updates the file", status_of (file, "c3") == "dismissed");

    spit (file, SIDECAR);
    pane.refresh ();
    button (row (pane, "c2"), "Edit").clicked ();
    Gtk.Entry? entry = null;
    foreach (var w in all (row (pane, "c2"))) {
        if (w is Gtk.Entry) {
            entry = (Gtk.Entry) w;
        }
    }
    check ("Edit opens an entry holding the body", entry != null && entry.text == "second body");
    if (entry != null) {
        entry.text = "better body";
        entry.activate ();
    }
    bool edited = false;
    foreach (var c in new Mdex.Comments (file).load ()) {
        edited = edited || (c.id == "c2" && c.body == "better body");
    }
    check ("Enter in the entry saves the new body", edited);

    // show_comments displays what the window just read instead of reading the sidecar again, so one read serves the marks and the pane. null is a file that cannot be read.
    spit (file, SIDECAR);
    var handed = new Gee.ArrayList<Mdex.Comment> ();
    var given = new Mdex.Comment ();
    given.id = "handed";
    given.quote = "handed quote";
    given.body = "handed body";
    handed.add (given);
    pane.show_comments (handed);
    check ("show_comments displays the comments it is given, not the file's", row (pane, "handed") != null && row (pane, "c2") == null);
    pane.show_comments (new Gee.ArrayList<Mdex.Comment> ());
    check ("show_comments of no comments shows the empty state", has_label (pane, "No comments.") && row (pane, "handed") == null);
    pane.show_comments (null);
    check ("show_comments of null says the file cannot be read", has_label (pane, "cannot be read") && has_label (pane, file));
    pane.refresh ();
    check ("refresh reads the file again", row (pane, "c2") != null && !has_label (pane, "cannot be read"));

    // An invalid sidecar is shown as one line with its path and left alone.
    spit (file, "this is not json");
    pane.refresh ();
    check ("invalid JSON says the file cannot be read", has_label (pane, "cannot be read") && has_label (pane, file));
    check ("invalid JSON shows no empty state or rows", !has_label (pane, "No comments.") && row (pane, "c2") == null);
    check ("invalid JSON is left untouched", is_text (file, "this is not json"));

    FileUtils.remove (file);
    FileUtils.remove (dir);
    return failures == 0 ? 0 : 1;
}

private Gtk.Expander? expander_of (Gtk.Widget pane) {
    foreach (var w in all (pane)) {
        if (w is Gtk.Expander) {
            return (Gtk.Expander) w;
        }
    }
    return null;
}

private bool is_text (string path, string want) {
    string text = "";
    try {
        FileUtils.get_contents (path, out text);
    } catch (GLib.FileError e) {
        return false;
    }
    return text == want;
}
