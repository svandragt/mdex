// Checks the read-only lock a launch puts on the editor, so a window that grabs
// focus from another program does not take that program's keystrokes.
//
// The click that lifts the lock needs a real pointer, so this calls unlock ()
// directly. It needs a display to build widgets and skips (exit 77) without one.

private int failures = 0;

private void check (string name, bool ok) {
    print ("%s %s\n", ok ? "ok  " : "FAIL", name);
    if (!ok) {
        failures++;
    }
}

// The editor's own shortcut handler: the view's built-in key controllers run in the bubble phase.
private Gtk.EventControllerKey? shortcut_handler (Mdex.Editor editor) {
    var controllers = editor.view.observe_controllers ();
    for (uint i = 0; i < controllers.get_n_items (); i++) {
        var key = controllers.get_item (i) as Gtk.EventControllerKey;
        if (key != null && key.propagation_phase == Gtk.PropagationPhase.CAPTURE) {
            return key;
        }
    }
    return null;
}

private void select_all (Mdex.Editor editor) {
    Gtk.TextIter start, end;
    editor.buffer.get_bounds (out start, out end);
    editor.buffer.select_range (start, end);
}

public static int main (string[] args) {
    if (!Gtk.init_check ()) {
        print ("skip: no display\n");
        return 77;
    }

    var editor = new Mdex.Editor ();
    check ("editable until locked", editor.view.editable && !editor.banner.visible);

    editor.lock_until_click ();
    check ("locked view is read-only", !editor.view.editable);
    check ("locked editor shows the banner", editor.banner.visible);

    // A reload or restore must still reach the buffer while the view is locked.
    editor.set_text ("hello");
    check ("set_text works while locked", editor.get_text () == "hello");

    // Formatting shortcuts edit the buffer directly, so view.editable alone does not stop them.
    var keys = shortcut_handler (editor);
    check ("editor has a shortcut handler", keys != null);
    select_all (editor);
    keys.key_pressed (Gdk.Key.b, 0, Gdk.ModifierType.CONTROL_MASK);
    check ("Ctrl+B changes nothing while locked", editor.get_text () == "hello");
    keys.key_pressed (Gdk.Key.@1, 0, Gdk.ModifierType.CONTROL_MASK);
    check ("Ctrl+1 changes nothing while locked", editor.get_text () == "hello");
    check ("Ctrl+F is still handled while locked", keys.key_pressed (Gdk.Key.f, 0, Gdk.ModifierType.CONTROL_MASK));

    editor.unlock ();
    check ("unlocked view is editable", editor.view.editable);
    check ("unlocked editor hides the banner", !editor.banner.visible);
    check ("text survives the unlock", editor.get_text () == "hello");

    select_all (editor);
    keys.key_pressed (Gdk.Key.b, 0, Gdk.ModifierType.CONTROL_MASK);
    check ("Ctrl+B formats once unlocked", editor.get_text () == "**hello**");

    return failures == 0 ? 0 : 1;
}
