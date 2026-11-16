// Checks the criteria pane against plans parsed from text and the quotes the page reports as not found.
//
// It builds widgets, so it needs a display and skips (exit 77) without one.
// Rows are found by their widget name: c<number> for a criterion, g<position> for a Not covered line.

private int failures = 0;

private void check (string name, bool ok) {
    if (ok) {
        print ("ok   %s\n", name);
        return;
    }
    failures++;
    print ("FAIL %s\n", name);
}

private Gee.ArrayList<Gtk.Widget> all (Gtk.Widget root) {
    var found = new Gee.ArrayList<Gtk.Widget> ();
    for (var child = root.get_first_child (); child != null; child = child.get_next_sibling ()) {
        found.add (child);
        found.add_all (all (child));
    }
    return found;
}

private Gtk.Widget? row (Gtk.Widget pane, string name) {
    foreach (var w in all (pane)) {
        if (w.name == name) {
            return w;
        }
    }
    return null;
}

/** How many rows of one kind there are: those whose name is the prefix and a number. */
private int rows_named (Gtk.Widget pane, string prefix) {
    int count = 0;
    foreach (var w in all (pane)) {
        if (w.name.has_prefix (prefix) && w.name.length > prefix.length && w.name.get_char (prefix.length).isdigit ()) {
            count++;
        }
    }
    return count;
}

private bool has_label (Gtk.Widget? where, string text) {
    if (where == null) {
        return false;
    }
    foreach (var w in all (where)) {
        var l = w as Gtk.Label;
        if (l != null && l.label.contains (text)) {
            return true;
        }
    }
    return false;
}

private bool has_warning (Gtk.Widget? where, string text) {
    if (where == null) {
        return false;
    }
    foreach (var w in all (where)) {
        var l = w as Gtk.Label;
        if (l != null && l.label.contains (text) && l.has_css_class ("warning")) {
            return true;
        }
    }
    return false;
}

private Gtk.Button? button (Gtk.Widget where, string label) {
    foreach (var w in all (where)) {
        var b = w as Gtk.Button;
        if (b != null && b.label == label) {
            return b;
        }
    }
    return null;
}

/** Presses the row the way a mouse click does. */
private void click (Gtk.Widget? row) {
    var controllers = row.observe_controllers ();
    for (uint i = 0; i < controllers.get_n_items (); i++) {
        var gesture = controllers.get_item (i) as Gtk.GestureClick;
        if (gesture != null) {
            gesture.pressed (1, 0, 0);
        }
    }
}

private const string PLAN = """## Criteria
1. Lists versions — <q cite="391.ticket.md">lists the versions</q>
2. Path is empty — <q>the next line</q> and <q cite="391.ticket.md">a path</q>
3. Plain behaviour stays — added: existing behaviour, see "Not covered".
4. Fails clearly — <q cite="other.md">gone text</q>

Not covered: <q cite="391.ticket.md">a greeting</q> — it asks for nothing.
Not covered: <q>lost gap</q> — a deliberate gap that is gone.
Not covered: Package "<name>" not found. — no quote on this line.
""";

