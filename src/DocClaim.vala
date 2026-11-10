namespace Mdex {
    /**
     * Marks a document as open in this window, so a second launch asks the
     * window to show itself instead of opening another copy.
     *
     * Each open file owns a well-known name on the session bus, derived from
     * its path. Instances are separate processes (NON_UNIQUE), so the bus is
     * the only place they can find each other.
     */
    [DBus (name = "com.github.svandragt.mdex.Doc")]
    public class DocClaim : Object {
        private const string PATH = "/com/github/svandragt/mdex/Doc";
        private const string INTERFACE = "com.github.svandragt.mdex.Doc";
        private const int TIMEOUT_MS = 2000;

        private GLib.DBusConnection? connection = null;
        private uint owner_id = 0;

        /** Fired when another instance asks this window to come forward; the token lets Wayland allow it to take focus. */
        [DBus (visible = false)]
        public signal void present_requested (string token);

        /** The bus name for a document: the path is hashed, as it can hold characters a name may not. */
        public static string bus_name (string path) {
            return "com.github.svandragt.mdex.Doc_" + GLib.Checksum.compute_for_string (GLib.ChecksumType.MD5, path);
        }

        /** Called over D-Bus by the instance that was asked to open this document. */
        public void present (string token) throws GLib.Error {
            present_requested (token);
        }

        /** Claims the name for path and gives up the previous document's. A name another window holds stays theirs; a file without a local path has no name. */
        [DBus (visible = false)]
        public void claim (string? path) {
            release ();
            if (path == null) {
                return;
            }
            try {
                if (connection == null) {
                    connection = Bus.get_sync (BusType.SESSION);
                    connection.register_object (PATH, this);
                }
            } catch (GLib.Error e) {
                warning ("cannot claim %s on the session bus: %s", path, e.message);
                connection = null;
                return;
            }
            owner_id = Bus.own_name_on_connection (connection, bus_name (path), BusNameOwnerFlags.DO_NOT_QUEUE);
        }

        [DBus (visible = false)]
        public void release () {
            if (owner_id != 0) {
                Bus.unown_name (owner_id);
                owner_id = 0;
            }
        }

        /**
         * Asks the window that has path open to come forward. Returns false
         * when none does, and also when the bus can't be reached: the caller
         * then opens the file itself.
         */
        public static bool present_owner (string path, string token) {
            try {
                var bus = Bus.get_sync (BusType.SESSION);
                bus.call_sync (
                    bus_name (path), PATH, INTERFACE, "Present", new Variant ("(s)", token),
                    null, DBusCallFlags.NO_AUTO_START, TIMEOUT_MS
                );
                return true;
            } catch (GLib.Error e) {
                if (!e.matches (GLib.DBusError.quark (), GLib.DBusError.SERVICE_UNKNOWN)
                    && !e.matches (GLib.DBusError.quark (), GLib.DBusError.NAME_HAS_NO_OWNER)) {
                    warning ("cannot ask the window with %s to come forward: %s", path, e.message);
                }
                return false;
            }
        }
    }
}
