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

        private const string USAGE = """Usage:
  mdex [FILE]     open FILE, or restore the scratch buffer
  ... | mdex      edit piped text as a scratch buffer

Options:
  -h, --help      show this help

""";

        public Application () {
            Object (
                application_id: "com.github.svandragt.mdex",
                flags: ApplicationFlags.HANDLES_COMMAND_LINE
            );
        }

        public override int command_line (ApplicationCommandLine cmdline) {
            string[] args = cmdline.get_arguments ();
            string piped = "";

            if (args.length > 1 && (args[1] == "--help" || args[1] == "-h")) {
                cmdline.print ("%s", USAGE);
                return 0;
            }

            if (window == null) {
                window = new MainWindow (this);
                window.open_requested.connect ((file) => open_file.begin (file));
                window.text_changed.connect (schedule_autosave);
                window.preview_ready.connect (() => on_preview_ready.begin ());
            }

            if (args.length > 1) {
                open_file.begin (GLib.File.new_for_commandline_arg (args[1]));
            } else if (!Posix.isatty (0) && read_stdin_if_any (out piped)) {
                current_file = null;
                window.set_text (Editor.unwrap (piped));
                window.set_subtitle ("Scratch");
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
            window.set_subtitle ("Scratch");

            string contents;
            try {
                FileUtils.get_contents (scratch_file ().get_path (), out contents);
                window.set_text (Editor.unwrap (contents));
            } catch (GLib.FileError e) {
                // No previous scratch session — start empty, nothing to recover.
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

                window.set_text (Editor.unwrap ((string) contents));
                current_file = file;
                current_etag = etag;
                window.set_subtitle (file.get_basename ());
                watch (file);
            } catch (GLib.Error e) {
                warning ("failed to open %s: %s", file.get_path (), e.message);
            }
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

        private void schedule_autosave (string text) {
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
            } catch (GLib.Error e) {
                warning ("autosave to %s failed: %s", target.get_path (), e.message);
            }
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
