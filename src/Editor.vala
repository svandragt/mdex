namespace Mdex {
    /**
     * Left-hand pane: a GtkSourceView markdown editor.
     */
    public class Editor : Gtk.Box {
        public GtkSource.View view;
        public GtkSource.Buffer buffer;

        private Gtk.SearchBar search_bar;
        private Gtk.SearchEntry search_entry;
        private GtkSource.SearchContext search;

        public signal void text_changed ();
        /** The search selected the nth (1-based) occurrence of text. */
        public signal void match_selected (string text, int n);

        construct {
            orientation = Gtk.Orientation.VERTICAL;
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
            search = new GtkSource.SearchContext (buffer, new GtkSource.SearchSettings () {
                wrap_around = true,
            });
            search_entry = new Gtk.SearchEntry () { hexpand = true };
            // Typing extends the current match; Enter and Ctrl+G move past it.
            search_entry.search_changed.connect (() => {
                search.settings.search_text = search_entry.text;
                find (true, false);
            });
            search_entry.activate.connect (() => find (true, true));
            search_entry.next_match.connect (() => find (true, true));
            var entry_keys = new Gtk.EventControllerKey ();
            entry_keys.key_pressed.connect ((keyval, keycode, state) => {
                if (keyval == Gdk.Key.Return && (state & Gdk.MODIFIER_MASK) == Gdk.ModifierType.SHIFT_MASK) {
                    find (false, true);
                    return true;
                }
                return false;
            });
            search_entry.add_controller (entry_keys);

            search_bar = new Gtk.SearchBar () {
                child = search_entry,
                show_close_button = true,
            };
            search_bar.connect_entry (search_entry);
            search_bar.bind_property ("search-mode-enabled", search, "highlight", BindingFlags.SYNC_CREATE);
            search_bar.notify["search-mode-enabled"].connect (() => {
                if (!search_bar.search_mode_enabled) {
                    view.grab_focus ();
                }
            });

            append (search_bar);
            append (scrolled);

            hexpand = true;
            vexpand = true;

            buffer.changed.connect (() => text_changed ());

            // Pasted text gets the same reflow as opened text. This runs before the
            // class handler (RUN_LAST), so stopping emission replaces the default paste.
            view.paste_clipboard.connect (() => {
                GLib.Signal.stop_emission_by_name (view, "paste-clipboard");
                var clipboard = view.get_clipboard ();
                clipboard.read_text_async.begin (null, (obj, res) => {
                    try {
                        string? text = clipboard.read_text_async.end (res);
                        if (text == null) {
                            return;
                        }
                        buffer.begin_user_action ();
                        if (buffer.has_selection && is_url (text)) {
                            wrap_selection ("[", "](" + text.strip () + ")");
                        } else {
                            buffer.delete_selection (true, view.editable);
                            buffer.insert_at_cursor (unwrap (text), -1);
                        }
                        buffer.end_user_action ();
                        view.scroll_mark_onscreen (buffer.get_insert ());
                    } catch (GLib.Error e) {
                        // Nothing textual on the clipboard.
                    }
                });
            });

            var keys = new Gtk.EventControllerKey ();
            keys.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            keys.key_pressed.connect (on_key_pressed);
            view.add_controller (keys);

            update_style_scheme (Granite.Settings.get_default ().prefers_color_scheme
                == Granite.Settings.ColorScheme.DARK);
        }

        private bool on_key_pressed (uint keyval, uint keycode, Gdk.ModifierType state) {
            if ((state & Gdk.MODIFIER_MASK) != Gdk.ModifierType.CONTROL_MASK) {
                return false;
            }
            switch (keyval) {
                case Gdk.Key.b: wrap_selection ("**", "**"); return true;
                case Gdk.Key.i: wrap_selection ("_", "_"); return true;
                case Gdk.Key.l: wrap_selection ("[", "]()", 1); return true;
                case Gdk.Key.f: start_search (); return true;
            }
            if (keyval >= Gdk.Key.@0 && keyval <= Gdk.Key.@6) {
                set_heading ((int) (keyval - Gdk.Key.@0));
                return true;
            }
            return false;
        }

        /**
         * Wraps the selection (or an empty span at the cursor) in before/after
         * and leaves the cursor `back` characters before the end of `after`,
         * which also puts an empty wrap's cursor between the markers.
         */
        private void wrap_selection (string before, string after, int back = 0) {
            Gtk.TextIter start, end;
            buffer.get_selection_bounds (out start, out end);
            string inner = buffer.get_text (start, end, false);
            buffer.begin_user_action ();
            buffer.delete (ref start, ref end);
            buffer.insert (ref start, before + inner + after, -1);
            start.backward_chars (inner == "" ? after.length : back);
            buffer.place_cursor (start);
            buffer.end_user_action ();
        }

        /** Opens the search bar, seeded with a one-line selection. */
        private void start_search () {
            string? selected = get_selected_text ();
            if (selected != null && !selected.contains ("\n")) {
                search_entry.text = selected;
            }
            search_bar.search_mode_enabled = true;
            search_entry.grab_focus ();
        }

        /**
         * Selects the next match in the given direction and scrolls to it.
         * `skip_current` starts past the current selection; otherwise the
         * search starts at its start, so a match that still fits stays put.
         */
        private void find (bool forward, bool skip_current) {
            search_entry.remove_css_class ("error");
            if (search_entry.text == "") {
                return;
            }
            Gtk.TextIter start, end, match_start, match_end;
            buffer.get_selection_bounds (out start, out end);
            bool wrapped;
            bool found = forward
                ? search.forward (skip_current ? end : start, out match_start, out match_end, out wrapped)
                : search.backward (start, out match_start, out match_end, out wrapped);
            if (!found) {
                search_entry.add_css_class ("error");
                return;
            }
            buffer.select_range (match_start, match_end);
            view.scroll_to_iter (match_start, 0.1, false, 0, 0);
            match_selected (search_entry.text, occurrence_number (match_start));
        }

        /**
         * Counts matches from the buffer start up to `match_start`. Not
         * get_occurrence_position (): it returns -1 until the background
         * scan finishes, which is mid-typing.
         */
        private int occurrence_number (Gtk.TextIter match_start) {
            Gtk.TextIter iter, s, e;
            buffer.get_start_iter (out iter);
            bool wrapped;
            int n = 0;
            while (search.forward (iter, out s, out e, out wrapped) && !wrapped
                   && s.compare (match_start) <= 0) {
                n++;
                iter = e;
            }
            return n;
        }

        /** Sets the cursor line's ATX heading level; 0 removes it. */
        private void set_heading (int level) {
            Gtk.TextIter start;
            buffer.get_iter_at_mark (out start, buffer.get_insert ());
            start.set_line_offset (0);
            var end = start;
            if (!end.ends_line ()) {
                end.forward_to_line_end ();
            }
            string line = buffer.get_text (start, end, false);
            string rest = line;
            try {
                rest = new Regex ("^#{1,6}\\s*").replace (line, -1, 0, "");
            } catch (RegexError e) {
                // pattern is constant
            }
            buffer.begin_user_action ();
            buffer.delete (ref start, ref end);
            buffer.insert (ref start, (level > 0 ? string.nfill (level, '#') + " " : "") + rest, -1);
            buffer.end_user_action ();
        }

        private static bool is_url (string text) {
            string t = text.strip ();
            return (t.has_prefix ("http://") || t.has_prefix ("https://")) && !Regex.match_simple ("\\s", t);
        }

        public string get_text () {
            Gtk.TextIter start, end;
            buffer.get_bounds (out start, out end);
            return buffer.get_text (start, end, false);
        }

        /** Returns the selected text, or null when nothing is selected. */
        public string? get_selected_text () {
            Gtk.TextIter start, end;
            if (!buffer.get_selection_bounds (out start, out end)) {
                return null;
            }
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
         * underlines, HTML blocks, footnote and link reference definitions).
         */
        private enum LineKind {
            TEXT,
            LIST,
            QUOTE,
            TERMINAL,
        }

        /**
         * Joins hard-wrapped paragraph lines into one line each. Fenced and
         * indented code, headings, tables, thematic breaks/setext underlines,
         * HTML blocks and footnote/link reference definitions are left
         * untouched, list items and block quotes absorb their
         * lazy-continuation lines, and a trailing hard break (two+ spaces or
         * a backslash) stops a join.
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
            if (Regex.match_simple ("^\\[[^\\]]+\\]:", rest)) {
                return LineKind.TERMINAL; // footnote or link reference definition
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
