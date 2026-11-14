namespace Mdex {
    /**
     * Right-hand pane: a WebKit view whose page does all markdown parsing,
     * rendering and exporting in JS. Vala only drives the `window.mdex` bridge.
     */
    public class Preview : WebKit.WebView {
        private bool loaded = false;
        private bool render_in_flight = false;
        private string? pending_md = null;
        private uint debounce_id = 0;

        /** The page asks to comment on this selection of the rendered text, which is this occurrence of the quote in it. */
        public signal void comment_requested (string quote, int occurrence);
        /** The page's highlight of this comment was clicked. */
        public signal void comment_opened (string id);
        /** A render replaced the page content, which wipes the comment marks. */
        public signal void rendered ();

        public Preview () {
            // WebKit only makes its own manager after construct{} has run, and the handler below needs one now.
            Object (user_content_manager: new WebKit.UserContentManager ());
        }

        construct {
            hexpand = true;
            vexpand = true;

            // The page's only message handler, so every message that arrives is its own.
            // The vapi forbids a null world; WebKit reads it as the page's own world, where window.webkit lives.
            string? page_world = null;
            user_content_manager.register_script_message_handler ("mdex", page_world);
            user_content_manager.script_message_received.connect (on_message);

            // The shell page is the whole preview; following a link inside it
            // would replace the renderer. Hand real URLs to the browser.
            decide_policy.connect ((decision, type) => {
                if (type != WebKit.PolicyDecisionType.NAVIGATION_ACTION
                    && type != WebKit.PolicyDecisionType.NEW_WINDOW_ACTION) {
                    return false;
                }
                var action = ((WebKit.NavigationPolicyDecision) decision).get_navigation_action ();
                // Only load_shell's own load may navigate without a click. After it, a navigation such as a
                // document's meta refresh would replace the shell with a page that has no policy.
                if (!loaded) {
                    return false;
                }
                decision.ignore ();
                string uri = action.get_request ().get_uri ();
                if (action.get_navigation_type () != WebKit.NavigationType.LINK_CLICKED || !is_openable (uri)) {
                    return true;
                }
                try {
                    AppInfo.launch_default_for_uri (uri, null);
                } catch (GLib.Error e) {
                    warning ("could not open %s: %s", uri, e.message);
                }
                return true;
            });
        }

        /** Whether a clicked link may be handed to the system. Anything else, such as javascript: or file:, is dropped. */
        public static bool is_openable (string uri) {
            string? scheme = GLib.Uri.peek_scheme (uri);
            return scheme == "http" || scheme == "https" || (scheme == "mailto" && mailto_keys_allowed (uri));
        }

        /**
         * A mail client attaches the local file that some keys in the mailto: query name, such as attach or insert, so
         * only the keys of a plain message pass. The query is split by hand, on & only, because a strict parser refuses
         * ordinary links such as ?subject=50% off. Values are not inspected.
         */
        private static bool mailto_keys_allowed (string uri) {
            int start = uri.index_of_char ('?');
            if (start < 0) {
                return true;
            }
            foreach (string segment in uri.substring (start + 1).split ("&")) {
                if (segment == "") {
                    continue;
                }
                int equals = segment.index_of_char ('=');
                string? key = GLib.Uri.unescape_string (equals < 0 ? segment : segment.substring (0, equals));
                if (key == null || !strv_contains ({ "to", "cc", "bcc", "subject", "body" }, key.ascii_down ())) {
                    return false;
                }
            }
            return true;
        }

        /** The page can post anything, so a message that is not a comment on a non-empty quote or an open of a non-empty id is dropped. */
        private void on_message (JSC.Value value) {
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (value.to_json (0));
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                    return;
                }
                var message = root.get_object ();
                string? type = text_member (message, "type");
                string? quote = text_member (message, "quote");
                string? id = text_member (message, "id");
                var count = message.get_member ("occurrence");
                int64 occurrence = count != null && count.get_value_type () == typeof (int64) ? count.get_int () : 1;
                if (type == "comment" && quote != null && quote.strip () != "") {
                    comment_requested (quote, (int) occurrence.clamp (1, int.MAX));
                } else if (type == "open" && id != null && id != "") {
                    comment_opened (id);
                }
            } catch (GLib.Error e) {
                warning ("unreadable message from the page: %s", e.message);
            }
        }

        private static string? text_member (Json.Object message, string name) {
            var node = message.get_member (name);
            return node != null && node.get_value_type () == typeof (string) ? node.get_string () : null;
        }

        /** Assembles shell.html from the gresource bundle and loads it once. A call after the shell has loaded does nothing. */
        public async void load_shell () throws GLib.Error {
            if (loaded) {
                return;
            }
            string marked = resource_string ("/com/github/svandragt/mdex/web/marked.min.js");
            string css = resource_string ("/com/github/svandragt/mdex/web/github-markdown.css");
            string exporters =
                resource_string ("/com/github/svandragt/mdex/web/exporters/github.js") + "\n" +
                resource_string ("/com/github/svandragt/mdex/web/exporters/slack.js") + "\n" +
                resource_string ("/com/github/svandragt/mdex/web/exporters/adf.js");
            // The nonce goes in before the bundles, so a {{NONCE}} inside one stays literal. A new one per load.
            string shell = resource_string ("/com/github/svandragt/mdex/web/shell.html")
                .replace ("{{NONCE}}", GLib.Uuid.string_random ().replace ("-", ""));

            string html = shell
                .replace ("/*{{MARKED_JS}}*/", marked)
                .replace ("/*{{EXPORTERS_JS}}*/", exporters)
                .replace ("/*{{GITHUB_CSS}}*/", css);

            ulong handler = 0;
            handler = load_changed.connect ((event) => {
                if (event == WebKit.LoadEvent.FINISHED) {
                    disconnect (handler);
                    load_shell.callback ();
                }
            });
            load_html (html, null);
            yield;

            loaded = true;
            if (pending_md != null) {
                do_render.begin ();
            }
        }

        private static string resource_string (string path) throws GLib.Error {
            var bytes = GLib.resources_lookup_data (path, GLib.ResourceLookupFlags.NONE);
            uint8[] data = bytes.get_data ();
            data += 0;
            return (string) data;
        }

        /** Debounced entry point for the editor: coalesces rapid keystrokes. */
        public void queue_render (string md) {
            pending_md = md;
            if (debounce_id != 0) {
                return;
            }
            debounce_id = GLib.Timeout.add (150, () => {
                debounce_id = 0;
                do_render.begin ();
                return GLib.Source.REMOVE;
            });
        }

        private async void do_render () {
            if (!loaded || render_in_flight || pending_md == null) {
                return;
            }
            string md = pending_md;
            pending_md = null;
            render_in_flight = true;
            yield render (md);
            render_in_flight = false;
        }

        public async void render (string md) {
            var b = new GLib.VariantBuilder (new GLib.VariantType ("a{sv}"));
            b.add ("{sv}", "md", new GLib.Variant.string (md));
            try {
                yield call_async_javascript_function (
                    "return window.mdex.render(md);", -1, b.end (), null, null, null);
            } catch (GLib.Error e) {
                warning ("render failed: %s", e.message);
            }
            rendered ();
        }

        /**
         * Marks each comment's effective quote in the page and returns whether it was found. Empty until the page has loaded, or if the call fails.
         * A marked passage shows the comment, and the reply under it, as its tooltip, and a click on it fires comment_opened.
         */
        public async bool[] mark_quotes (Comment[] comments) {
            bool[] found = {};
            if (!loaded) {
                return found;
            }
            var list = new Json.Builder ();
            list.begin_array ();
            foreach (var c in comments) {
                string title = c.body;
                if ((c.reply ?? "").strip () != "") {
                    title += "\n↳ " + c.reply;
                }
                list.begin_object ();
                list.set_member_name ("id");
                list.add_string_value (c.id);
                list.set_member_name ("quote");
                list.add_string_value (c.effective_quote ());
                list.set_member_name ("occurrence");
                list.add_int_value (c.effective_occurrence ());
                list.set_member_name ("title");
                list.add_string_value (title);
                list.end_object ();
            }
            list.end_array ();
            var b = new GLib.VariantBuilder (new GLib.VariantType ("a{sv}"));
            b.add ("{sv}", "items", new GLib.Variant.string (Json.to_string (list.get_root (), false)));
            try {
                var result = yield call_async_javascript_function (
                    "return JSON.stringify(window.mdex.markQuotes(JSON.parse(items)));", -1, b.end (), null, null, null);
                var parser = new Json.Parser ();
                parser.load_from_data (result.to_string ());
                foreach (unowned Json.Node flag in parser.get_root ().get_array ().get_elements ()) {
                    found += flag.get_boolean ();
                }
            } catch (GLib.Error e) {
                warning ("mark_quotes failed: %s", e.message);
                found = {};
            }
            return found;
        }

        /** Scrolls the page to the first piece of the nth (1-based) occurrence of quote, which may span bold, links or line breaks. Returns whether it was found. */
        public async bool reveal_quote (string quote, int n) {
            bool found = false;
            if (!loaded) {
                return found;
            }
            var b = new GLib.VariantBuilder (new GLib.VariantType ("a{sv}"));
            b.add ("{sv}", "quote", new GLib.Variant.string (quote));
            b.add ("{sv}", "n", new GLib.Variant.int32 (n));
            try {
                var result = yield call_async_javascript_function (
                    "return window.mdex.revealQuote(quote, n);", -1, b.end (), null, null, null);
                found = result.to_boolean ();
            } catch (GLib.Error e) {
                warning ("reveal_quote failed: %s", e.message);
            }
            return found;
        }

        /** Selects and scrolls to the nth (1-based) occurrence of text. */
        public async void reveal (string text, int n) {
            var b = new GLib.VariantBuilder (new GLib.VariantType ("a{sv}"));
            b.add ("{sv}", "text", new GLib.Variant.string (text));
            b.add ("{sv}", "n", new GLib.Variant.int32 (n));
            try {
                yield call_async_javascript_function (
                    "return window.mdex.reveal(text, n);", -1, b.end (), null, null, null);
            } catch (GLib.Error e) {
                warning ("reveal failed: %s", e.message);
            }
        }

        /** Returns the exporter list as a JSON string, or "[]" on error. */
        public async string list () {
            try {
                var result = yield call_async_javascript_function (
                    "return window.mdex.list();", -1, null, null, null, null);
                return result.to_string ();
            } catch (GLib.Error e) {
                warning ("list failed: %s", e.message);
                return "[]";
            }
        }

        public async string run (string id, string md) throws GLib.Error {
            var b = new GLib.VariantBuilder (new GLib.VariantType ("a{sv}"));
            b.add ("{sv}", "id", new GLib.Variant.string (id));
            b.add ("{sv}", "md", new GLib.Variant.string (md));
            var result = yield call_async_javascript_function (
                "return window.mdex.run(id, md);", -1, b.end (), null, null, null);
            return result.to_string ();
        }

        public async void set_theme (bool dark) {
            // WebKit's argument vardict rejects GVariant booleans outright, so marshal
            // as a string and coerce in JS instead.
            var b = new GLib.VariantBuilder (new GLib.VariantType ("a{sv}"));
            b.add ("{sv}", "dark", new GLib.Variant.string (dark ? "true" : ""));
            try {
                yield call_async_javascript_function (
                    "return window.mdex.setTheme(!!dark);", -1, b.end (), null, null, null);
            } catch (GLib.Error e) {
                warning ("set_theme failed: %s", e.message);
            }
        }

        /** Injects a user plugin. A broken plugin must not take the app down. */
        public async void inject_plugin (string js) {
            try {
                yield evaluate_javascript (js, -1, null, null, null);
            } catch (GLib.Error e) {
                warning ("plugin injection failed: %s", e.message);
            }
        }
    }
}
