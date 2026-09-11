namespace Mdex {
    /**
     * Left-hand pane: a GtkSourceView markdown editor.
     */
    public class Editor : Gtk.Box {
        public GtkSource.View view;
        public GtkSource.Buffer buffer;

        public signal void text_changed ();

        construct {
            buffer = new GtkSource.Buffer (null);

            var lang = GtkSource.LanguageManager.get_default ().get_language ("markdown");
            if (lang != null) {
                buffer.set_language (lang);
            }

            view = new GtkSource.View ();
            view.buffer = buffer;
            view.monospace = true;
            view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            view.top_margin = 12;
            view.bottom_margin = 12;
            view.left_margin = 12;
            view.right_margin = 12;

            var scrolled = new Gtk.ScrolledWindow () {
                child = view,
                hexpand = true,
                vexpand = true,
            };
            append (scrolled);

            hexpand = true;
            vexpand = true;

            buffer.changed.connect (() => text_changed ());

            update_style_scheme (Granite.Settings.get_default ().prefers_color_scheme
                == Granite.Settings.ColorScheme.DARK);
        }

        public string get_text () {
            Gtk.TextIter start, end;
            buffer.get_bounds (out start, out end);
            return buffer.get_text (start, end, false);
        }

        public void set_text (string text) {
            buffer.begin_irreversible_action ();
            buffer.text = text;
            buffer.end_irreversible_action ();
        }

        public void update_style_scheme (bool dark) {
            var manager = GtkSource.StyleSchemeManager.get_default ();
            var scheme = manager.get_scheme (dark ? "Adwaita-dark" : "Adwaita");
            if (scheme != null) {
                buffer.set_style_scheme (scheme);
            }
        }
    }
}