public static int main (string[] args) {
    if (!Gtk.init_check ()) {
        print ("skip: no display\n");
        return 77;
    }

    var pane = new Mdex.CoveragePane ();
    string? activated = null;
    int activations = 0;
    int plan_requests = 0;
    pane.quote_activated.connect ((quote) => {
        activated = quote;
        activations++;
    });
    pane.plan_requested.connect (() => plan_requests++);

    var plan = Mdex.Coverage.parse (PLAN);
    var lost = new Gee.HashSet<string> ();
    lost.add (Mdex.Coverage.missing_key (2, "the next line"));
    lost.add (Mdex.Coverage.missing_key (4, "gone text"));
    lost.add (Mdex.Coverage.missing_key (0, "lost gap"));
    pane.show_plan (plan, "391.ticket.md", lost);

    check ("one row per criterion", rows_named (pane, "c") == 4);
    check ("a row shows its number and text", has_label (row (pane, "c1"), "1.") && has_label (row (pane, "c1"), "Lists versions"));
    check ("a criterion whose quotes are found says so", has_label (row (pane, "c1"), "Quotes the ticket") && !has_warning (row (pane, "c1"), "not found"));
    check ("a criterion without a <q> is Added", has_label (row (pane, "c3"), "Added") && !has_label (row (pane, "c3"), "Quotes the ticket"));
    check ("an Added criterion is not flagged", !has_warning (row (pane, "c3"), "not found"));
    check ("a missing quote with no cite names the ticket file", has_warning (row (pane, "c2"), "Quote not found in 391.ticket.md: “the next line”"));
    check ("a criterion with a found and a missing quote shows only the missing one", !has_label (row (pane, "c2"), "Quotes the ticket") && !has_warning (row (pane, "c2"), "a path"));
    check ("a missing quote names the file it cites", has_warning (row (pane, "c4"), "Quote not found in other.md: “gone text”"));

    check ("a Not covered section lists each line", has_label (pane, "Not covered") && rows_named (pane, "g") == 3);
    check ("a gap shows its quote and its reason", has_label (row (pane, "g1"), "a greeting") && has_label (row (pane, "g1"), "it asks for nothing."));
    check ("a gap whose quote is missing gets the same warning", has_warning (row (pane, "g2"), "Quote not found in 391.ticket.md: “lost gap”"));
    check ("a gap with no quote shows its reason and no warning", has_label (row (pane, "g3"), "no quote on this line") && !has_warning (row (pane, "g3"), "not found"));

    // A click goes to the criterion's first quote that was found, so a missing first quote is skipped.
    click (row (pane, "c1"));
    check ("a criterion activates its quote", activated == "lists the versions" && activations == 1);
    click (row (pane, "c2"));
    check ("a criterion activates its first found quote", activated == "a path" && activations == 2);
    click (row (pane, "c3"));
    click (row (pane, "c4"));
    check ("an Added criterion and one with every quote missing activate nothing", activations == 2);
    click (row (pane, "g1"));
    check ("a gap with a quote activates it", activated == "a greeting" && activations == 3);
    click (row (pane, "g2"));
    click (row (pane, "g3"));
    check ("a missing gap quote and a gap without one activate nothing", activations == 3);

    // Open plan is always at the top.
    var open = button (pane, "Open plan");
    check ("there is an Open plan button", open != null);
    if (open != null) {
        open.clicked ();
    }
    check ("Open plan asks for the plan", plan_requests == 1);

    // Until the page has said what it found, nothing is flagged.
    pane.show_plan (plan, "391.ticket.md", null);
    check ("with no result from the page nothing is flagged", !has_warning (pane, "not found") && has_label (row (pane, "c4"), "Quotes the ticket"));

    // A refresh with nothing new keeps the rows, so a scroll position and a click in progress survive.
    pane.show_plan (plan, "391.ticket.md", lost);
    var before = row (pane, "c1");
    pane.show_plan (Mdex.Coverage.parse (PLAN), "391.ticket.md", lost);
    check ("an unchanged plan keeps the rows", row (pane, "c1") == before);
    var found_all = new Gee.HashSet<string> ();
    pane.show_plan (plan, "391.ticket.md", found_all);
    check ("a changed result rebuilds them", row (pane, "c1") != before && !has_warning (pane, "not found"));

    // No Criteria section, or no plan.
    pane.show_plan (Mdex.Coverage.parse ("# Approach\n"), "391.ticket.md", found_all);
    check ("a plan with no criteria says so", has_label (pane, "no criteria") && rows_named (pane, "c") == 0 && !has_label (pane, "Not covered"));
    pane.show_plan (null, "391.ticket.md", null);
    check ("no plan shows no rows", rows_named (pane, "c") == 0 && rows_named (pane, "g") == 0 && !has_label (pane, "no criteria"));

    return failures == 0 ? 0 : 1;
}
