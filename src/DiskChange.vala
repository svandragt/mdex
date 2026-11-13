namespace Mdex {
    /** What to do when the open document's file changes on disk. */
    public enum DiskChange {
        /** The disk already holds the editor's text, as after mdex's own autosave. */
        IGNORE,
        /** The editor holds nothing unsaved, so the disk text replaces it. */
        RELOAD,
        /** The editor holds unsaved edits, so the user chooses. */
        ASK;

        public static DiskChange decide (string disk, string editor, string last_saved, bool autosave_pending) {
            if (disk == editor) {
                return IGNORE;
            }
            return !autosave_pending && editor == last_saved ? RELOAD : ASK;
        }
    }
}
