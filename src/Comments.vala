namespace Mdex {
    /** One review comment, as a coding session sees it in the sidecar file. */
    public class Comment : Object {
        public string id = "";
        /** The rendered text the comment is about. */
        public string quote = "";
        /** Which occurrence of the quote in the rendered text the comment is on, 1-based. */
        public int occurrence = 1;
        public string body = "";
        /** open, resolved or dismissed. */
        public string status = "open";
        /** A session's answer; null until it has one. */
        public string? reply = null;
        /** A phrase from the text the session wrote in answer. */
        public string? change_quote = null;
        public string created = "";

        /** What to look for in the preview: change_quote once a session wrote one, else the quote. */
        public string effective_quote () {
            return follows_change () ? change_quote : quote;
        }

        /** Which occurrence of effective_quote () to look for: the number belongs to the original quote, so a change_quote is looked up from the first. */
        public int effective_occurrence () {
            return follows_change () ? 1 : occurrence;
        }

        private bool follows_change () {
            return change_quote != null && change_quote.strip () != "";
        }
    }

    /**
     * The review comments on one document, kept in a JSON list in a sidecar
     * file that a coding session reads and writes too.
     *
     * The file is the only state: every call reads it, and every write edits
     * the freshly read JSON in place. A reply, or a member this class does not
     * know, that a session wrote since the last call therefore survives.
     */
    public class Comments : Object {
        private const string[] STATUSES = { "open", "resolved", "dismissed" };

        private delegate bool Edit (Json.Array items);

        private string file;

        public Comments (string file) {
            this.file = file;
        }

        /** Where the comments on a document live; null is the scratch buffer. Same key scheme as Revisions. */
        public static string path_for (string? doc_path) {
            string key = doc_path == null ? "scratch" : GLib.Checksum.compute_for_string (ChecksumType.MD5, doc_path);
            return Path.build_filename (GLib.Environment.get_user_cache_dir (), "mdex", "comments", key + ".json");
        }

        /** The comments in file order. A missing, empty or invalid file gives an empty list. */
        public Gee.List<Comment> load () {
            return parse () ?? new Gee.ArrayList<Comment> ();
        }

        /**
         * The comments with the open ones first; each group keeps file order.
         * Null when the file holds something other than a JSON list, which a
         * write must not replace; a missing or empty file gives an empty list.
         * One read answers both, so a caller that needs to tell the two apart reads once.
         */
        public Gee.List<Comment>? list () {
            var all = parse ();
            if (all == null) {
                return null;
            }
            var ordered = new Gee.ArrayList<Comment> ();
            foreach (var c in all) {
                if (c.status == "open") {
                    ordered.add (c);
                }
            }
            foreach (var c in all) {
                if (c.status != "open") {
                    ordered.add (c);
                }
            }
            return ordered;
        }

        /** Drops every comment, for a document that starts over. A file that is not a JSON list stays, as a write would not replace it either. */
        public void clear () {
            if (parse () != null) {
                FileUtils.unlink (file);
            }
        }

        /**
         * Moves the comments to another sidecar, for a document that is saved
         * under a new path. False when they could not move: a sidecar already
         * there belongs to whatever was saved at that path before, so it is
         * kept and these stay where they are. No sidecar means nothing to move.
         */
        public bool move_to (string new_file) {
            if (!FileUtils.test (file, FileTest.EXISTS)) {
                return true;
            }
            try {
                DirUtils.create_with_parents (Path.get_dirname (new_file), 0700);
                GLib.File.new_for_path (file).move (GLib.File.new_for_path (new_file), GLib.FileCopyFlags.NONE);
            } catch (GLib.Error e) {
                warning ("cannot move %s to %s: %s", file, new_file, e.message);
                return false;
            }
            return true;
        }

        /** Adds an open comment on the given occurrence of the quote (below 1 counts as 1). Null when the quote or body is blank, or the file is not valid JSON. */
        public Comment? add (string quote, string body, int occurrence = 1) {
            if (quote.strip () == "" || body.strip () == "") {
                return null;
            }
            Comment? made = null;
            write ((items) => {
                var item = new Json.Object ();
                item.set_string_member ("id", "c%u".printf (items.get_length () + 1));
                item.set_string_member ("quote", quote);
                item.set_int_member ("occurrence", int.max (occurrence, 1));
                item.set_string_member ("body", body);
                item.set_string_member ("status", "open");
                item.set_null_member ("reply");
                item.set_null_member ("change_quote");
                item.set_string_member ("created", new DateTime.now_local ().format ("%Y-%m-%dT%H:%M:%S%:z"));
                items.add_object_element (item);
                made = to_comment (item);
                return true;
            });
            return made;
        }

        /** False when the status is not one of the three, the id is unknown, or the file is not valid JSON. */
        public bool set_status (string id, string status) {
            if (!(status in STATUSES)) {
                return false;
            }
            return write ((items) => {
                var item = find (items, id);
                if (item == null) {
                    return false;
                }
                item.set_string_member ("status", status);
                return true;
            });
        }

        /** Changes the body while the comment is open and unanswered; false otherwise, or for a blank body. */
        public bool edit (string id, string body) {
            if (body.strip () == "") {
                return false;
            }
            return write ((items) => {
                var item = find (items, id);
                if (item == null) {
                    return false;
                }
                var comment = to_comment (item);
                if (comment.status != "open" || (comment.reply ?? "").strip () != "") {
                    return false;
                }
                item.set_string_member ("body", body);
                return true;
            });
        }

        private Gee.List<Comment>? parse () {
            var root = read_root ();
            if (root == null) {
                return null;
            }
            var comments = new Gee.ArrayList<Comment> ();
            var items = root.get_array ();
            for (uint i = 0; i < items.get_length (); i++) {
                var node = items.get_element (i);
                if (node.get_node_type () == Json.NodeType.OBJECT) {
                    comments.add (to_comment (node.get_object ()));
                }
            }
            return comments;
        }

        /**
         * The file's JSON list, empty for a missing or empty file. Null when
         * the file holds anything else, which a write must not replace.
         */
        private Json.Node? read_root () {
            string text = "";
            try {
                FileUtils.get_contents (file, out text);
            } catch (GLib.FileError e) {
                if (!(e is GLib.FileError.NOENT)) {
                    warning ("cannot read %s: %s", file, e.message);
                    return null;
                }
                text = "";
            }
            if (text.strip () == "") {
                var root = new Json.Node (Json.NodeType.ARRAY);
                root.take_array (new Json.Array ());
                return root;
            }
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (text);
                var root = parser.steal_root ();
                if (root.get_node_type () == Json.NodeType.ARRAY) {
                    return root;
                }
                warning ("%s is not a JSON list; leaving it alone", file);
            } catch (GLib.Error e) {
                warning ("%s is not valid JSON; leaving it alone: %s", file, e.message);
            }
            return null;
        }

        /** Reads the file afresh, applies the edit and writes the result atomically. False if the edit declines or the file cannot be used. */
        private bool write (Edit edit) {
            var root = read_root ();
            if (root == null || !edit (root.get_array ())) {
                return false;
            }
            var generator = new Json.Generator ();
            generator.pretty = true;
            generator.set_root (root);
            try {
                DirUtils.create_with_parents (Path.get_dirname (file), 0700);
                FileUtils.set_contents (file, generator.to_data (null) + "\n");
            } catch (GLib.FileError e) {
                warning ("cannot write %s: %s", file, e.message);
                return false;
            }
            return true;
        }

        private static Json.Object? find (Json.Array items, string id) {
            for (uint i = 0; i < items.get_length (); i++) {
                var node = items.get_element (i);
                if (node.get_node_type () == Json.NodeType.OBJECT && text_of (node.get_object (), "id") == id) {
                    return node.get_object ();
                }
            }
            return null;
        }

        private static Comment to_comment (Json.Object item) {
            var comment = new Comment ();
            comment.id = text_of (item, "id") ?? "";
            comment.quote = text_of (item, "quote") ?? "";
            comment.occurrence = count_of (item, "occurrence");
            comment.body = text_of (item, "body") ?? "";
            comment.status = text_of (item, "status") ?? "open";
            comment.reply = text_of (item, "reply");
            comment.change_quote = text_of (item, "change_quote");
            comment.created = text_of (item, "created") ?? "";
            return comment;
        }

        /** A number member from 1 up to int.MAX, or 1 when it is missing, below 1, too large or not a number. */
        private static int count_of (Json.Object item, string member) {
            var node = item.get_member (member);
            if (node == null || (node.get_value_type () != typeof (int64) && node.get_value_type () != typeof (double))) {
                return 1;
            }
            int64 n = node.get_int ();
            return n >= 1 && n <= int.MAX ? (int) n : 1;
        }

        /** A string member, or null when it is missing, null or not a string. */
        private static string? text_of (Json.Object item, string member) {
            var node = item.get_member (member);
            return node != null && node.get_value_type () == typeof (string) ? node.get_string () : null;
        }
    }
}
