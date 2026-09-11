namespace Mdex {
    /**
     * Window chrome: header bar, editor/preview split pane, export menu,
     * theme follow. File I/O, autosave, CLI input and plugin scanning live
     * in Application; this class only drives the UI and the JS bridge.
     */
    public class MainWindow : Gtk.ApplicationWindow {
        public Editor editor;
        public Preview preview;

        private Gtk.MenuButton export_button;
        private Gtk.Label subtitle_label;
        private Gtk.Overlay overlay;
        private SimpleActionGroup export_actions;

        /** Fired once the preview has loaded shell.html and the bridge is live. */
        public signal void preview_ready ();
        /** Fired when the user picks a file to open via the header button. */
        public signal void open_requested (GLib.File file);
        /** Fired on every edit, for the Application to debounce into an autosave. */
        public signal void text_changed (string text);

        public MainWindow (Gtk.Application app) {
            Object (application: app);
        }

        construct {
            default_width = 1100;
            default_height = 720;
            // Wayland matches the app id to the .desktop file for this, but X11
            // needs it stated.
            icon_name = "com.github.svandragt.mdex";

            var title_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                valign = Gtk.Align.CENTER,
            };
            var title_label = new Gtk.Label ("Mdex") {
                css_classes = { "title" },
            };
            subtitle_label = new Gtk.Label ("Scratch") {
                css_classes = { "subtitle", "dim-label" },
            };
            title_box.append (title_label);
            title_box.append (subtitle_label);

            var header = new Gtk.HeaderBar () {
                title_widget = title_box,
            };

            var open_button = new Gtk.Button.from_icon_name ("document-open-symbolic") {
                tooltip_text = "Open…",
            };
            open_button.clicked.connect (on_open_clicked);
            header.pack_start (open_button);

            export_button = new Gtk.MenuButton () {
                label = "Export",
                tooltip_text = "Export",
                sensitive = false,
            };
            header.pack_end (export_button);

            set_titlebar (header);

            editor = new Editor ();
            preview = new Preview ();

            var paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL) {
                start_child = editor,
                end_child = preview,
                resize_start_child = true,
                resize_end_child = true,
                shrink_start_child = false,
                shrink_end_child = false,
            };

            overlay = new Gtk.Overlay () {
                child = paned,
            };
            set_child (overlay);

            paned.position = default_width / 2;

            editor.text_changed.connect (() => {
                string text = editor.get_text ();
                preview.queue_render (text);
                text_changed (text);
            });

            export_actions = new SimpleActionGroup ();
            insert_action_group ("export", export_actions);

            var edit_actions = new SimpleActionGroup ();
            var unwrap_action = new SimpleAction ("unwrap", null);
            unwrap_action.activate.connect (() => do_unwrap ());
            edit_actions.add_action (unwrap_action);
            insert_action_group ("edit", edit_actions);

            Granite.Settings.get_default ().notify["prefers-color-scheme"].connect (update_theme);
            sync_local_theme ();
            preview_ready.connect (update_theme);

            init_preview.begin ();
        }

        private async void init_preview () {
            try {
                yield preview.load_shell ();
            } catch (GLib.Error e) {
                warning ("failed to load preview shell: %s", e.message);
                return;
            }
            // "application" isn't set until after construct{} returns (it's
            // not a construct property), so the accel has to wait until here,
            // once the yield above has actually suspended past construction.
            application.set_accels_for_action ("edit.unwrap", { "<Control><Shift>u" });
            preview_ready ();
        }

        public string get_text () {
            return editor.get_text ();
        }

        public void set_text (string text) {
            editor.set_text (text);
            preview.queue_render (text);
        }

        public void set_subtitle (string text) {
            subtitle_label.label = text;
        }

        public void show_toast (string title) {
            var toast = new Granite.Toast (title);
            overlay.add_overlay (toast);
            toast.send_notification ();
        }

        private bool is_dark () {
            return Granite.Settings.get_default ().prefers_color_scheme
                == Granite.Settings.ColorScheme.DARK;
        }

        private void sync_local_theme () {
            bool dark = is_dark ();
            Gtk.Settings.get_default ().gtk_application_prefer_dark_theme = dark;
            editor.update_style_scheme (dark);
        }

        /** Also pushes the theme into the preview — only safe once the page has loaded. */
        private void update_theme () {
            sync_local_theme ();
            preview.set_theme.begin (is_dark ());
        }

        /** Rewrites the buffer with unwrapped text, as one undo step. */
        private void do_unwrap () {
            Gdk.Rectangle visible;
            editor.view.get_visible_rect (out visible);
            Gtk.TextIter top_iter;
            editor.view.get_iter_at_location (out top_iter, visible.x, visible.y);
            int top_line = top_iter.get_line ();

            editor.buffer.begin_user_action ();
            editor.buffer.text = Editor.unwrap (editor.get_text ());
            editor.buffer.end_user_action ();

            Gtk.TextIter scroll_iter;
            editor.buffer.get_iter_at_line (out scroll_iter, top_line);
            editor.view.scroll_to_iter (scroll_iter, 0, false, 0, 0);
        }

        private void on_open_clicked () {
            var dialog = new Gtk.FileDialog () {
                title = "Open Markdown File",
            };
            dialog.open.begin (this, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file != null) {
                        open_requested (file);
                    }
                } catch (GLib.Error e) {
                    // User cancelled, or the picker failed — nothing to recover.
                }
            });
        }

        /** Builds the export menu from window.mdex.list(). Call after plugins are injected. */
        public async void build_export_menu () {
            string json = yield preview.list ();

            Json.Node? root = null;
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (json);
                root = parser.get_root ();
            } catch (GLib.Error e) {
                warning ("could not parse exporter list: %s", e.message);
                return;
            }
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) {
                return;
            }

            var menu = new GLib.Menu ();
            foreach (unowned Json.Node item in root.get_array ().get_elements ()) {
                unowned Json.Object obj = item.get_object ();
                string id = obj.get_string_member ("id");
                string label = obj.get_string_member ("label");

                var action = new SimpleAction (id, null);
                action.activate.connect (() => run_export.begin (id, label));
                export_actions.add_action (action);

                menu.append (label, "export." + id);

                string? accel = accel_for_id (id);
                if (accel != null) {
                    application.set_accels_for_action ("export." + id, { accel });
                }
            }

            export_button.menu_model = menu;
            export_button.sensitive = true;
        }

        private string? accel_for_id (string id) {
            switch (id) {
                case "github":
                    return "<Control><Shift>g";
                case "slack":
                    return "<Control><Shift>s";
                case "adf":
                    return "<Control><Shift>j";
                default:
                    return null;
            }
        }

        private async void run_export (string id, string label) {
            try {
                string result = yield preview.run (id, editor.get_text ());
                Gdk.Display.get_default ().get_clipboard ().set_text (result);
                show_toast ("Copied %s to clipboard".printf (label));
            } catch (GLib.Error e) {
                warning ("export %s failed: %s", id, e.message);
                show_toast ("Export to %s failed".printf (label));
            }
        }
    }
}
