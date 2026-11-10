// Checks DocClaim.bus_name, the session-bus name a window claims for the file
// it has open.
//
// A second launch finds the first window by that name, so the same path must
// always give the same name, two paths must never share one, and the bus must
// accept it: a name it rejects makes the claim fail and the file open twice.

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

    return failures == 0 ? 0 : 1;
}
