// Checks the parsers that turn `herdr pane get` and `herdr workspace get` output into a window's session name.
//
// The fixtures are real herdr output. Anything else herdr might print (nothing, an error, another shape)
// must give null, so the window keeps the title "<file> — Mdex" instead of a half-built name.

private int failures = 0;

private void check (string name, bool ok) {
    print ("%s %s\n", ok ? "ok  " : "FAIL", name);
    if (!ok) {
        failures++;
    }
}

private const string PANE = """{"id":"cli:pane:get","result":{"pane":{"agent":"claude","agent_status":"idle","cwd":"/home/me/.herdr/worktrees/notes-repo/.42-release-notes","focused":false,"foreground_cwd":"/home/me/.herdr/worktrees/notes-repo/.42-release-notes","pane_id":"wFW:p1","revision":5,"scroll":{"max_offset_from_bottom":0,"offset_from_bottom":0,"viewport_rows":55},"tab_id":"wFW:t1","terminal_id":"term_0000000000000000","terminal_title":"✳ 42","terminal_title_stripped":"42","workspace_id":"wFW"},"type":"pane_info"}}
""";

private const string WORKSPACE = """{"id":"cli:workspace:get","result":{"type":"workspace_info","workspace":{"active_tab_id":"wFW:t1","agent_status":"idle","focused":false,"label":"42 release notes","number":13,"pane_count":1,"tab_count":1,"workspace_id":"wFW","worktree":{"checkout_path":"/home/me/.herdr/worktrees/notes-repo/.42-release-notes","is_linked_worktree":true,"repo_key":"/home/me/dev/notes-repo/.git","repo_name":"notes-repo","repo_root":"/home/me/dev/notes-repo"}}}}
""";

public static int main (string[] args) {
    check ("the workspace id is read from a pane", Mdex.Herdr.workspace_id (PANE) == "wFW");
    check ("the name is the number and the label", Mdex.Herdr.workspace_name (WORKSPACE) == "13 · 42 release notes");

    foreach (string bad in new string[] {
        "",
        "not json",
        "[]",
        "{}",
        "{\"result\":{}}",
        "{\"error\":{\"code\":\"pane_not_found\"}}",
    }) {
        check ("no workspace id from %s".printf (bad == "" ? "nothing" : bad), Mdex.Herdr.workspace_id (bad) == null);
        check ("no name from %s".printf (bad == "" ? "nothing" : bad), Mdex.Herdr.workspace_name (bad) == null);
    }

    check ("a pane with no workspace id gives none", Mdex.Herdr.workspace_id (PANE.replace ("\"workspace_id\":\"wFW\"", "\"x\":1")) == null);
    check ("a workspace id that is not text gives none", Mdex.Herdr.workspace_id (PANE.replace ("\"wFW\"}", "7}")) == null);
    check ("a workspace with no number gives no name", Mdex.Herdr.workspace_name (WORKSPACE.replace ("\"number\":13", "\"x\":1")) == null);
    check ("a workspace with no label gives no name", Mdex.Herdr.workspace_name (WORKSPACE.replace ("\"label\":\"42 release notes\"", "\"x\":1")) == null);
    check ("an empty label gives no name", Mdex.Herdr.workspace_name (WORKSPACE.replace ("42 release notes\",\"number", "\",\"number")) == null);
    check ("a number that is not a number gives no name", Mdex.Herdr.workspace_name (WORKSPACE.replace ("\"number\":13", "\"number\":\"13\"")) == null);

    return failures == 0 ? 0 : 1;
}
