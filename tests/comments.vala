// Checks Comments, the review-comment store behind a document.
//
// A coding session edits the same JSON file while mdex has it open, so every
// write must keep what the session put there, and a file that is not valid
// JSON must never be overwritten.

private int failures = 0;

private void check (string name, bool ok) {
    if (ok) {
        print ("ok   %s\n", name);
        return;
    }
    failures++;
    print ("FAIL %s\n", name);
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

private string slurp (string path) {
    string text = "";
    try {
        FileUtils.get_contents (path, out text);
    } catch (GLib.FileError e) {
        // A missing file reads as empty.
        text = "";
    }
    return text;
}

private void spit (string path, string text) {
    try {
        FileUtils.set_contents (path, text);
    } catch (GLib.FileError e) {
        error ("cannot write %s: %s", path, e.message);
    }
}

/** What a session does: set a member on one comment, leaving the rest of the file alone. */
private void session_sets (string path, string id, string member, string value) {
    try {
        var parser = new Json.Parser ();
        parser.load_from_data (slurp (path));
        var root = parser.steal_root ();
        var items = root.get_array ();
        for (uint i = 0; i < items.get_length (); i++) {
            var item = items.get_object_element (i);
            if (item.get_string_member ("id") == id) {
                item.set_string_member (member, value);
            }
        }
        var generator = new Json.Generator ();
        generator.set_root (root);
        spit (path, generator.to_data (null));
    } catch (GLib.Error e) {
        error ("session write failed: %s", e.message);
    }
}

private string ids (Gee.List<Mdex.Comment> comments) {
    var names = new string[0];
    foreach (var c in comments) {
        names += c.id;
    }
    return string.joinv (",", names);
}

public static int main (string[] args) {
    string dir;
    try {
        dir = DirUtils.make_tmp ("mdex-comments-XXXXXX");
    } catch (GLib.FileError e) {
        error ("no temp dir: %s", e.message);
    }
    // The directory does not exist yet: the first write has to create it.
    string file = Path.build_filename (dir, "nested", "doc.json");

    // Add, then reload from a fresh model: every field comes back.
    var comments = new Mdex.Comments (file);
    var made = comments.add ("the quote", "the body");
    check ("add returns an open comment", made != null && made.status == "open" && made.id == "c1");
    check ("add timestamps to the second, with an offset",
        made != null && Regex.match_simple ("^\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\d[+-]\\d\\d:\\d\\d$", made.created));
    var second = comments.add ("other quote", "other body");
    check ("second id follows the first", second != null && second.id == "c2");
    var loaded = new Mdex.Comments (file).load ();
    check ("reload keeps both comments", loaded.size == 2);
    if (loaded.size == 2 && made != null) {
        var c = loaded[0];
        check ("reload keeps id, quote, body, status",
            c.id == "c1" && c.quote == "the quote" && c.body == "the body" && c.status == "open");
        check ("reload keeps created", c.created == made.created);
        check ("reply and change_quote start empty", c.reply == null && c.change_quote == null);
    }
    check ("blank quote is refused", comments.add ("  ", "body") == null);
    check ("blank body is refused", comments.add ("quote", "") == null);

    // set_status
    check ("resolve", comments.set_status ("c1", "resolved"));
    check ("status persists", new Mdex.Comments (file).load ()[0].status == "resolved");
    check ("dismiss", comments.set_status ("c1", "dismissed"));
    check ("reopen", comments.set_status ("c1", "open"));
    check ("unknown status is refused", !comments.set_status ("c1", "bogus"));
    check ("refused status leaves the old one", new Mdex.Comments (file).load ()[0].status == "open");
    check ("unknown id is refused", !comments.set_status ("c99", "resolved"));

    // edit: only while open and unanswered
    check ("edit while open", comments.edit ("c1", "new body"));
    check ("edit persists", new Mdex.Comments (file).load ()[0].body == "new body");
    check ("blank edit is refused", !comments.edit ("c1", " "));
    check ("edit of unknown id is refused", !comments.edit ("c99", "x"));
    comments.set_status ("c1", "resolved");
    check ("edit refused once resolved", !comments.edit ("c1", "late"));
    comments.set_status ("c1", "open");
    session_sets (file, "c1", "reply", "Done");
    check ("edit refused after a reply", !comments.edit ("c1", "late"));
    check ("refused edit leaves the body", new Mdex.Comments (file).load ()[0].body == "new body");
    session_sets (file, "c2", "reply", "");
    check ("an empty reply does not block an edit", comments.edit ("c2", "edited"));

    // A reply written between load and write survives the write.
    check ("reply is read", new Mdex.Comments (file).load ()[0].reply == "Done");
    var stale = new Mdex.Comments (file);
    stale.load ();
    session_sets (file, "c2", "reply", "Answered");
    session_sets (file, "c2", "change_quote", "new phrase");
    check ("write after the session's reply", stale.set_status ("c2", "resolved"));
    var c2 = new Mdex.Comments (file).load ()[1];
    check ("reply survives", c2.reply == "Answered");
    check ("change_quote survives", c2.change_quote == "new phrase");
    check ("the write itself took", c2.status == "resolved");
    var again = stale.add ("late quote", "late body");
    check ("add keeps the session's replies", again != null && again.id == "c3"
        && new Mdex.Comments (file).load ()[0].reply == "Done");

    // Members this code does not know are kept.
    session_sets (file, "c1", "session", "abc123");
    comments.set_status ("c1", "resolved");
    check ("unknown member survives", slurp (file).contains ("abc123"));

    // Open comments list first, in file order within each group.
    check ("open comments come first", ids (comments.list ()) == "c3,c1,c2");
    comments.set_status ("c2", "open");
    comments.set_status ("c3", "open");
    comments.set_status ("c1", "dismissed");
    check ("order within a group is file order", ids (comments.list ()) == "c2,c3,c1");
    check ("load keeps file order", ids (comments.load ()) == "c1,c2,c3");

    // Missing, empty and invalid files.
    string missing = Path.build_filename (dir, "missing.json");
    check ("missing file is an empty list", new Mdex.Comments (missing).load ().size == 0);
    check ("loading does not create the file", !FileUtils.test (missing, FileTest.EXISTS));

    string blank = Path.build_filename (dir, "blank.json");
    spit (blank, "");
    check ("empty file is an empty list", new Mdex.Comments (blank).load ().size == 0);
    check ("empty file is readable", new Mdex.Comments (blank).list () != null);
    spit (blank, "  \n");
    check ("blank file is an empty list", new Mdex.Comments (blank).list ().size == 0);
    check ("blank file is readable", new Mdex.Comments (blank).list () != null);
    check ("an empty file takes a comment", new Mdex.Comments (blank).add ("q", "b") != null);

    check ("missing file is readable", new Mdex.Comments (missing).list () != null);
    check ("a list is readable", new Mdex.Comments (blank).list () != null && new Mdex.Comments (file).list () != null);
    check ("a path that is a directory is not readable", new Mdex.Comments (dir).list () == null);

    foreach (string bad in new string[] { "{not json", "{\"a\": 1}", "[1, {\"id\": }" }) {
        string broken = Path.build_filename (dir, "broken.json");
        spit (broken, bad);
        var model = new Mdex.Comments (broken);
        check ("an invalid file is not readable: " + bad, model.list () == null);
        check ("invalid file loads as empty: " + bad, model.load ().size == 0);
        check ("add refuses to overwrite: " + bad, model.add ("q", "b") == null);
        check ("set_status refuses to overwrite: " + bad, !model.set_status ("c1", "resolved"));
        check ("edit refuses to overwrite: " + bad, !model.edit ("c1", "x"));
        check ("invalid file is left as it was: " + bad, slurp (broken) == bad);
    }

    // Which occurrence of a repeated quote the comment is on: written by add, kept by reloads and writes, 1 when absent or invalid.
    string repeats = Path.build_filename (dir, "repeats.json");
    var counted = new Mdex.Comments (repeats);
    var plain_add = counted.add ("red fox", "first");
    var third = counted.add ("red fox", "third", 3);
    check ("add defaults to the first occurrence", plain_add != null && plain_add.occurrence == 1);
    check ("add returns the occurrence it was given", third != null && third.occurrence == 3);
    check ("the occurrence is written as a number", slurp (repeats).contains ("\"occurrence\" : 3"));
    check ("an occurrence below 1 is stored as 1", counted.add ("red fox", "zero", 0).occurrence == 1 && counted.add ("red fox", "negative", -4).occurrence == 1);
    var reread = new Mdex.Comments (repeats).load ();
    check ("a reload keeps the occurrence", reread[0].occurrence == 1 && reread[1].occurrence == 3);
    counted.set_status ("c2", "resolved");
    session_sets (repeats, "c1", "reply", "Done");
    counted.edit ("c1", "first, reworded");
    check ("a status change, an edit and a session write keep the occurrence", new Mdex.Comments (repeats).load ()[1].occurrence == 3 && new Mdex.Comments (repeats).load ()[0].occurrence == 1);

    spit (repeats, """[
      {"id": "a", "quote": "q", "body": "b"},
      {"id": "b", "quote": "q", "body": "b", "occurrence": 4},
      {"id": "c", "quote": "q", "body": "b", "occurrence": 0},
      {"id": "d", "quote": "q", "body": "b", "occurrence": -2},
      {"id": "e", "quote": "q", "body": "b", "occurrence": "2"},
      {"id": "f", "quote": "q", "body": "b", "occurrence": null},
      {"id": "g", "quote": "q", "body": "b", "occurrence": true},
      {"id": "h", "quote": "q", "body": "b", "occurrence": 2.0},
      {"id": "i", "quote": "q", "body": "b", "occurrence": 99999999999999}
    ]""");
    var older = new Mdex.Comments (repeats).load ();
    check ("a comment without the field is on the first occurrence", older[0].occurrence == 1);
    check ("a stored occurrence is read", older[1].occurrence == 4);
    check ("an occurrence below 1 reads as 1", older[2].occurrence == 1 && older[3].occurrence == 1);
    check ("an occurrence that is not a number reads as 1", older[4].occurrence == 1 && older[5].occurrence == 1 && older[6].occurrence == 1);
    check ("a whole number written with a fraction part is read", older[7].occurrence == 2);
    check ("an occurrence too large for an int reads as 1", older[8].occurrence == 1);

    // The number belongs to the original quote, so a change_quote is looked up from the first occurrence.
    var repeated = new Mdex.Comment ();
    repeated.quote = "red fox";
    repeated.occurrence = 3;
    check ("without a change_quote the occurrence is kept", repeated.effective_occurrence () == 3);
    repeated.change_quote = " \n";
    check ("a blank change_quote keeps the occurrence", repeated.effective_occurrence () == 3);
    repeated.change_quote = "blue fox";
    check ("a change_quote is located from the first occurrence", repeated.effective_occurrence () == 1 && repeated.effective_quote () == "blue fox");
    check ("a new comment is on the first occurrence", new Mdex.Comment ().occurrence == 1);

    // Where a comment is located in the page: change_quote once a session wrote one, else the quote.
    var located = new Mdex.Comment ();
    located.quote = "old words";
    check ("without a change_quote the quote locates the comment", located.effective_quote () == "old words");
    located.change_quote = "";
    check ("an empty change_quote is ignored", located.effective_quote () == "old words");
    located.change_quote = " \n";
    check ("a blank change_quote is ignored", located.effective_quote () == "old words");
    located.change_quote = "new words";
    check ("a change_quote locates the comment", located.effective_quote () == "new words");
    var written = new Mdex.Comments (file).load ();
    check ("a loaded comment follows its change_quote", written[1].effective_quote () == "new phrase" && written[0].effective_quote () == written[0].quote);

    // A document that starts over drops its comments, so the next one is c1. A file that is not a list stays, as a write would not replace it either.
    string wiped = Path.build_filename (dir, "wiped.json");
    var old_comments = new Mdex.Comments (wiped);
    old_comments.add ("q", "b");
    old_comments.add ("q2", "b2");
    old_comments.clear ();
    check ("clear drops every comment", old_comments.load ().size == 0 && !FileUtils.test (wiped, FileTest.EXISTS));
    check ("the next comment is the first again", old_comments.add ("q", "b").id == "c1");
    old_comments.clear ();
    old_comments.clear ();
    check ("clear with no sidecar does nothing", !FileUtils.test (wiped, FileTest.EXISTS));
    spit (wiped, "{not json");
    old_comments.clear ();
    check ("clear leaves a file that is not a list", slurp (wiped) == "{not json");

    // Comments follow their document when it moves: the sidecar goes to the new path's key, whatever the session wrote in it.
    string from = Path.build_filename (dir, "from.json");
    string to = Path.build_filename (dir, "other", "to.json");
    var moving = new Mdex.Comments (from);
    moving.add ("first", "one");
    moving.add ("second", "two");
    session_sets (from, "c2", "reply", "Done");
    check ("moving the comments works", moving.move_to (to));
    var moved = new Mdex.Comments (to).load ();
    check ("the comments arrive whole", moved.size == 2 && moved[0].quote == "first" && moved[1].reply == "Done");
    check ("nothing is left at the old path", !FileUtils.test (from, FileTest.EXISTS));
    check ("no sidecar means nothing to move", new Mdex.Comments (from).move_to (Path.build_filename (dir, "never.json"))
        && !FileUtils.test (Path.build_filename (dir, "never.json"), FileTest.EXISTS));

    // A sidecar already at the destination belongs to whatever document was saved there before: it is kept, and the moving comments stay where they are.
    var staying = new Mdex.Comments (from);
    staying.add ("kept quote", "kept body");
    check ("an existing sidecar is not replaced", !staying.move_to (to));
    check ("the destination keeps its own comments", new Mdex.Comments (to).load ().size == 2);
    check ("the refused comments stay in place", new Mdex.Comments (from).load ().size == 1 && new Mdex.Comments (from).load ()[0].quote == "kept quote");

    // The sidecar path.
    string path = Mdex.Comments.path_for ("/home/me/notes.md");
    check ("path is stable", path == Mdex.Comments.path_for ("/home/me/notes.md"));
    check ("path differs per document", path != Mdex.Comments.path_for ("/home/me/other.md"));
    check ("path is in the cache, keyed by an MD5",
        path.has_prefix (Path.build_filename (Environment.get_user_cache_dir (), "mdex", "comments") + "/")
        && Regex.match_simple ("/[0-9a-f]{32}\\.json$", path));
    check ("scratch buffer has its own path", Mdex.Comments.path_for (null).has_suffix ("/mdex/comments/scratch.json"));

    remove_tree (dir);
    return failures == 0 ? 0 : 1;
}
