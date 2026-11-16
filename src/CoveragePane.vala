namespace Mdex {
    /**
     * Pane of a ticket window: the criteria of the plan beside the ticket, each
     * with whether it quotes the ticket, then the plan's Not covered lines.
     */
    public class CoveragePane : Gtk.Box {
        /** A row was clicked; the preview should show the first occurrence of this quote. */
        public signal void quote_activated (string quote);
        /** Open plan was pressed. */
        public signal void plan_requested ();

        private Gtk.Box rows;
        // What the rows were built from. Refreshes run after every render and every plan change,
        // so an unchanged one must keep the rows, or the scroll position would reset.
        private string? shown = null;

        construct {
            orientation = Gtk.Orientation.VERTICAL;
            width_request = 320;
            var open = new Gtk.Button.with_label ("Open plan") {
                halign = Gtk.Align.START,
                margin_top = 8,
                margin_start = 8,
                margin_end = 8,
            };
            open.clicked.connect (() => plan_requested ());
            append (open);
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

        /**
         * Shows the criteria and Not covered lines of plan; null is no plan. ticket_name is where a quote
         * that cites no file was looked for. lost holds the Coverage.missing_key of each quote the preview
         * could not find; null until it has said, when nothing is flagged.
         */
        public void show_plan (Coverage? plan, string ticket_name, Gee.Set<string>? lost = null) {
            var sig = new StringBuilder (ticket_name);
            if (plan != null) {
                sig.append ("|plan");
                foreach (var c in plan.criteria) {
                    sig.append_printf ("|%d|%s", c.number, c.text);
                    foreach (var q in c.quotes) {
                        sig.append_printf ("|%s|%s|%d", q.text, q.cite ?? "", is_missing (lost, c.number, q) ? 1 : 0);
                    }
                }
                foreach (var g in plan.gaps) {
                    sig.append_printf ("|gap|%s|%s|%d", g.reason, g.quote != null ? g.quote.text : "", g.quote != null && is_missing (lost, 0, g.quote) ? 1 : 0);
                }
            }
            if (sig.str == shown) {
                return;
            }
            shown = sig.str;

            for (var child = rows.get_first_child (); child != null; child = rows.get_first_child ()) {
                rows.remove (child);
            }
            if (plan == null) {
                return;
            }
            if (plan.criteria.is_empty && plan.gaps.is_empty) {
                rows.append (note ("The plan has no criteria. Add a Criteria section."));
                return;
            }
            foreach (var c in plan.criteria) {
                rows.append (criterion_row (c, ticket_name, lost));
            }
            if (!plan.gaps.is_empty) {
                var heading = new Gtk.Label ("Not covered") {
                    xalign = 0,
                    margin_top = 8,
                    attributes = new Pango.AttrList (),
                };
                heading.attributes.insert (Pango.attr_weight_new (Pango.Weight.BOLD));
                rows.append (heading);
                int position = 0;
                foreach (var g in plan.gaps) {
                    position++;
                    rows.append (gap_row (position, g, ticket_name, lost));
                }
            }
        }

        private static bool is_missing (Gee.Set<string>? lost, int number, Quote quote) {
            return lost != null && Coverage.missing_key (number, quote.text) in lost;
        }

        private Gtk.Label note (string text, string css = "dim-label") {
            return new Gtk.Label (text) {
                xalign = 0,
                wrap = true,
                wrap_mode = Pango.WrapMode.WORD_CHAR,
                css_classes = { css },
            };
        }

        private static string not_found (Quote quote, string ticket_name) {
            return "Quote not found in %s: “%s”".printf (quote.cite ?? ticket_name, quote.text);
        }

        private Gtk.Widget criterion_row (Criterion c, string ticket_name, Gee.Set<string>? lost) {
            var inner = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                margin_top = 8,
                margin_bottom = 8,
                margin_start = 8,
                margin_end = 8,
            };
            inner.append (new Gtk.Label ("%d. %s".printf (c.number, c.text)) {
                xalign = 0,
                wrap = true,
                wrap_mode = Pango.WrapMode.WORD_CHAR,
            });
            string? target = null;
            bool flagged = false;
            foreach (var q in c.quotes) {
                if (is_missing (lost, c.number, q)) {
                    inner.append (note (not_found (q, ticket_name), "warning"));
                    flagged = true;
                } else if (target == null) {
                    target = q.text;
                }
            }
            if (c.quotes.is_empty) {
                inner.append (note ("Added"));
            } else if (!flagged) {
                inner.append (note ("Quotes the ticket"));
            }
            return row ("c%d".printf (c.number), inner, target);
        }

        private Gtk.Widget gap_row (int position, Gap g, string ticket_name, Gee.Set<string>? lost) {
            var inner = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                margin_top = 8,
                margin_bottom = 8,
                margin_start = 8,
                margin_end = 8,
            };
            string? target = null;
            if (g.quote != null) {
                inner.append (note ("“%s”".printf (g.quote.text)));
                if (is_missing (lost, 0, g.quote)) {
                    inner.append (note (not_found (g.quote, ticket_name), "warning"));
                } else {
                    target = g.quote.text;
                }
            }
            if (g.reason != "") {
                inner.append (note (g.reason));
            }
            return row ("g%d".printf (position), inner, target);
        }

        /** A card that sends target to the preview when clicked; with no target, a click does nothing. */
        private Gtk.Widget row (string name, Gtk.Widget inner, string? target) {
            var card = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                name = name,
                css_classes = { "card" },
            };
            card.append (inner);
            if (target != null) {
                var click = new Gtk.GestureClick ();
                click.pressed.connect (() => quote_activated (target));
                card.add_controller (click);
            }
            return card;
        }
    }
}
