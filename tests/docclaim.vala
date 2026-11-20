// Checks DocClaim.bus_name, the session-bus name a window claims for the file
// it has open.
//
// A second launch finds the first window by that name, so the same path must
// always give the same name, two paths must never share one, and the bus must
// accept it: a name it rejects makes the claim fail and the file open twice.
//
// It also checks DocClaim.raise_pane, which `mdex --raise` uses to bring forward every window launched from
// one herdr pane. That half claims names on the session bus, so it skips (exit 77) without one.

private int failures = 0;

private void check (string name, bool ok) {
    if (ok) {
        print ("ok   %s\n", name);
        return;
    }
    failures++;
    print ("FAIL %s\n", name);
}

private bool valid_name (string name) {
    if (name.length > 255) {
        return false;
    }
    foreach (string element in name.split (".")) {
        // Elements start with a letter or underscore and hold only [A-Za-z0-9_].
        if (!Regex.match_simple ("^[A-Za-z_][A-Za-z0-9_]*$", element)) {
            return false;
        }
    }
    return name.split (".").length >= 2 && GLib.DBus.is_name (name);
}

// Stands in for a window from before panes were recorded: it has the interface and present, but no pane property.
[DBus (name = "com.github.svandragt.mdex.Doc")]
private class OldDoc : Object {
    public bool presented = false;

    public void present (string token) throws GLib.Error {
        presented = true;
    }
}

private bool wait_for_owner (GLib.DBusConnection bus, string name) {
    for (int i = 0; i < 100; i++) {
        while (MainContext.default ().iteration (false)) {
        }
        try {
            bus.call_sync ("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetNameOwner",
                new Variant ("(s)", name), null, DBusCallFlags.NONE, -1);
            return true;
        } catch (GLib.Error e) {
            Thread.usleep (20000);
        }
    }
    return false;
}

// The raise blocks on the other windows, so it runs in a thread while the main loop answers for the windows in this process.
private int raise_in_thread (string pane, string token) {
    var loop = new MainLoop ();
    var thread = new Thread<int> ("raise", () => {
        int raised = Mdex.DocClaim.raise_pane (pane, token);
        Idle.add (() => {
            loop.quit ();
            return Source.REMOVE;
        });
        return raised;
    });
    loop.run ();
    return thread.join ();
}

private void check_raise () throws GLib.Error {
    string pane = "mdex-test-pane-%d".printf ((int) Posix.getpid ());
    Environment.set_variable ("HERDR_PANE_ID", pane, true);
    var claim = new Mdex.DocClaim ();
    string? token = null;
    claim.present_requested.connect ((t) => token = t);
    claim.claim ("/mdex-test/%s.md".printf (pane));

    var old_bus = new DBusConnection.for_address_sync (
        BusType.SESSION.get_address_sync (), DBusConnectionFlags.AUTHENTICATION_CLIENT | DBusConnectionFlags.MESSAGE_BUS_CONNECTION, null);
    var old = new OldDoc ();
    old_bus.register_object ("/com/github/svandragt/mdex/Doc", old);
    Bus.own_name_on_connection (old_bus, Mdex.DocClaim.bus_name ("/mdex-test/old-%s.md".printf (pane)), BusNameOwnerFlags.DO_NOT_QUEUE);

    var bus = Bus.get_sync (BusType.SESSION);
    check ("the claim is on the bus", wait_for_owner (bus, Mdex.DocClaim.bus_name ("/mdex-test/%s.md".printf (pane))));
    check ("the old-style window is on the bus", wait_for_owner (bus, Mdex.DocClaim.bus_name ("/mdex-test/old-%s.md".printf (pane))));

    check ("a raise for another pane finds nothing", raise_in_thread ("mdex-test-other-pane", "other") == 0 && token == null);
    check ("a raise with no pane finds nothing", raise_in_thread ("", "none") == 0 && token == null);
    check ("a raise for the pane finds its window", raise_in_thread (pane, "tok") == 1);
    check ("the window is asked to come forward with the token", token == "tok");
    check ("a window with no pane property is skipped", !old.presented);
}

public static int main (string[] args) {
    string plain = Mdex.DocClaim.bus_name ("/home/me/notes.md");

    check ("same path, same name", plain == Mdex.DocClaim.bus_name ("/home/me/notes.md"));
    check ("different paths, different names", plain != Mdex.DocClaim.bus_name ("/home/me/other.md"));
    check ("case matters", plain != Mdex.DocClaim.bus_name ("/home/me/Notes.md"));
    check ("valid D-Bus name", valid_name (plain));
    check ("name is not empty", plain != "");

    // A name made from the path's characters would break on these.
    string spaced = Mdex.DocClaim.bus_name ("/home/me/my notes (draft).md");
    check ("spaces", valid_name (spaced) && spaced != plain);
    string accented = Mdex.DocClaim.bus_name ("/home/me/café — 日本語.md");
    check ("non-ASCII", valid_name (accented) && accented != spaced);
    check ("non-ASCII, same path", accented == Mdex.DocClaim.bus_name ("/home/me/café — 日本語.md"));

    // The bus caps a name at 255 characters, however long the path.
    string long_path = "/" + string.nfill (4000, 'a') + ".md";
    check ("long path", valid_name (Mdex.DocClaim.bus_name (long_path)));

    try {
        Bus.get_sync (BusType.SESSION);
    } catch (GLib.Error e) {
        print ("skip raise: no session bus\n");
        return failures == 0 ? 77 : 1;
    }
    try {
        check_raise ();
    } catch (GLib.Error e) {
        check ("raise checks ran: %s".printf (e.message), false);
    }

    return failures == 0 ? 0 : 1;
}
