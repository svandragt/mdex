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

        /**
         * A non-blank line falls into one of these once fences are handled
         * separately. TEXT is ordinary paragraph content. LIST and QUOTE are
         * "continuable" block starts: CommonMark's lazy continuation lets a
         * following plain-text line belong to them, and to whatever already
         * joined onto them. TERMINAL block starts never absorb a follow-on
         * line (headings, indented code, tables, thematic breaks/setext
         * underlines, HTML blocks).
         */
        private enum LineKind {
            TEXT,
            LIST,
            QUOTE,
            TERMINAL,
        }

        /**
         * Joins hard-wrapped paragraph lines into one line each. Fenced and
         * indented code, headings, tables, thematic breaks/setext underlines
         * and HTML blocks are left untouched, list items and block quotes
         * absorb their lazy-continuation lines, and a trailing hard break
         * (two+ spaces or a backslash) stops a join.
         */
        public static string unwrap (string text) {
            bool trailing_newline = text.has_suffix ("\n");
            string[] raw_lines = text.split ("\n");
            if (trailing_newline) {
                raw_lines = raw_lines[0:raw_lines.length - 1];
            }

            var out_lines = new Gee.ArrayList<string> ();
            bool fenced = false;
            // True when the last output line can still absorb a join.
            bool prev_joinable = false;
            // True when that joinable line is (or continues) a block quote,
            // the one case where B is allowed to be a block start too.
            bool prev_is_quote = false;

            foreach (string line in raw_lines) {
                bool is_fence = is_fence_line (line);

                if (fenced) {
                    out_lines.add (line);
                    fenced = !is_fence;
                    prev_joinable = false;
                    prev_is_quote = false;
                    continue;
                }

                if (is_fence) {
                    out_lines.add (line);
                    fenced = true;
                    prev_joinable = false;
                    prev_is_quote = false;
                    continue;
                }

                if (line.strip () == "") {
                    out_lines.add (line);
                    prev_joinable = false;
                    prev_is_quote = false;
                    continue;
                }

                LineKind kind = classify_line (line);
                string joined_text = line;
                bool can_join = false;
                if (prev_joinable) {
                    if (kind == LineKind.TEXT) {
                        can_join = true;
                    } else if (kind == LineKind.QUOTE && prev_is_quote) {
                        joined_text = strip_quote_marker (line);
                        can_join = true;
                    }
                }

                if (can_join) {
                    string prev = out_lines[out_lines.size - 1];
                    if (!has_hard_break (prev)) {
                        out_lines[out_lines.size - 1] = prev.chomp () + " " + joined_text;
                        prev_joinable = !has_hard_break (joined_text);
                        // prev_is_quote is unchanged: a TEXT join keeps whatever
                        // kind the chain already had, a QUOTE join keeps quoting.
                        continue;
                    }
                }

                out_lines.add (line);
                prev_joinable = kind != LineKind.TERMINAL;
                prev_is_quote = kind == LineKind.QUOTE;
            }

            string result = string.joinv ("\n", out_lines.to_array ());
            if (trailing_newline) {
                result += "\n";
            }
            return result;
        }

        private static bool has_hard_break (string line) {
            if (line.has_suffix ("\\")) {
                return true;
            }
            int n = line.length;
            int spaces = 0;
            while (spaces < n && line[n - 1 - spaces] == ' ') {
                spaces++;
            }
            return spaces >= 2;
        }

        private static bool is_fence_line (string line) {
            string rest = line.substring (leading_spaces (line, 3));
            return rest.has_prefix ("```") || rest.has_prefix ("~~~");
        }

        /** Strips a block quote's leading marker: up to 3 spaces, '>', one optional space. */
        private static string strip_quote_marker (string line) {
            string rest = line.substring (leading_spaces (line, 3));
            rest = rest.substring (1); // the '>' itself
            if (rest.has_prefix (" ")) {
                rest = rest.substring (1);
            }
            return rest;
        }

        /** Called only on non-blank, non-fence lines. */
        private static LineKind classify_line (string line) {
            // ponytail: 4-space indent means "indented code" even inside a
            // list, so a genuinely indented list continuation is misread as
            // TERMINAL and won't join. A real block-structure parse (tracking
            // each list item's content column) is the upgrade path.
            if (line.has_prefix ("    ") || line.has_prefix ("\t")) {
                return LineKind.TERMINAL; // indented code
            }

            string rest = line.substring (leading_spaces (line, 3));
            if (rest.has_prefix ("|")) {
                return LineKind.TERMINAL; // table row
            }
            if (rest.has_prefix ("<")) {
                return LineKind.TERMINAL; // HTML block
            }
            if (rest.has_prefix (">")) {
                return LineKind.QUOTE;
            }
            if (Regex.match_simple ("^#{1,6}(\\s|$)", rest)) {
                return LineKind.TERMINAL; // ATX heading
            }
            if (Regex.match_simple ("^([-*+] |\\d+[.)] )", rest)) {
                return LineKind.LIST;
            }
            if (Regex.match_simple ("^(?:[-*_] *){3,}$", rest)
                || Regex.match_simple ("^=+ *$", rest)) {
                return LineKind.TERMINAL; // thematic break / setext underline
            }
            return LineKind.TEXT;
        }

        private static int leading_spaces (string line, int max) {
            int n = 0;
            while (n < line.length && n < max && line[n] == ' ') {
                n++;
            }
            return n;
        }
    }
}
