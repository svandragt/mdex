// Checks that Open plan in a ticket window asks for the plan in a window of its own.
//
// The window that shows the ticket keeps its document, so Open plan must not take the path the
// Open dialog takes, which replaces the document. Starting the window, or bringing forward one that
// already shows the plan, is the Application's job and has no test: it needs a second process.
//
// It also checks that a plan which quotes nothing of the ticket draws no bar beside the ticket's paragraphs,
// since every paragraph would then read as left out. The bars are drawn by the page, so the check loads it.
//
// It checks the Export menu ends with Export to PDF… even when the exporter list is broken, the name the save dialog
// offers for it, and that a PDF export snapshots the text like the other exports.
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

private GLib.MenuModel? export_menu_of (Gtk.Widget where) {
    var b = where as Gtk.MenuButton;
    if (b != null && b.label == "Export") {
        return b.menu_model;
    }
    for (var child = where.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var found = export_menu_of (child);
        if (found != null) {
            return found;
        }
    }
    return null;
}

private Mdex.Preview? preview_of (Gtk.Widget where) {
    var preview = where as Mdex.Preview;
    for (var child = where.get_first_child (); preview == null && child != null; child = child.get_next_sibling ()) {
        preview = preview_of (child);
    }
    return preview;
}

private Mdex.Editor? editor_of (Gtk.Widget where) {
    var editor = where as Mdex.Editor;
    for (var child = where.get_first_child (); editor == null && child != null; child = child.get_next_sibling ()) {
        editor = editor_of (child);
    }
    return editor;
}

private async void wait_ms (uint ms) {
    GLib.Timeout.add (ms, () => {
        wait_ms.callback ();
        return GLib.Source.REMOVE;
    });
    yield;
}

/** The paragraphs of the page that carry the bar, polled until the page says want or the time is up. */
private async int bars (Mdex.Preview preview, int want) {
    int found = -1;
    for (int i = 0; i < 100 && found != want; i++) {
        yield wait_ms (50);
        try {
            var result = yield preview.call_async_javascript_function (
                "return document.querySelectorAll('.mdex-uncovered').length;", -1, null, null, null, null);
            found = (int) result.to_int32 ();
        } catch (GLib.Error e) {
            found = -1;
        }
    }
    return found;
}

private async void check_bars (Mdex.MainWindow window, string ticket, string plan) {
    var preview = preview_of (window);
    check ("the window has a preview", preview != null);
    string text = "# Ticket\n\nThe tool lists versions.\n\nNobody covers this.\n";
    try {
        FileUtils.set_contents (ticket, text);
        FileUtils.set_contents (plan, "## Criteria\n1. Lists — <q cite=\"391.ticket.md\">The tool lists versions.</q>\n");
    } catch (GLib.FileError e) {
        check ("the files are written: %s".printf (e.message), false);
        return;
    }
    window.set_document (ticket);
    window.set_text (text);
    check ("a plan that quotes the ticket bars the paragraph it leaves out", (yield bars (preview, 1)) == 1);

    // Nothing here is the ticket's: an added criterion and a quote of another file.
    try {
        FileUtils.set_contents (plan, "## Criteria\n1. Lists\n2. Other — <q cite=\"other.md\">The tool lists versions.</q>\n");
    } catch (GLib.FileError e) {
        check ("the plan is rewritten: %s".printf (e.message), false);
        return;
    }
    window.set_document (ticket);
    check ("a plan that quotes nothing of the ticket bars nothing", (yield bars (preview, 0)) == 0);
}

private async void check_menu (Mdex.MainWindow window) {
    yield window.build_export_menu ();
    var menu = export_menu_of (window);
    check ("the window has an Export menu", menu != null);
    if (menu == null) {
        return;
    }
    int last = menu.get_n_items () - 1;
    var label = menu.get_item_attribute_value (last, GLib.Menu.ATTRIBUTE_LABEL, GLib.VariantType.STRING);
    var action = menu.get_item_attribute_value (last, GLib.Menu.ATTRIBUTE_ACTION, GLib.VariantType.STRING);
    check ("the Export menu ends with Export to PDF…", label != null && label.get_string () == "Export to PDF…" && action != null && action.get_string () == "win.export-pdf");
    check ("the PDF entry follows the exporters", last >= 1);

    // A page whose exporter list is not JSON still gets the built-in entry.
    var preview = preview_of (window);
    try {
        yield preview.call_async_javascript_function ("window.mdex.list = () => 'not json'; return 1;", -1, null, null, null, null);
    } catch (GLib.Error e) {
        check ("the exporter list is broken: %s".printf (e.message), false);
        return;
    }
    yield window.build_export_menu ();
    menu = export_menu_of (window);
    check ("a broken exporter list leaves the PDF entry", menu != null && menu.get_n_items () == 1);
}

