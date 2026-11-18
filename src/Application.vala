namespace Mdex {
    /**
     * Owns everything that isn't window chrome: CLI input, file I/O,
     * autosave and plugin discovery.
     */
    public class Application : Gtk.Application {
        private MainWindow? window = null;
        private GLib.File? current_file = null;
        private string? current_etag = null;
        private GLib.FileMonitor? monitor = null;
        private uint autosave_id = 0;
        private DocClaim doc_claim = new DocClaim ();
        private Revisions revisions;
        private string last_saved = "";
        private int64 last_edit = 0;
        // Set while load_text fills the buffer with text that is already on disk.
        private bool loading = false;
        // A New Window document lives in the cache until its first manual snapshot asks where to keep it.
        private bool untitled = false;

        private const string USAGE = """Usage:
  mdex [FILE]     open FILE, or resume the last document
  mdex --new      start a blank document
  ... | mdex      edit piped text as a scratch buffer

Options:
  -h, --help      show this help
  --comments-path FILE
                  print where FILE's review comments are kept, then exit

""";

        public Application () {
            // NON_UNIQUE: each launch is its own instance, so two documents can
            // sit side by side and piped stdin is read by the process that owns it.
            Object (
                application_id: "com.github.svandragt.mdex",
                flags: ApplicationFlags.HANDLES_COMMAND_LINE | ApplicationFlags.NON_UNIQUE
            );
        }

        public override int command_line (ApplicationCommandLine cmdline) {
            string[] args = cmdline.get_arguments ();
            string piped = "";

            if (args.length > 1 && (args[1] == "--help" || args[1] == "-h")) {
                cmdline.print ("%s", USAGE);
                return 0;
            }

            if (args.length > 1 && args[1] == "--comments-path") {
                if (args.length < 3) {
                    cmdline.printerr ("mdex: --comments-path needs a FILE\n");
                    return 1;
                }
                cmdline.print ("%s\n", Comments.path_for (GLib.File.new_for_commandline_arg (args[2]).get_path ()));
                return 0;
            }

            // Decided before the window exists, so a launch that only forwards the file (or the resumed document) never builds one.
            GLib.File? wanted = null;
            bool have_piped = false;
            if (args.length > 1 && args[1] != "--new") {
                wanted = GLib.File.new_for_commandline_arg (args[1]);
            } else if (args.length <= 1) {
                if (!Posix.isatty (0) && read_stdin_if_any (out piped)) {
                    have_piped = true;
                } else {
                    string path = "";
                    try {
                        FileUtils.get_contents (last_file ().get_path (), out path);
                    } catch (GLib.FileError e) {
                        // First run — nothing to resume.
                    }
                    path = path.strip ();
                    if (path != "" && GLib.FileUtils.test (path, GLib.FileTest.EXISTS)) {
                        wanted = GLib.File.new_for_path (path);
                    }
                }
            }
            if (wanted != null) {
                string token = cmdline.getenv ("XDG_ACTIVATION_TOKEN") ?? cmdline.getenv ("DESKTOP_STARTUP_ID") ?? "";
                if (open_elsewhere (wanted, token)) {
                    return 0;
                }
            }

            if (window == null) {
                window = new MainWindow (this);
                window.open_requested.connect ((file) => {
                    if (!open_elsewhere (file, activation_token ())) {
                        open_file.begin (file);
                    }
                });
                window.open_in_new_window_requested.connect ((file) => open_in_new_window (file, running_program (args[0])));
                window.new_requested.connect ((file) => {
                    if (!open_elsewhere (file, activation_token ())) {
                        create_file.begin (file);
                    }
                });
                window.copy_requested.connect ((file) => save_copy.begin (file));
                window.scratch_requested.connect (start_scratch);
                window.text_changed.connect (schedule_autosave);
                window.publish_requested.connect ((text) => publish.begin (text));
                window.snapshot_requested.connect ((text) => {
                    if (untitled) {
                        keep_untitled.begin (text);
                        return;
                    }
                    window.show_toast (revisions.snapshot (text, "manual") ? "Snapshot taken" : "Nothing changed since the last snapshot");
                });
                window.reload_requested.connect ((text) => {
                    // Autosave has put the editor's text on disk by now, so keep it restorable and write the reloaded text back.
                    revisions.snapshot (window.get_text (), "before-reload");
                    load_text (text);
                    save_now (text);
                });
                window.export_done.connect ((text) => revisions.snapshot (text, "export"));
                window.pdf_exported.connect ((file) => reveal_file.begin (file));
                window.revisions_requested.connect ((text) => {
                    var dialog = new RevisionsWindow (window, revisions, text);
                    dialog.restore_requested.connect ((old, label) => {
                        revisions.snapshot (window.get_text (), "before-restore");
                        window.set_text (old);
                        dialog.close ();
                        window.show_toast ("Restored " + label);
                    });
                    dialog.present ();
                });
                window.preview_ready.connect (() => on_preview_ready.begin ());
                doc_claim.present_requested.connect ((token) => {
                    if (token != "") {
                        window.set_startup_id (token);
                    }
                    window.editor.lock_until_click ();
                    window.present ();
                });
                // Autosave is debounced, so an edit made just before closing is still pending.
                window.close_request.connect (() => {
                    if (autosave_id != 0) {
                        GLib.Source.remove (autosave_id);
                        autosave_id = 0;
                        save_now (window.get_text ());
                    }
                    return false;
                });

                var quit_action = new SimpleAction ("quit", null);
                quit_action.activate.connect (() => window.close ());
                add_action (quit_action);
                set_accels_for_action ("app.quit", { "<Control>q" });
            }

            if (args.length > 1 && args[1] == "--new") {
                untitled = true;
                var name = "untitled-" + GLib.get_real_time ().to_string () + ".md";
                create_file.begin (scratch_file ().get_parent ().get_child (name));
            } else if (wanted != null) {
                // A path on the command line comes from another program; resuming the last file is the user's own plain launch.
                if (args.length > 1) {
                    window.editor.lock_until_click ();
                }
                open_file.begin (wanted);
            } else if (have_piped) {
                current_file = null;
                doc_claim.release ();
                remember (null);
                track (null, true);
                window.set_text (Editor.unwrap (piped));
                window.set_subtitle ("Scratch");
                revisions.snapshot (window.get_text (), "original");
            } else {
                restore_scratch ();
            }

            window.present ();
            return 0;
        }

        /**
         * Reads piped input, returning false when there wasn't any.
         *
         * stdin is not a tty for a desktop or script launch either, not just
         * for a pipe. Treating those as empty input would overwrite the
         * restored scratch buffer with nothing.
         */
        private bool read_stdin_if_any (out string text) {
            var sb = new StringBuilder ();
            string? line;
            while ((line = stdin.read_line ()) != null) {
                sb.append (line);
                sb.append_c ('\n');
            }
            text = sb.str;
            return text.strip () != "";
        }

        private void restore_scratch () {
            current_file = null;
            doc_claim.release ();
            remember (null);
            track (null, false);
            window.set_subtitle ("Scratch");

            string contents;
            try {
                FileUtils.get_contents (scratch_file ().get_path (), out contents);
                load_text (Editor.unwrap (contents));
                revisions.snapshot (window.get_text (), "original");
            } catch (GLib.FileError e) {
                // No previous scratch session — start empty, nothing to recover.
            }
        }

        /**
         * Points the revision store and the comments at a document. A fresh
         * scratch buffer wipes the old scratch history, since it is a different
         * document living at the same path.
         */
        private void track (GLib.File? file, bool fresh) {
            string? path = file != null ? file.get_path () : null;
            revisions = new Revisions (path);
            if (fresh) {
                revisions.clear ();
                new Comments (Comments.path_for (path)).clear ();
            }
            last_saved = window.get_text ();
            last_edit = 0;
            window.set_document (path);
        }

        /** Drops the current document for an empty scratch buffer; autosave picks up scratch.md on the next edit. */
        private void start_scratch () {
            if (monitor != null) {
                monitor.cancel ();
                monitor = null;
            }
            current_file = null;
            doc_claim.release ();
            remember (null);
            window.set_text ("");
            track (null, true);
            window.set_subtitle ("Scratch");
        }

        /**
         * Asks the window that already has file open to come forward, so it
         * isn't opened twice. The window's own file is a reload, not a new open.
         */
        private bool open_elsewhere (GLib.File file, string token) {
            string? path = file.get_path ();
            if (path == null || (current_file != null && file.equal (current_file))) {
                return false;
            }
            return DocClaim.present_owner (path, token);
        }

        /**
         * Shows file in a window of its own and leaves this one as it is. Windows are
         * separate instances, so that is a new launch, which brings forward the window that already has the file.
         */
        private void open_in_new_window (GLib.File file, string program) {
            string token = activation_token ();
            if (open_elsewhere (file, token)) {
                return;
            }
            var launcher = new GLib.SubprocessLauncher (GLib.SubprocessFlags.NONE);
            if (token != "") {
                launcher.setenv ("XDG_ACTIVATION_TOKEN", token, true);
            }
            try {
                launcher.spawn (program, file.get_path ());
            } catch (GLib.Error e) {
                warning ("could not open %s in a new window: %s", file.get_path (), e.message);
                window.show_toast ("Could not open a new window");
            }
        }

        /** The executable this process runs, so a new window is the same build; argv[0] may be a bare name or a path that no longer resolves. */
        private static string running_program (string argv0) {
            try {
                string exe = GLib.FileUtils.read_link ("/proc/self/exe");
                // An executable replaced while running reads as "<path> (deleted)", which is not a file.
                if (GLib.FileUtils.test (exe, GLib.FileTest.IS_EXECUTABLE)) {
                    return exe;
                }
            } catch (GLib.FileError e) {
                warning ("cannot read the running program: %s", e.message);
            }
            return argv0;
        }

        /** A token from this window's last input, which lets Wayland let another window take focus. */
        private string activation_token () {
            try {
                // GDK refuses to make a token without an AppInfo to name the requester.
                var info = GLib.AppInfo.create_from_commandline ("mdex", "mdex", GLib.AppInfoCreateFlags.NONE);
                return window.get_display ().get_app_launch_context ().get_startup_notify_id (info, new GLib.List<GLib.File> ()) ?? "";
            } catch (GLib.Error e) {
                warning ("no activation token: %s", e.message);
                return "";
            }
        }

        private async void open_file (GLib.File file) {
            try {
                uint8[] contents;
                string? etag;
                yield file.load_contents_async (null, out contents, out etag);

                // Our own autosave fires the monitor too; the etag tells the
                // two apart, so reloading doesn't fight the editor.
                if (current_file != null && file.equal (current_file) && etag == current_etag) {
                    return;
                }

                // Another instance on the same file saves back what it just reloaded;
                // rewriting an identical buffer would bounce saves between the two forever.
                string text = Editor.unwrap ((string) contents);
                bool same_file = current_file != null && file.equal (current_file);
                if (!same_file) {
                    load_text (text);
                } else {
                    var change = DiskChange.decide (text, window.get_text (), last_saved, autosave_id != 0);
                    switch (change) {
                        case DiskChange.RELOAD:
                            // The editor's text is on disk by now, and unless a snapshot already holds it, this reload would leave it in none.
                            revisions.snapshot (window.get_text (), "before-reload");
                            load_text (text);
                            break;
                        case DiskChange.ASK:
                            // The pending autosave overwrites the file within a second, so keep the disk text where Revisions can restore it.
                            revisions.snapshot (text, "external");
                            window.offer_reload (text);
                            break;
                        default:
                            break;
                    }
                    if (change != DiskChange.ASK) {
                        // The disk and the editor agree again, so an earlier offer to reload is out of date.
                        // Not before the etag check above: mdex's own autosave overwrites the offered text and must leave the banner up.
                        window.editor.withdraw_reload_offer ();
                    }
                }
                current_file = file;
                current_etag = etag;
                remember (file);
                window.set_subtitle (untitled ? "Untitled" : file.get_basename ());
                watch (file);
                if (!same_file) {
                    doc_claim.claim (file.get_path ());
                    track (file, false);
                    revisions.snapshot (text, "original");
                }
            } catch (GLib.Error e) {
                warning ("failed to open %s: %s", file.get_path (), e.message);
            }
        }

        /**
         * Replaces the buffer with text that is already on disk: a reload, a
         * file just opened, or the restored scratch buffer. Loading is not an
         * edit, so no autosave or "pause" snapshot follows and a pending
         * autosave of the old text is dropped. No snapshot is taken either:
         * the new text is recorded by the next "pause", whose last_saved is
         * this text.
         */
        private void load_text (string text) {
            if (autosave_id != 0) {
                GLib.Source.remove (autosave_id);
                autosave_id = 0;
            }
            loading = true;
            window.set_text (text);
            loading = false;
            last_saved = text;
        }

        /**
         * Reloads the open file when something else writes to it.
         *
         * CHANGES_DONE_HINT rather than CHANGED: one write arrives as a burst
         * of CHANGED events, and reloading mid-burst shows a half-written
         * file. CREATED covers editors that save by replacing the file.
         */
        private void watch (GLib.File file) {
            if (monitor != null) {
                monitor.cancel ();
            }
            try {
                monitor = file.monitor_file (GLib.FileMonitorFlags.NONE, null);
            } catch (GLib.Error e) {
                warning ("cannot watch %s: %s", file.get_path (), e.message);
                return;
            }
            monitor.changed.connect ((f, other, event) => {
                if (event == GLib.FileMonitorEvent.CHANGES_DONE_HINT
                    || event == GLib.FileMonitorEvent.CREATED) {
                    open_file.begin (file);
                }
            });
        }

        private GLib.File scratch_file () {
            string dir = Path.build_filename (GLib.Environment.get_user_cache_dir (), "mdex");
            DirUtils.create_with_parents (dir, 0700);
            return GLib.File.new_for_path (Path.build_filename (dir, "scratch.md"));
        }

        /** Path of the last document, or empty for the scratch buffer, so a plain launch resumes it. */
        private GLib.File last_file () {
            return scratch_file ().get_parent ().get_child ("last");
        }

        private void remember (GLib.File? file) {
            try {
                FileUtils.set_contents (last_file ().get_path (), file != null ? file.get_path () : "");
            } catch (GLib.FileError e) {
                warning ("could not record last file: %s", e.message);
            }
        }

        /** Creates an empty file and opens it, so autosave has somewhere to go from the first keystroke. */
        private async void create_file (GLib.File file) {
            try {
                string? new_etag;
                yield file.replace_contents_async ("".data, null, false, GLib.FileCreateFlags.NONE, null, out new_etag);
            } catch (GLib.Error e) {
                warning ("could not create %s: %s", file.get_path (), e.message);
                window.show_toast ("Could not create file");
                return;
            }
            yield open_file (file);
        }

        /** Writes the editor text to a file the user picked, leaving the open document and its autosave alone. */
        private async void save_copy (GLib.File file) {
            try {
                string? new_etag;
                yield file.replace_contents_async (window.get_text ().data, null, false, GLib.FileCreateFlags.NONE, null, out new_etag);
            } catch (GLib.Error e) {
                warning ("could not copy to %s: %s", file.get_path (), e.message);
                window.show_toast ("Could not save a copy");
                return;
            }
            window.show_toast ("Copy saved");
        }

        /** Opens the folder holding file in the file manager, with the file selected where it can. */
        private async void reveal_file (GLib.File file) {
            try {
                yield new Gtk.FileLauncher (file).open_containing_folder (window, null);
            } catch (GLib.Error e) {
                warning ("could not show %s in the file manager: %s", file.get_path (), e.message);
            }
        }

        /** Moves the untitled document to where the user picks, then takes the snapshot they asked for. */
        private async void keep_untitled (string text) {
            var dest = yield window.ask_save_location ();
            if (dest == null) {
                return;
            }
            save_now (text);
            try {
                current_file.move (dest, GLib.FileCopyFlags.OVERWRITE, null, null);
            } catch (GLib.Error e) {
                warning ("could not move to %s: %s", dest.get_path (), e.message);
                window.show_toast ("Could not save file");
                return;
            }
            // The comments are keyed by path, so they follow the document; an existing sidecar at the destination is kept (see Comments.move_to).
            if (dest.get_path () != null) {
                new Comments (Comments.path_for (current_file.get_path ())).move_to (Comments.path_for (dest.get_path ()));
            }
            untitled = false;
            yield open_file (dest);
            revisions.snapshot (text, "manual");
            window.show_toast ("Saved and snapshot taken");
        }

        private const int64 IDLE_SNAPSHOT_USEC = 5 * 60 * GLib.TimeSpan.SECOND;

        /**
         * The first edit after a pause snapshots the version that sat still:
         * that is the one worth comparing against, not whatever is mid-keystroke.
         */
        private void schedule_autosave (string text) {
            if (loading) {
                return;
            }
            int64 now = GLib.get_monotonic_time ();
            if (last_edit != 0 && now - last_edit > IDLE_SNAPSHOT_USEC) {
                revisions.snapshot (last_saved, "pause");
            }
            last_edit = now;
            if (autosave_id != 0) {
                GLib.Source.remove (autosave_id);
            }
            autosave_id = GLib.Timeout.add (1000, () => {
                autosave_id = 0;
                save_now (text);
                return GLib.Source.REMOVE;
            });
        }

        private void save_now (string text) {
            GLib.File target = current_file ?? scratch_file ();
            try {
                string? new_etag;
                target.replace_contents (text.data, null, false, GLib.FileCreateFlags.NONE, out new_etag, null);
                if (current_file != null) {
                    current_etag = new_etag;
                }
                last_saved = text;
            } catch (GLib.Error e) {
                warning ("autosave to %s failed: %s", target.get_path (), e.message);
            }
        }

        /**
         * Publishes the buffer through mpcli, which holds the Micropub
         * endpoint and token — mdex never sees either.
         */
        private async void publish (string text) {
            revisions.snapshot (text, "publish");
            string output;
            try {
                var proc = new GLib.Subprocess (
                    GLib.SubprocessFlags.STDIN_PIPE
                        | GLib.SubprocessFlags.STDOUT_PIPE
                        | GLib.SubprocessFlags.STDERR_MERGE,
                    "mp", "post", "--stdin", "--extract-title"
                );
                yield proc.communicate_utf8_async (text, null, out output, null);
                if (!proc.get_successful ()) {
                    warning ("mp post failed: %s", output);
                    window.show_toast ("Publishing failed");
                    return;
                }
            } catch (GLib.Error e) {
                warning ("could not run mp: %s", e.message);
                window.show_toast ("Publishing failed — is mp installed?");
                return;
            }

            window.show_toast ("Published");

            string? url = first_url (output);
            if (url != null) {
                new Gtk.UriLauncher (url).launch.begin (window, null);
            }
        }

        private string? first_url (string output) {
            try {
                MatchInfo match;
                if (new Regex ("https?://[^\\s]+").match (output, 0, out match)) {
                    return match.fetch (0);
                }
            } catch (GLib.RegexError e) {
                warning ("bad URL pattern: %s", e.message);
            }
            return null;
        }

        private async void on_preview_ready () {
            yield inject_plugins ();
            yield window.build_export_menu ();
        }

        private async void inject_plugins () {
            string dir = Path.build_filename (GLib.Environment.get_user_config_dir (), "mdex", "plugins");
            Dir d;
            try {
                d = Dir.open (dir);
            } catch (GLib.Error e) {
                return; // no plugins directory — nothing to inject
            }

            string? name;
            while ((name = d.read_name ()) != null) {
                if (!name.has_suffix (".js")) {
                    continue;
                }
                string path = Path.build_filename (dir, name);
                string contents;
                try {
                    FileUtils.get_contents (path, out contents);
                } catch (GLib.FileError e) {
                    warning ("could not read plugin %s: %s", path, e.message);
                    continue;
                }
                yield window.preview.inject_plugin (contents);
            }
        }
    }
}

public static int main (string[] args) {
    var app = new Mdex.Application ();
    return app.run (args);
}
