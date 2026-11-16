// Checks that Open plan in a ticket window asks for the plan in a window of its own.
//
// The window that shows the ticket keeps its document, so Open plan must not take the path the
// Open dialog takes, which replaces the document. Starting the window, or bringing forward one that
// already shows the plan, is the Application's job and has no test: it needs a second process.
//
// It builds a MainWindow, so it needs a display and skips (exit 77) without one.

private int failures = 0;

private void check (string name, bool ok) {
    print ("%s %s\n", ok ? "ok  " : "FAIL", name);
    if (!ok) {
        failures++;
    }
}

private void remove_tree (string path) {
    if (FileUtils.test (path, FileTest.IS_DIR)) {
        try {
            var dir = Dir.open (path);
            string? name;
            while ((name = dir.read_name ()) != null) {
                remove_tree (Path.build_filename (path, name));
            }
        } catch (GLib.FileError e) {
            // Already gone.
        }
    }
    FileUtils.remove (path);
}

private Gtk.Button? button (Gtk.Widget where, string label) {
    var b = where as Gtk.Button;
    if (b != null && b.label == label) {
        return b;
    }
    for (var child = where.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var found = button (child, label);
        if (found != null) {
            return found;
        }
    }
    return null;
}

public static int main (string[] args) {
    string dir;
    try {
        dir = DirUtils.make_tmp ("mdex-mainwindow-XXXXXX");
    } catch (GLib.Error e) {
        print ("FAIL no temp directory: %s\n", e.message);
        return 1;
    }
    // The window keeps comments under the cache directory, so point that at the temp one.
    Environment.set_variable ("XDG_CACHE_HOME", dir, true);
    if (!Gtk.init_check ()) {
        print ("skip: no display\n");
        return 77;
    }

    string ticket = Path.build_filename (dir, "391.ticket.md");
    string plan = Path.build_filename (dir, "391.md");
    var window = new Mdex.MainWindow (new Gtk.Application ("com.github.svandragt.mdex.test", GLib.ApplicationFlags.NON_UNIQUE));
    GLib.File? in_new_window = null;
    int replaced = 0;
    window.open_requested.connect (() => replaced++);
    window.open_in_new_window_requested.connect ((file) => in_new_window = file);

    // With no document, or a document that is not a ticket, there is no plan to ask for.
    window.set_document (null);
    var open = button (window, "Open plan");
    check ("the window has an Open plan button", open != null);
    open.clicked ();
    check ("a document with no plan asks for nothing", in_new_window == null && replaced == 0);

    window.set_document (ticket);
    open.clicked ();
    check ("Open plan asks for the plan beside the ticket in a new window", in_new_window != null && in_new_window.get_path () == plan);
    check ("Open plan does not replace this window's document", replaced == 0);

    remove_tree (dir);
    return failures == 0 ? 0 : 1;
}
