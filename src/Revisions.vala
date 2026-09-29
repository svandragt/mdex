namespace Mdex {
    /**
     * Snapshots of one document, kept as timestamped markdown files under
     * ~/.cache/mdex/revisions/<doc>/. The directory listing is the index.
     */
    public class Revisions : Object {
        private string dir;

        /** Key is the document path, or null for the scratch buffer. */
        public Revisions (string? path) {
            string key = path == null ? "scratch" : GLib.Checksum.compute_for_string (ChecksumType.MD5, path);
            dir = Path.build_filename (GLib.Environment.get_user_cache_dir (), "mdex", "revisions", key);
            DirUtils.create_with_parents (dir, 0700);
        }

        /** Snapshot file names, oldest first. */
        public string[] list () {
            var names = new Gee.ArrayList<string> ();
            try {
                var d = Dir.open (dir);
                string? name;
                while ((name = d.read_name ()) != null) {
                    if (name.has_suffix (".md")) {
                        names.add (name);
                    }
                }
            } catch (GLib.Error e) {
                // Directory gone — nothing to list.
            }
            names.sort ();
            return names.to_array ();
        }

        public string path_of (string name) {
            return Path.build_filename (dir, name);
        }

        public string read (string name) {
            string text = "";
            try {
                FileUtils.get_contents (path_of (name), out text);
            } catch (GLib.FileError e) {
                warning ("could not read revision %s: %s", name, e.message);
            }
            return text;
        }

        /** Writes a snapshot unless it matches the latest one; returns whether it wrote. `why` shows in the list. */
        public bool snapshot (string text, string why) {
            string[] names = list ();
            if (text.strip () == "" || (names.length > 0 && read (names[names.length - 1]) == text)) {
                return false;
            }
            // The name is the sort key, so two snapshots in one moment get distinct milliseconds.
            var now = new DateTime.now_local ();
            int ms = now.get_microsecond () / 1000;
            string stamp = now.format ("%Y%m%d-%H%M%S");
            while (names.length > 0 && names[names.length - 1].has_prefix (stamp + "%03d".printf (ms))) {
                ms++;
            }
            string name = stamp + "%03d-%s.md".printf (ms, why);
            try {
                FileUtils.set_contents (path_of (name), text);
            } catch (GLib.FileError e) {
                warning ("could not write revision: %s", e.message);
                return false;
            }
            return true;
        }

        public void clear () {
            foreach (string name in list ()) {
                FileUtils.unlink (path_of (name));
            }
        }

        /** "Original" for the first snapshot, otherwise when and why it was taken. */
        public string label (string name) {
            string[] names = list ();
            if (names.length > 0 && names[0] == name) {
                return "Original";
            }
            if (name.length < 23) {
                return name; // not one of ours: hand-copied or from an older build
            }
            var t = new DateTime.local (
                int.parse (name.substring (0, 4)), int.parse (name.substring (4, 2)), int.parse (name.substring (6, 2)),
                int.parse (name.substring (9, 2)), int.parse (name.substring (11, 2)), int.parse (name.substring (13, 2))
            );
            string why = name.substring (19, name.length - 22).replace ("-", " ");
            return t.format ("%e %b %H:%M") + " · " + why;
        }
    }

    /** Picks two revisions and shows the unified diff between them. */
    public class RevisionsWindow : Gtk.Window {
        private const string CURRENT = "current";

        private Revisions store;
        private string current_text;
        private Gtk.DropDown from_drop;
        private Gtk.DropDown to_drop;
        private GtkSource.Buffer diff_buffer;
        private string[] names;

        public signal void restore_requested (string text, string label);

        public RevisionsWindow (Gtk.Window parent, Revisions store, string current_text) {
            Object (transient_for: parent, title: "Revisions", default_width: 800, default_height: 600);
            this.store = store;
            this.current_text = current_text;

            names = store.list ();
            string[] labels = {};
            foreach (string name in names) {
                labels += store.label (name);
            }
            labels += "Current";

            from_drop = new Gtk.DropDown.from_strings (labels) {
                selected = 0,
            };
            to_drop = new Gtk.DropDown.from_strings (labels) {
                selected = names.length,
            };
            from_drop.notify["selected"].connect (() => refresh.begin ());
            to_drop.notify["selected"].connect (() => refresh.begin ());

            var restore = new Gtk.Button () {
                tooltip_text = "Put the left-hand revision back in the editor",
            };
            restore.clicked.connect (() => restore_requested (text_at (from_drop.selected), label_at (from_drop.selected)));
            from_drop.notify["selected"].connect (() => {
                restore.label = "Restore " + label_at (from_drop.selected);
                restore.sensitive = from_drop.selected < names.length;
            });
            from_drop.notify_property ("selected");

            var bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) { margin_start = 6, margin_end = 6, margin_top = 6, margin_bottom = 6 };
            bar.append (from_drop);
            bar.append (new Gtk.Label ("→"));
            bar.append (to_drop);
            bar.append (restore);

            diff_buffer = new GtkSource.Buffer (null) {
                language = GtkSource.LanguageManager.get_default ().get_language ("diff"),
                highlight_syntax = true,
            };
            bool dark = Granite.Settings.get_default ().prefers_color_scheme == Granite.Settings.ColorScheme.DARK;
            diff_buffer.style_scheme = GtkSource.StyleSchemeManager.get_default ().get_scheme (dark ? "Adwaita-dark" : "Adwaita");
            var view = new GtkSource.View.with_buffer (diff_buffer) {
                editable = false,
                monospace = true,
                wrap_mode = Gtk.WrapMode.WORD_CHAR,
            };
            var scroller = new Gtk.ScrolledWindow () { child = view, vexpand = true };

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            box.append (bar);
            box.append (scroller);
            child = box;

            refresh.begin ();
        }

        private string text_at (uint index) {
            return index < names.length ? store.read (names[index]) : current_text;
        }

        private string label_at (uint index) {
            return index < names.length ? store.label (names[index]) : "Current";
        }

        /** Shells out to diff(1): exit 1 means "different", not failure. */
        private async void refresh () {
            string a = store.path_of ("a.tmp");
            string b = store.path_of ("b.tmp");
            try {
                FileUtils.set_contents (a, text_at (from_drop.selected));
                FileUtils.set_contents (b, text_at (to_drop.selected));
                var proc = new GLib.Subprocess (
                    GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_MERGE,
                    "diff", "-u", "--label", label_at (from_drop.selected), "--label", label_at (to_drop.selected), a, b
                );
                string output;
                yield proc.communicate_utf8_async (null, null, out output, null);
                diff_buffer.text = proc.get_exit_status () == 0 ? "No differences." : output;
            } catch (GLib.Error e) {
                diff_buffer.text = "Could not run diff: " + e.message;
            } finally {
                FileUtils.unlink (a);
                FileUtils.unlink (b);
            }
        }
    }
}
