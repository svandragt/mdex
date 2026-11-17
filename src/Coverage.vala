namespace Mdex {
    /** A phrase of ticket text that a plan quotes in <q cite="file">…</q>. */
    public class Quote : Object {
        public string text = "";
        /** The file the quote is copied from, when the plan names one. */
        public string? cite = null;

        /** Whether the quote is of the ticket called ticket_name: it cites no file, or a file with that name. */
        public bool is_of (string ticket_name) {
            return cite == null || Path.get_basename (cite) == ticket_name;
        }
    }

    /** One numbered criterion of a plan, and the ticket text it quotes. */
    public class Criterion : Object {
        public int number = 0;
        /** The item as shown to a reader: its quotes in curly double quotes, the <q> tags gone. It is also the tooltip on the quoted text. */
        public string text = "";
        public Gee.List<Quote> quotes = new Gee.ArrayList<Quote> ();
    }

    /** A Not covered line: ticket text a plan leaves out on purpose, and why. */
    public class Gap : Object {
        /** The line's first <q>; null for a line that quotes nothing, which is listed but marks nothing. */
        public Quote? quote = null;
        public string reason = "";
    }

    /**
     * What an approach plan says it covers of its ticket, read from the plan's
     * Criteria section: each numbered item with the <q> elements it holds, and
     * each Not covered line. Double-quoted text is prose, not a quote. Matching
     * the quotes to the ticket's text happens in the preview page.
     */
    public class Coverage : Object {
        private const string TICKET_SUFFIX = ".ticket.md";
        private const string GAP_PREFIX = "Not covered:";

        private static Regex quote_re;
        private static Regex cite_re;
        private static Regex item_re;
        private static Regex space_re;
        private static Regex dash_re;

        static construct {
            try {
                quote_re = new Regex ("<q\\b([^>]*)>(.*?)</q>", RegexCompileFlags.CASELESS);
                cite_re = new Regex ("(?<=\\s)cite\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')", RegexCompileFlags.CASELESS);
                item_re = new Regex ("^\\d+[.)]\\s+");
                space_re = new Regex ("\\s+");
                dash_re = new Regex ("^[\\s\\-–—]+");
            } catch (RegexError e) {
                error ("bad pattern: %s", e.message);
            }
        }

        public Gee.List<Criterion> criteria = new Gee.ArrayList<Criterion> ();
        public Gee.List<Gap> gaps = new Gee.ArrayList<Gap> ();

        /** Whether the plan quotes the ticket called ticket_name, in a criterion or a Not covered line. */
        public bool quotes_ticket (string ticket_name) {
            foreach (var c in criteria) {
                foreach (var q in c.quotes) {
                    if (q.is_of (ticket_name)) {
                        return true;
                    }
                }
            }
            foreach (var g in gaps) {
                if (g.quote != null && g.quote.is_of (ticket_name)) {
                    return true;
                }
            }
            return false;
        }

        /** The plan that goes with a ticket file, or null when the name does not say it is a ticket: x.ticket.md pairs with x.md. Case-sensitive, as the approach skill writes the name. */
        public static string? plan_path_for (string ticket_path) {
            if (!ticket_path.has_suffix (TICKET_SUFFIX) || Path.get_basename (ticket_path) == TICKET_SUFFIX) {
                return null;
            }
            return ticket_path.substring (0, ticket_path.length - TICKET_SUFFIX.length) + ".md";
        }

        /** Reads the criteria and gaps from a plan's text. A plan without a Criteria section gives none. */
        public static Coverage parse (string plan_text) {
            var plan = new Coverage ();
            bool in_criteria = false;
            // The opening run of ``` or ~~~ of the code fence being read, whose lines are not the plan's.
            string? fence = null;
            // The numbered item or Not covered paragraph being read, its lines joined by single spaces.
            string? block = null;
            foreach (string raw in plan_text.split ("\n")) {
                string line = raw.strip ();
                if (fence != null) {
                    if (line.length >= fence.length && line.replace (fence.substring (0, 1), "") == "") {
                        fence = null;
                    }
                } else if ((fence = fence_opener (line)) != null) {
                    continue;
                } else if (line.has_prefix ("# ") || line.has_prefix ("## ")) {
                    plan.add (block);
                    block = null;
                    in_criteria = line.has_prefix ("## ") && line.substring (3).strip () == "Criteria";
                } else if (!in_criteria) {
                    continue;
                } else if (line == "") {
                    plan.add (block);
                    block = null;
                } else if (line.has_prefix (GAP_PREFIX) || Regex.match_simple ("^\\d+[.)]\\s", raw)) {
                    plan.add (block);
                    block = line;
                } else if (block != null) {
                    block += " " + line;
                }
            }
            plan.add (block);
            return plan;
        }

        /** The run of three or more ` or ~ that opens a code fence on line, or null. A backtick fence's info string has no backtick, so "```make install```" is inline code. */
        private static string? fence_opener (string line) {
            if (!line.has_prefix ("```") && !line.has_prefix ("~~~")) {
                return null;
            }
            int length = 0;
            while (length < line.length && line[length] == line[0]) {
                length++;
            }
            if (line[0] == '`' && line.substring (length).contains ("`")) {
                return null;
            }
            return line.substring (0, length);
        }

        /** What the page reports for a quote it could not find, and what the pane looks it up by; number is 0 for a Not covered quote. */
        public static string missing_key (int number, string quote) {
            return "%d\n%s".printf (number, quote);
        }

        private void add (string? block) {
            if (block == null) {
                return;
            }
            try {
                if (block.has_prefix (GAP_PREFIX)) {
                    string text = block.substring (GAP_PREFIX.length);
                    Quote? quote = null;
                    string rest = text;
                    MatchInfo match;
                    if (quote_re.match (text, 0, out match)) {
                        do {
                            quote = quote_of (match);
                            if (quote != null) {
                                int start;
                                int end;
                                match.fetch_pos (0, out start, out end);
                                rest = text.substring (0, start) + " " + text.substring (end);
                                break;
                            }
                        } while (match.next ());
                    }
                    string reason = dash_re.replace_literal (plain (rest), -1, 0, "");
                    if (quote != null || reason != "") {
                        gaps.add (new Gap () { quote = quote, reason = reason });
                    }
                    return;
                }
                string text = item_re.replace_literal (block, -1, 0, "");
                var criterion = new Criterion () {
                    // As Markdown numbers a list: the first marker's number, then one more for each item.
                    number = criteria.is_empty ? int.parse (block) : criteria.last ().number + 1,
                    text = plain (text),
                };
                MatchInfo match;
                if (quote_re.match (text, 0, out match)) {
                    do {
                        Quote? quote = quote_of (match);
                        if (quote != null) {
                            criterion.quotes.add (quote);
                        }
                    } while (match.next ());
                }
                criteria.add (criterion);
            } catch (RegexError e) {
                warning ("cannot read the plan's criteria: %s", e.message);
            }
        }

        /** The quote a <q> match holds, or null for an empty one. Its entities are decoded once. */
        private static Quote? quote_of (MatchInfo match) {
            string text = collapse (decode (match.fetch (2)));
            if (text == "") {
                return null;
            }
            string? cite = null;
            // The match info points into the string it was run on, so that string must outlive it.
            string attributes = match.fetch (1);
            MatchInfo attribute;
            if (cite_re.match (attributes, 0, out attribute)) {
                cite = collapse (decode ((attribute.fetch (1) ?? "") + (attribute.fetch (2) ?? "")));
            }
            return new Quote () { text = text, cite = cite != "" ? cite : null };
        }

        /** text as a reader sees it: every <q> as its quote in curly double quotes, whitespace collapsed. */
        private static string plain (string text) throws RegexError {
            return collapse (quote_re.replace_eval (text, -1, 0, 0, (match, result) => {
                string quote = collapse (decode (match.fetch (2)));
                result.append (quote != "" ? "“" + quote + "”" : "");
                return false;
            }));
        }

        private static string collapse (string text) {
            try {
                return space_re.replace_literal (text, -1, 0, " ").strip ();
            } catch (RegexError e) {
                return text.strip ();
            }
        }

        // The ampersand goes last, so &amp;lt; comes out as &lt; and not <.
        private static string decode (string text) {
            return text.replace ("&lt;", "<").replace ("&gt;", ">").replace ("&quot;", "\"").replace ("&#39;", "'").replace ("&amp;", "&");
        }
    }
}
