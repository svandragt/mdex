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

        construct {
            hexpand = true;
            vexpand = true;
        }

        /** Assembles shell.html from the gresource bundle and loads it once. */
        public async void load_shell () throws GLib.Error {
            string marked = resource_string ("/com/github/svandragt/mdex/web/marked.min.js");
            string css = resource_string ("/com/github/svandragt/mdex/web/github-markdown.css");
            string exporters =
                resource_string ("/com/github/svandragt/mdex/web/exporters/github.js") + "\n" +
                resource_string ("/com/github/svandragt/mdex/web/exporters/slack.js") + "\n" +
                resource_string ("/com/github/svandragt/mdex/web/exporters/adf.js");
            string shell = resource_string ("/com/github/svandragt/mdex/web/shell.html");

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
