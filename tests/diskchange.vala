// Checks what mdex does when the open document's file changes on disk.
//
// mdex's own autosave changes the file too, and a coding session edits it
// while the editor may hold unsaved text, so the decision must never replace
// edits silently.

private int failures = 0;

private void check (string name, Mdex.DiskChange got, Mdex.DiskChange want) {
    if (got == want) {
        print ("ok   %s\n", name);
        return;
    }
    failures++;
    print ("FAIL %s\n", name);
}

public static int main (string[] args) {
    // Disk matches the editor: that is mdex's own write, whatever the editor's state.
    check ("identical and clean is ignored", Mdex.DiskChange.decide ("a", "a", "a", false), Mdex.DiskChange.IGNORE);
    check ("identical with an autosave pending is ignored", Mdex.DiskChange.decide ("b", "b", "a", true), Mdex.DiskChange.IGNORE);

    // Disk differs and the editor holds nothing unsaved: take the disk text.
    check ("different and clean reloads", Mdex.DiskChange.decide ("new", "old", "old", false), Mdex.DiskChange.RELOAD);

    // Disk differs and the editor holds edits: ask.
    check ("different with an autosave pending asks", Mdex.DiskChange.decide ("new", "old", "old", true), Mdex.DiskChange.ASK);
    check ("different with edits not yet saved asks", Mdex.DiskChange.decide ("new", "old+", "old", false), Mdex.DiskChange.ASK);

    return failures == 0 ? 0 : 1;
}