private async void check_save_pdf (Mdex.MainWindow window, string dir) {
    string? exported = null;
    GLib.File? saved = null;
    window.export_done.connect ((text) => exported = text);
    window.pdf_exported.connect ((file) => saved = file);
    window.set_text ("# Exported\n");
    var target = GLib.File.new_for_path (Path.build_filename (dir, "out.pdf"));
    yield window.save_pdf (target);
    check ("a PDF export reports the text that went out", exported == "# Exported\n");
    check ("a PDF export reports the saved file", saved != null && saved.get_path () == target.get_path ());

    exported = null;
    saved = null;
    yield window.save_pdf (GLib.File.new_for_path (Path.build_filename (dir, "no-such-dir", "out.pdf")));
    check ("a failed PDF export reports nothing", exported == null);
    check ("a failed PDF export reports no file", saved == null);

    window.set_text ("# Exported\n\nKept para.\n");
    yield window.save_pdf (target, "Kept para.");
    string? pdftotext = GLib.Environment.find_program_in_path ("pdftotext");
    if (pdftotext != null) {
        string text = "";
        try {
            GLib.Process.spawn_sync (null, { pdftotext, target.get_path (), "-" }, null, 0, null, out text);
        } catch (GLib.SpawnError e) {
            text = "";
        }
        check ("a PDF of a selection holds only the selection", text.contains ("Kept para.") && !text.contains ("Exported"));
    } else {
        print ("skip a PDF of a selection holds only the selection: no pdftotext\n");
    }
    var preview = preview_of (window);
    string shown = "";
    try {
        var result = yield preview.call_async_javascript_function (
            "return document.getElementById('output').textContent;", -1, null, null, null, null);
        shown = result.to_string ();
    } catch (GLib.Error e) {
        shown = "";
    }
    check ("the preview shows the whole document again after a selection's PDF", shown.contains ("Exported"));
}

// The pane that last had focus decides which selection an export takes, since each pane keeps its selection when it loses focus.
private async void check_selection_source (Mdex.MainWindow window) {
    var editor = editor_of (window);
    var preview = preview_of (window);
    window.set_text ("Alpha para.\n\nBeta para.\n");
    yield wait_ms (400);
    // Selecting in the preview takes the PRIMARY clipboard, and GTK then clears the editor's selection,
    // so the editor is selected second, as a user would leave the panes.
    try {
        yield preview.call_async_javascript_function ("""
            const p = document.getElementById("output").querySelectorAll("p")[1];
            window.getSelection().selectAllChildren(p);
        """, -1, null, null, null, null);
    } catch (GLib.Error e) {
        check ("the preview selection is made: %s".printf (e.message), false);
    }
    Gtk.TextIter start, end;
    editor.buffer.get_iter_at_offset (out start, 0);
    editor.buffer.get_iter_at_offset (out end, 5);
    editor.buffer.select_range (start, end);

    editor.view.grab_focus ();
    yield wait_ms (50);
    string? from_editor = yield window.selected_markdown ();
    check ("with the editor focused last, its selection is exported, got %s".printf (from_editor ?? "null"), from_editor == "Alpha");

    preview.grab_focus ();
    yield wait_ms (50);
    string? from_preview = yield window.selected_markdown ();
    check ("with the preview focused last, its selection is exported, got %s".printf (from_preview ?? "null"), from_preview == "Beta para.");

    editor.view.grab_focus ();
    editor.buffer.select_range (start, start);
    yield wait_ms (50);
    string? none = yield window.selected_markdown ();
    check ("with the editor focused last and nothing selected there, the whole document is exported", none == null);
}

// While renders are paused, a queued render leaves the page as it is.
private async void check_paused (Mdex.MainWindow window) {
    var preview = preview_of (window);
    yield preview.render ("Shown.\n");
    preview.paused = true;
    preview.queue_render ("Queued.\n");
    yield wait_ms (400);
    string shown = "";
    try {
        var result = yield preview.call_async_javascript_function (
            "return document.getElementById('output').textContent;", -1, null, null, null, null);
        shown = result.to_string ();
    } catch (GLib.Error e) {
        shown = "";
    }
    preview.paused = false;
    check ("a paused preview ignores a queued render", shown.contains ("Shown."));
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
    check ("the PDF export action exists as soon as the window is built", window.lookup_action ("export-pdf") != null);
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

    var loop = new GLib.MainLoop ();
    window.present ();
    check_bars.begin (window, ticket, plan, (obj, res) => {
        check_bars.end (res);
        loop.quit ();
    });
    loop.run ();

    check ("a document's PDF is named after it", Mdex.MainWindow.pdf_name ("391.ticket.md") == "391.ticket.pdf");
    check ("a document with no extension keeps its name", Mdex.MainWindow.pdf_name ("notes") == "notes.pdf");
    check ("the scratch buffer is named untitled", Mdex.MainWindow.pdf_name ("") == "untitled.pdf");

    var menu_loop = new GLib.MainLoop ();
    check_menu.begin (window, (obj, res) => {
        check_menu.end (res);
        menu_loop.quit ();
    });
    menu_loop.run ();

    var pdf_loop = new GLib.MainLoop ();
    check_save_pdf.begin (window, dir, (obj, res) => {
        check_save_pdf.end (res);
        pdf_loop.quit ();
    });
    pdf_loop.run ();

    var selection_loop = new GLib.MainLoop ();
    check_selection_source.begin (window, (obj, res) => {
        check_selection_source.end (res);
        check_paused.begin (window, (obj2, res2) => {
            check_paused.end (res2);
            selection_loop.quit ();
        });
    });
    selection_loop.run ();

    remove_tree (dir);
    return failures == 0 ? 0 : 1;
}
