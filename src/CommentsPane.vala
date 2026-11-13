namespace Mdex {
    /**
     * Right-hand pane: the review comments on the open document, open ones
     * first, with the buttons that change a comment's status or body.
     */
    public class CommentsPane : Gtk.Box {
        private delegate void Click ();

        /** Fired after a button here wrote the sidecar, so the window can re-mark the preview. */
        public signal void changed ();
        /** A row was clicked; the preview should show this occurrence of the comment's effective quote. */
        public signal void quote_activated (string quote, int occurrence);

        private Comments? comments = null;
        private string? path = null;
        // Effective quotes of the open comments the preview could not find; null until it has said.
        private Gee.Set<string>? missing = null;
        private Gtk.Box rows;
        private Gtk.Expander? closed = null;
        // What the rows were built from. Refreshes run after every render and every sidecar write,
        // so an unchanged one must keep the rows, or an open expander and an edit in progress would reset.
        private string? shown = null;

        construct {
            orientation = Gtk.Orientation.VERTICAL;
            width_request = 320;
            rows = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
                margin_top = 8,
                margin_bottom = 8,
                margin_start = 8,
                margin_end = 8,
            };
            append (new Gtk.ScrolledWindow () {
                child = rows,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vexpand = true,
            });
        }

        /** Shows the comments in the sidecar at path; null is no document. */
        public void use (string? path) {
            this.path = path;
            comments = path != null ? new Comments (path) : null;
            shown = null;
            refresh ();
        }

        /** Rereads the sidecar. lost holds the effective quotes of open comments the preview could not find. */
        public void refresh (Gee.Set<string>? lost = null) {
            show_comments (comments != null ? comments.list () : new Gee.ArrayList<Comment> (), lost);
        }

        /** Shows comments the caller has just read from the sidecar, so a refresh that already holds them reads nothing. Null is a sidecar that cannot be read. */
        public void show_comments (Gee.List<Comment>? items, Gee.Set<string>? lost = null) {
            missing = lost;
            bool broken = items == null;

            var sig = new StringBuilder (broken ? path : "");
            if (!broken) {
                foreach (var c in items) {
                    sig.append_printf ("|%s|%s|%s|%s|%d|%s|%s|%d", c.id, c.status, c.quote, c.effective_quote (), c.effective_occurrence (), c.body, c.reply ?? "", is_missing (c) ? 1 : 0);
                }
            }
            if (sig.str == shown) {
                return;
            }
            shown = sig.str;

            bool keep_open = closed != null && closed.expanded;
            closed = null;
            for (var child = rows.get_first_child (); child != null; child = rows.get_first_child ()) {
                rows.remove (child);
            }

            if (broken) {
                rows.append (line ("The comments file cannot be read: " + path));
                return;
            }
            if (items.is_empty) {
                rows.append (line ("No comments. Select text in the preview and press C."));
                return;
            }

            var done = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            int done_count = 0;
            foreach (var c in items) {
                if (c.status == "open") {
                    rows.append (build_row (c));
                } else {
                    done.append (build_row (c));
                    done_count++;
                }
            }
            if (done_count > 0) {
                closed = new Gtk.Expander ("Resolved and dismissed (%d)".printf (done_count)) {
                    child = done,
                    expanded = keep_open,
                };
                rows.append (closed);
            }
        }

        /** Focuses the row of the open comment with this id, which scrolls it into view; an id with no such row does nothing. */
        public void select (string id) {
            for (var child = rows.get_first_child (); child != null; child = child.get_next_sibling ()) {
                if (child.name == id) {
                    child.grab_focus ();
                    // A click in the preview leaves the focus ring hidden, and the ring is how the row shows up.
                    var window = get_root () as Gtk.Window;
                    if (window != null) {
                        window.focus_visible = true;
                    }
                    if (child.get_height () == 0) {
                        // A pane shown a moment ago has no layout until its first frame, so focus had nothing to scroll to.
                        var row = child;
                        row.add_tick_callback (() => {
                            if (row.get_height () == 0) {
                                return GLib.Source.CONTINUE;
                            }
                            (row.get_ancestor (typeof (Gtk.Viewport)) as Gtk.Viewport).scroll_to (row, null);
                            return GLib.Source.REMOVE;
                        });
                    }
                    return;
                }
            }
        }

        private bool is_missing (Comment c) {
            return c.status == "open" && missing != null && c.effective_quote () in missing;
        }

        private Gtk.Label line (string text) {
            return new Gtk.Label (text) {
                xalign = 0,
                wrap = true,
                wrap_mode = Pango.WrapMode.WORD_CHAR,
                css_classes = { "dim-label" },
            };
        }

        private Gtk.Widget build_row (Comment c) {
            string id = c.id;
            string quote = c.quote;
            string target = c.effective_quote ();
            int target_occurrence = c.effective_occurrence ();
            bool open = c.status == "open";
            bool answered = (c.reply ?? "").strip () != "";

            var inner = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                margin_top = 8,
                margin_bottom = 8,
                margin_start = 8,
                margin_end = 8,
            };
            inner.append (new Gtk.Label (quote) {
                xalign = 0,
                wrap = true,
                lines = 2,
                ellipsize = Pango.EllipsizeMode.END,
                tooltip_text = quote,
                css_classes = { "dim-label" },
            });
            if (is_missing (c)) {
                inner.append (new Gtk.Label ("Text changed") {
                    xalign = 0,
                    css_classes = { "warning" },
                });
            }
            var body = new Gtk.Label (c.body) {
                xalign = 0,
                wrap = true,
            };
            inner.append (body);
            if (answered) {
                inner.append (new Gtk.Label (c.reply) {
                    xalign = 0,
                    wrap = true,
                    margin_start = 12,
                });
            }

            if (open) {
                var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
                buttons.append (button ("Resolve", () => set_status (id, "resolved")));
                buttons.append (button ("Dismiss", () => set_status (id, "dismissed")));
                if (!answered) {
                    var entry = new Gtk.Entry () {
                        visible = false,
                    };
                    entry.activate.connect (() => {
                        comments.edit (id, entry.text);
                        refresh (missing);
                        changed ();
                    });
                    var keys = new Gtk.EventControllerKey ();
                    keys.key_pressed.connect ((val) => {
                        if (val != Gdk.Key.Escape) {
                            return false;
                        }
                        entry.visible = false;
                        body.visible = true;
                        return true;
                    });
                    entry.add_controller (keys);
                    inner.append (entry);
                    buttons.append (button ("Edit", () => {
                        entry.text = body.label;
                        body.visible = false;
                        entry.visible = true;
                        entry.grab_focus ();
                        entry.set_position (-1);
                    }));
                }
                inner.append (buttons);
            }

            var row = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                name = id,
                focusable = true,
                css_classes = { "card" },
            };
            row.append (inner);
            var click = new Gtk.GestureClick ();
            click.pressed.connect (() => quote_activated (target, target_occurrence));
            row.add_controller (click);
            return row;
        }

        private Gtk.Button button (string label, owned Click action) {
            var b = new Gtk.Button.with_label (label);
            b.clicked.connect (() => action ());
            return b;
        }

        private void set_status (string id, string status) {
            comments.set_status (id, status);
            refresh (missing);
            changed ();
        }
    }
}
