// Checks that export_pdf prints the page to a PDF at the target, and reports a failure
// instead of success when it cannot write there.
//
// It builds a WebView and prints it without a dialog, so it needs a display and skips (exit 77) without one.

private int failures = 0;

private void check (string name, bool ok) {
    print ("%s %s\n", ok ? "ok  " : "FAIL", name);
    if (!ok) {
        failures++;
    }
}

private bool is_pdf (GLib.File file) {
    uint8[] data;
    try {
        FileUtils.get_data (file.get_path (), out data);
    } catch (GLib.FileError e) {
        return false;
    }
    return data.length > 4 && Memory.cmp (data, "%PDF".data, 4) == 0;
}

private async void check_page (Mdex.Preview preview, string dir) {
    try {
        yield preview.load_shell ();
    } catch (GLib.Error e) {
        check ("the shell loads: %s".printf (e.message), false);
        return;
    }
    yield preview.render ("# Title\n\n- one\n- two\n");

    var target = GLib.File.new_for_path (Path.build_filename (dir, "out.pdf"));
    try {
        yield preview.export_pdf (target);
        check ("a PDF is written at the target", is_pdf (target));
    } catch (GLib.Error e) {
        check ("a PDF is written at the target: %s".printf (e.message), false);
    }

    var missing = GLib.File.new_for_path (Path.build_filename (dir, "no-such-dir", "out.pdf"));
    bool failed = false;
    try {
        yield preview.export_pdf (missing);
    } catch (GLib.Error e) {
        failed = true;
    }
    check ("a path in a missing directory reports failure", failed && !missing.query_exists ());
}

public static int main (string[] args) {
    if (!Gtk.init_check ()) {
        print ("skip: no display\n");
        return 77;
    }

    string dir;
    try {
        dir = DirUtils.make_tmp ("mdex-pdf-XXXXXX");
    } catch (GLib.Error e) {
        print ("FAIL no temp directory: %s\n", e.message);
        return 1;
    }

    var loop = new GLib.MainLoop ();
    var preview = new Mdex.Preview ();
    var window = new Gtk.Window ();
    window.set_default_size (800, 600);
    window.child = preview;
    window.present ();
    check_page.begin (preview, dir, (obj, res) => {
        check_page.end (res);
        loop.quit ();
    });
    loop.run ();

    FileUtils.remove (Path.build_filename (dir, "out.pdf"));
    FileUtils.remove (dir);
    return failures == 0 ? 0 : 1;
}
