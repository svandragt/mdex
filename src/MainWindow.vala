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
        /** Fired when the user picks a location for a new file; it does not exist yet. */
        public signal void new_requested (GLib.File file);
        /** Fired when the user wants an empty scratch buffer, autosaved to the cache rather than a file. */
        public signal void scratch_requested ();
        /** Fired on every edit, for the Application to debounce into an autosave. */
        public signal void text_changed (string text);
        /** Fired when the user confirms publishing the buffer to their blog. */
        public signal void publish_requested (string text);
        /** Fired when the user asks for a snapshot of the buffer. */
        public signal void snapshot_requested (string text);
        /** Fired after an export lands on the clipboard: a version went out, so it is worth keeping. */
        public signal void export_done (string text);
        /** Fired when the user opens the revisions window. */
        public signal void revisions_requested (string text);

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

            var scratch_button = new Gtk.Button.from_icon_name ("document-new-symbolic") {
                tooltip_text = "New scratch",
            };
            scratch_button.clicked.connect (() => scratch_requested ());
            header.pack_start (scratch_button);

            var new_button = new Gtk.Button.from_icon_name ("document-save-as-symbolic") {
                tooltip_text = "New file…",
            };
            new_button.clicked.connect (on_new_clicked);
            header.pack_start (new_button);

            var open_button = new Gtk.Button.from_icon_name ("document-open-symbolic") {
                tooltip_text = "Open…",
            };
            open_button.clicked.connect (on_open_clicked);
            header.pack_start (open_button);

            var revisions_button = new Gtk.Button.from_icon_name ("document-open-recent-symbolic") {
                tooltip_text = "Revisions…",
            };
            revisions_button.clicked.connect (() => revisions_requested (editor.get_text ()));
            header.pack_start (revisions_button);

            export_button = new Gtk.MenuButton () {
                label = "Export",
                tooltip_text = "Export",
                sensitive = false,
            };
            header.pack_end (export_button);

            // pack_end stacks right to left, so this lands left of Export.
            // Without mp there is nothing to publish through, so the button
            // stays hidden rather than offering an action that can only fail.
            var publish_button = new Gtk.Button.from_icon_name ("document-send-symbolic") {
                tooltip_text = "Publish to blog",
                visible = GLib.Environment.find_program_in_path ("mp") != null,
            };
            publish_button.clicked.connect (confirm_publish);
            header.pack_end (publish_button);

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
            var new_action = new SimpleAction ("new", null);
            new_action.activate.connect (() => on_new_clicked ());
            edit_actions.add_action (new_action);
            var open_action = new SimpleAction ("open", null);
            open_action.activate.connect (() => on_open_clicked ());
            edit_actions.add_action (open_action);
            var scratch_action = new SimpleAction ("scratch", null);
            scratch_action.activate.connect (() => scratch_requested ());
            edit_actions.add_action (scratch_action);
            var snapshot_action = new SimpleAction ("snapshot", null);
            snapshot_action.activate.connect (() => snapshot_requested (editor.get_text ()));
            edit_actions.add_action (snapshot_action);
            var revisions_action = new SimpleAction ("revisions", null);
            revisions_action.activate.connect (() => revisions_requested (editor.get_text ()));
            edit_actions.add_action (revisions_action);
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
            application.set_accels_for_action ("edit.new", { "<Control>n" });
            application.set_accels_for_action ("edit.open", { "<Control>o" });
            application.set_accels_for_action ("edit.scratch", { "<Control><Shift>n" });
            application.set_accels_for_action ("edit.snapshot", { "<Control>s" });
            application.set_accels_for_action ("edit.revisions", { "<Control>h" });
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
            title = text + " — Mdex";
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

        private void on_new_clicked () {
            var dialog = new Gtk.FileDialog () {
                title = "New Markdown File",
                initial_name = "untitled.md",
            };
            dialog.save.begin (this, null, (obj, res) => {
                try {
                    var file = dialog.save.end (res);
                    if (file != null) {
                        new_requested (file);
                    }
                } catch (GLib.Error e) {
                    // User cancelled — nothing to create.
                }
            });
        }

        /** Asks where to keep an untitled document; null when the user cancels. */
        public async GLib.File? ask_save_location () {
            var dialog = new Gtk.FileDialog () {
                title = "Save Markdown File",
                initial_name = "untitled.md",
            };
            try {
                return yield dialog.save (this, null);
            } catch (GLib.Error e) {
                return null;
            }
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

        /** Publishing is live and can't be undone, so it asks first. */
        private void confirm_publish () {
            var dialog = new Gtk.AlertDialog ("Publish this post to your blog?") {
                detail = "It goes live immediately. The first line's heading becomes the title.",
                buttons = { "Cancel", "Publish" },
                cancel_button = 0,
                default_button = 1,
            };
            dialog.choose.begin (this, null, (obj, res) => {
                try {
                    if (dialog.choose.end (res) == 1) {
                        publish_requested (editor.get_text ());
                    }
                } catch (GLib.Error e) {
                    // Dismissed — nothing to publish.
                }
            });
        }

        private async void run_export (string id, string label) {
            try {
                string json = yield preview.run (id, editor.get_text ());

                Json.Node? root = null;
                try {
                    var parser = new Json.Parser ();
                    parser.load_from_data (json);
                    root = parser.get_root ();
                } catch (GLib.Error e) {
                    warning ("could not parse export result: %s", e.message);
                    show_toast ("Export to %s failed".printf (label));
                    return;
                }
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                    warning ("export %s returned no result", id);
                    show_toast ("Export to %s failed".printf (label));
                    return;
                }
                unowned Json.Object obj = root.get_object ();
                if (!obj.has_member ("text")) {
                    warning ("export %s returned no text", id);
                    show_toast ("Export to %s failed".printf (label));
                    return;
                }
                string text = obj.get_string_member ("text");
                string html = obj.has_member ("html") ? obj.get_string_member ("html") : "";

                var clipboard = Gdk.Display.get_default ().get_clipboard ();
                if (html != "") {
                    // Slack's composer parses pasted plain text as markdown unreliably, so
                    // offer the HTML flavour first for targets that accept rich text.
                    var html_provider = new Gdk.ContentProvider.for_bytes ("text/html", new GLib.Bytes (html.data));
                    var text_value = GLib.Value (typeof (string));
                    text_value.set_string (text);
                    var text_provider = new Gdk.ContentProvider.for_value (text_value);
                    var union = new Gdk.ContentProvider.union ({ html_provider, text_provider });
                    clipboard.set_content (union);
                } else {
                    clipboard.set_text (text);
                }
                show_toast ("Copied %s to clipboard".printf (label));
                export_done (editor.get_text ());
            } catch (GLib.Error e) {
                warning ("export %s failed: %s", id, e.message);
                show_toast ("Export to %s failed".printf (label));
            }
        }
    }
}
