namespace Mdex {
    /**
     * Names a window after the herdr workspace of the pane that launched it.
     * herdr is optional: every failure here gives null, and the window keeps its plain title.
     */
    public class Herdr : Object {
        private const int TIMEOUT_MS = 2000;

        /** The workspace a pane belongs to, from `herdr pane get` output. */
        public static string? workspace_id (string json) {
            return text_in (info_in (json, "pane"), "workspace_id");
        }

        /** "number · label" from `herdr workspace get` output, as workspaces are shown in herdr. */
        public static string? workspace_name (string json) {
            var workspace = info_in (json, "workspace");
            string? label = text_in (workspace, "label");
            if (workspace == null || label == null || !workspace.has_member ("number")) {
                return null;
            }
            var number = workspace.get_member ("number");
            if (number.get_node_type () != Json.NodeType.VALUE || number.get_value_type () != typeof (int64)) {
                return null;
            }
            return number.get_int ().to_string () + " · " + label;
        }

        /** Looks up the session name for a pane, or null when it has none or herdr takes over 2 seconds. */
        public static async string? session_name (string pane) {
            if (pane == "") {
                return null;
            }
            var cancel = new GLib.Cancellable ();
            uint timeout = 0;
            timeout = GLib.Timeout.add (TIMEOUT_MS, () => {
                timeout = 0;
                cancel.cancel ();
                return GLib.Source.REMOVE;
            });
            string? name = null;
            string? pane_json = yield run ("pane", pane, cancel);
            string? id = pane_json != null ? workspace_id (pane_json) : null;
            if (id != null) {
                string? workspace_json = yield run ("workspace", id, cancel);
                name = workspace_json != null ? workspace_name (workspace_json) : null;
            }
            if (timeout != 0) {
                GLib.Source.remove (timeout);
            }
            return name;
        }

        private static async string? run (string kind, string id, GLib.Cancellable cancel) {
            GLib.Subprocess? proc = null;
            try {
                proc = new GLib.Subprocess (GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_SILENCE, "herdr", kind, "get", id);
                string output;
                yield proc.communicate_utf8_async (null, cancel, out output, null);
                return proc.get_successful () ? output : null;
            } catch (GLib.Error e) {
                // herdr is not installed, or took too long.
                if (proc != null) {
                    proc.force_exit ();
                }
                return null;
            }
        }

        /** The object at result.<key> in herdr's reply, or null when the reply is not shaped that way. */
        private static Json.Object? info_in (string json, string key) {
            var parser = new Json.Parser ();
            try {
                parser.load_from_data (json);
            } catch (GLib.Error e) {
                return null;
            }
            return object_in (object_in (object_of (parser.get_root ()), "result"), key);
        }

        private static Json.Object? object_of (Json.Node? node) {
            return node != null && node.get_node_type () == Json.NodeType.OBJECT ? node.get_object () : null;
        }

        private static Json.Object? object_in (Json.Object? parent, string key) {
            return parent != null && parent.has_member (key) ? object_of (parent.get_member (key)) : null;
        }

        /** A non-empty string member, or null. */
        private static string? text_in (Json.Object? parent, string key) {
            if (parent == null || !parent.has_member (key)) {
                return null;
            }
            var node = parent.get_member (key);
            if (node.get_node_type () != Json.NodeType.VALUE || node.get_value_type () != typeof (string)) {
                return null;
            }
            string text = node.get_string ();
            return text != "" ? text : null;
        }
    }
}
