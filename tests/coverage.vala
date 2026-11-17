// Checks Coverage, which reads the criteria out of an approach plan so the
// ticket's preview can show what they cover. The plan sits next to the ticket
// and is found by file name; nothing here touches a file or a widget.
//
// Ticket text is quoted in <q cite="file">…</q>. Double quotes in the plan are
// ordinary prose: they cross-reference other sections and show error messages.

private int failures = 0;

private void check (string name, bool ok) {
    if (ok) {
        print ("ok   %s\n", name);
        return;
    }
    failures++;
    print ("FAIL %s\n", name);
}

private string quotes_of (Mdex.Criterion c) {
    var texts = new string[0];
    foreach (var q in c.quotes) {
        texts += q.text;
    }
    return string.joinv (" | ", texts);
}

public static int main (string[] args) {
    // Pairing is by name: only a ticket file has a plan, and the plan is its sibling without ".ticket".
    check ("x.ticket.md pairs with x.md", Mdex.Coverage.plan_path_for ("/work/x.ticket.md") == "/work/x.md");
    check ("a dotted name keeps its dots", Mdex.Coverage.plan_path_for ("/work/391.v2.ticket.md") == "/work/391.v2.md");
    check ("a plain document has no plan", Mdex.Coverage.plan_path_for ("/work/x.md") == null);
    check ("the suffix is case-sensitive", Mdex.Coverage.plan_path_for ("/work/x.TICKET.md") == null);
    check ("a name that only ends in ticket.md has no plan", Mdex.Coverage.plan_path_for ("/work/myticket.md") == null);
    check ("a file named .ticket.md has no stem to pair", Mdex.Coverage.plan_path_for ("/work/.ticket.md") == null);

    // Numbered items, with one <q> and with several; an item without one is added, and still counts.
    var plan = Mdex.Coverage.parse (
        "# Approach\n\n## Criteria\n\n"
        + "1. `viv show --all` lists the versions — <q cite=\"391.ticket.md\">lists the available versions</q>\n"
        + "2. The path line is empty — <q cite=\"391.ticket.md\">a path</q> and <q>the next line</q>\n"
        + "3. Plain behaviour stays — added: existing behaviour that must not change.\n"
        + "\n## Problem\nignored\n");
    check ("three criteria read", plan.criteria.size == 3);
    check ("number is read", plan.criteria[0].number == 1 && plan.criteria[2].number == 3);
    check ("one quote", quotes_of (plan.criteria[0]) == "lists the available versions");
    check ("two quotes in order", quotes_of (plan.criteria[1]) == "a path | the next line");
    check ("a quote keeps its cite", plan.criteria[0].quotes[0].cite == "391.ticket.md" && plan.criteria[1].quotes[0].cite == "391.ticket.md");
    check ("a quote with no cite has none", plan.criteria[1].quotes[1].cite == null);
    check ("an added criterion has no quote", plan.criteria[2].quotes.size == 0);
    check ("the text shows the quote in curly quotes, the tags gone",
        plan.criteria[0].text == "`viv show --all` lists the versions — “lists the available versions”");
    check ("every quote of a criterion is shown", plan.criteria[1].text == "The path line is empty — “a path” and “the next line”");
    check ("an added criterion shows its whole text", plan.criteria[2].text == "Plain behaviour stays — added: existing behaviour that must not change.");
    check ("no gaps", plan.gaps.size == 0);

    // The cite takes single or double attribute quotes; the quote's entities are decoded once, and its text is kept as written.
    plan = Mdex.Coverage.parse ("## Criteria\n1. Does it — <q cite='a.md'>x &lt;y&gt; &amp;lt; &quot;z&quot; &#39;w&#39; `code`</q>\n");
    check ("a single-quoted cite is read", plan.criteria[0].quotes[0].cite == "a.md");
    check ("entities are decoded once, backticks kept", plan.criteria[0].quotes[0].text == "x <y> &lt; \"z\" 'w' `code`");
    plan = Mdex.Coverage.parse ("## Criteria\n1. Does it — <Q CITE = \"b.md\" class=\"c\">cased</q> <q cite=\"\">empty cite</q> <q></q> <q>  </q>\n");
    check ("tag and attribute names are not case-sensitive, other attributes are ignored", plan.criteria[0].quotes[0].text == "cased" && plan.criteria[0].quotes[0].cite == "b.md");
    check ("an empty cite is no cite, and an empty <q> is no quote", quotes_of (plan.criteria[0]) == "cased | empty cite" && plan.criteria[0].quotes[1].cite == null);

    // Double quotes, straight or curly, are prose.
    plan = Mdex.Coverage.parse ("## Criteria\n1. Fails like Package \"<name>\" not found — added: see \"Not covered\" and “curly”.\n");
    check ("double-quoted text is not a quote", plan.criteria[0].quotes.size == 0);
    check ("double-quoted text stays in the criterion's text", plan.criteria[0].text == "Fails like Package \"<name>\" not found — added: see \"Not covered\" and “curly”.");

    // A wrapped item is one item: its quote can run over the line break, and the indent goes.
    plan = Mdex.Coverage.parse (
        "## Criteria\n"
        + "1. First result.\n"
        + "   — <q cite=\"t.md\">lists the available\n   versions from every\n   repository</q>\n"
        + "2. Second.\n");
    check ("wrapped lines join into one item", plan.criteria.size == 2 && plan.criteria[0].number == 1);
    check ("a quote over a line break is one quote", quotes_of (plan.criteria[0]) == "lists the available versions from every repository");

    // Not covered: gives the first <q> and, as the reason, the line's text outside it without the dash that introduced it.
    plan = Mdex.Coverage.parse (
        "## Criteria\n1. One — <q>one</q>\n\n"
        + "Not covered: <q cite=\"t.md\">a greeting</q> — it asks for nothing.\n"
        + "Not covered: <q>two</q> - a hyphen\n  wraps onto a second line, and <q>another</q> stays.\n"
        + "Not covered: Package \"<name>\" not found. — there is no quote here.\n"
        + "Not covered: - a bare reason\n");
    check ("four gaps read in order", plan.gaps.size == 4);
    check ("the first <q> is the gap's quote", plan.gaps[0].quote != null && plan.gaps[0].quote.text == "a greeting" && plan.gaps[0].quote.cite == "t.md");
    check ("the reason loses its dash", plan.gaps[0].reason == "it asks for nothing.");
    check ("a hyphen, a wrapped reason, and a second <q> shown as text",
        plan.gaps[1].quote.text == "two" && plan.gaps[1].reason == "a hyphen wraps onto a second line, and “another” stays.");
    check ("double quotes do not make a gap quote", plan.gaps[2].quote == null);
    check ("a gap without a quote is listed with its text as the reason", plan.gaps[2].reason == "Package \"<name>\" not found. — there is no quote here.");
    check ("a bare reason loses its dash", plan.gaps[3].quote == null && plan.gaps[3].reason == "a bare reason");
    check ("a gap line does not become a criterion", plan.criteria.size == 1);

    // Only the Criteria section is read.
    plan = Mdex.Coverage.parse (
        "1. Before the section — <q>before</q>\n\nNot covered: <q>before gap</q> — no\n\n"
        + "## Criteria\n1. Inside — <q>inside</q>\n\n## Problem\n"
        + "2. After the section — <q>after</q>\n\nNot covered: <q>after gap</q> — no\n");
    check ("text before and after is ignored", plan.criteria.size == 1 && quotes_of (plan.criteria[0]) == "inside" && plan.gaps.size == 0);

    // No section, an empty section, and an empty plan read as nothing.
    plan = Mdex.Coverage.parse ("# Approach\n\n## Problem\n1. Not a criterion — <q>x</q>\n");
    check ("no Criteria section is empty", plan.criteria.size == 0 && plan.gaps.size == 0);
    plan = Mdex.Coverage.parse ("## Criteria\n\n## Problem\n");
    check ("an empty Criteria section is empty", plan.criteria.size == 0 && plan.gaps.size == 0);
    plan = Mdex.Coverage.parse ("");
    check ("an empty plan is empty", plan.criteria.size == 0 && plan.gaps.size == 0);

    // A criterion's number is its position in the list, as the Markdown renders it, not the number the marker is written with.
    plan = Mdex.Coverage.parse ("## Criteria\n1. One — <q>a</q>\n1. Two — <q>b</q>\n1. Three\n\n9. Four\n");
    check ("criteria are numbered by position", plan.criteria.size == 4 && plan.criteria[0].number == 1 && plan.criteria[1].number == 2 && plan.criteria[2].number == 3 && plan.criteria[3].number == 4);

    // Only a line with no indent is a criterion; an indented number is part of the criterion above it. The list's first number is its start, and later ones count on from it.
    plan = Mdex.Coverage.parse ("## Criteria\n1. One — <q>one</q>\n   1. a1\n   2. a2\n2. Two — <q>two</q>\n");
    check ("indented numbered lines are not criteria", plan.criteria.size == 2 && plan.criteria[0].text == "One — “one” 1. a1 2. a2" && plan.criteria[1].number == 2);
    plan = Mdex.Coverage.parse ("## Criteria\n3. A — <q>a</q>\n4. B\n");
    check ("a list that starts at 3 is numbered 3, 4", plan.criteria.size == 2 && plan.criteria[0].number == 3 && plan.criteria[1].number == 4);
    plan = Mdex.Coverage.parse ("## Criteria\n1. A\n1. B\n1. C\n");
    check ("a list of 1. markers counts on from 1", plan.criteria.size == 3 && plan.criteria[0].number == 1 && plan.criteria[1].number == 2 && plan.criteria[2].number == 3);

    // # and ## headings end the section; ### does not. A fence hides its lines, whether it is ``` or ~~~, and a heading inside it is no heading.
    plan = Mdex.Coverage.parse ("## Criteria\n1. One — <q>one</q>\n\n# Next\n2. After — <q>after</q>\n\nNot covered: <q>after gap</q> — no\n");
    check ("a level 1 heading ends the Criteria section", plan.criteria.size == 1 && plan.gaps.size == 0);
    plan = Mdex.Coverage.parse ("## Criteria\n1. One — <q>one</q>\n\n### Notes\n2. Two — <q>two</q>\n");
    check ("a level 3 heading does not", plan.criteria.size == 2);
    plan = Mdex.Coverage.parse (
        "## Criteria\n1. One — <q>one</q>\n\n"
        + "```sh\n# a comment in code\n2. not a criterion — <q>x</q>\nNot covered: <q>y</q> — no\n```\n\n"
        + "  ~~~\n3. nor this — <q>z</q>\n  ~~~\n\n"
        + "2. Two — <q>two</q>\n");
    check ("lines inside a fence are not read, and a # line in it ends nothing", plan.criteria.size == 2 && quotes_of (plan.criteria[1]) == "two" && plan.gaps.size == 0);
    plan = Mdex.Coverage.parse ("```\n## Criteria\n1. In a fence — <q>x</q>\n```\n");
    check ("a Criteria heading in a fence starts nothing", plan.criteria.size == 0);

    // A backtick fence's info string has no backtick, so ```make install``` is inline code. A fence closes on the same character, at least as long as the opener, with nothing after it.
    plan = Mdex.Coverage.parse ("```make install``` runs the build\n\n## Criteria\n1. One — <q>one</q>\n");
    check ("a line of inline code that starts with ``` opens no fence", plan.criteria.size == 1);
    plan = Mdex.Coverage.parse ("## Criteria\n1. One — <q>one</q>\n\n````\n```\n2. inside — <q>x</q>\n````\n\n2. Two — <q>two</q>\n");
    check ("a shorter fence does not close a longer one", plan.criteria.size == 2 && quotes_of (plan.criteria[1]) == "two");
    plan = Mdex.Coverage.parse ("## Criteria\n1. One — <q>one</q>\n\n```\n``` x\n2. inside — <q>x</q>\n```\n\n2. Two — <q>two</q>\n");
    check ("text after a closing fence keeps the fence open", plan.criteria.size == 2 && quotes_of (plan.criteria[1]) == "two");

    // Only a cite attribute names the source, not the end of another name such as data-cite.
    plan = Mdex.Coverage.parse ("## Criteria\n1. Does it — <q data-cite=\"a.md\">one</q> <q data-cite=\"a.md\" cite=\"b.md\">two</q>\n");
    check ("data-cite is not the cite", plan.criteria[0].quotes[0].cite == null);
    check ("a cite after another attribute is read", plan.criteria[0].quotes[1].cite == "b.md");

    // A quote is of the ticket when it cites no file or one with the ticket's name; a quote of another file is not looked up in the ticket.
    plan = Mdex.Coverage.parse (
        "## Criteria\n1. One — <q>bare</q> <q cite=\"391.ticket.md\">named</q> <q cite=\"docs/391.ticket.md\">path</q> <q cite=\"other.md\">other</q> <q cite=\"x391.ticket.md\">suffix</q>\n");
    var ticket_quotes = new string[0];
    foreach (var q in plan.criteria[0].quotes) {
        if (q.is_of ("391.ticket.md")) {
            ticket_quotes += q.text;
        }
    }
    check ("a quote with no cite, the ticket's name or a path to it is of the ticket", string.joinv (" | ", ticket_quotes) == "bare | named | path");

    // The plan names something to cover only if a quote is of the ticket, in a criterion or a Not covered line.
    check ("a quote of the ticket is something", plan.quotes_ticket ("391.ticket.md"));
    plan = Mdex.Coverage.parse ("## Criteria\n1. Added — nothing quoted.\n2. Other — <q cite=\"other.md\">q</q>\n\nNot covered: <q cite=\"other.md\">g</q> — r\nNot covered: a bare reason\n");
    check ("criteria without a ticket quote name nothing", plan.criteria.size == 2 && plan.gaps.size == 2 && !plan.quotes_ticket ("391.ticket.md"));
    plan = Mdex.Coverage.parse ("## Criteria\n1. Added — nothing quoted.\n\nNot covered: <q>g</q> — r\n");
    check ("a Not covered quote of the ticket counts", plan.quotes_ticket ("391.ticket.md"));
    check ("an empty plan names nothing", !Mdex.Coverage.parse ("").quotes_ticket ("391.ticket.md"));

    // The page reports a missing quote by criterion number (0 for a gap) and text; the pane looks it up by the same key.
    check ("a missing quote's key names its criterion", Mdex.Coverage.missing_key (3, "gone") != Mdex.Coverage.missing_key (4, "gone"));
    check ("a gap's key differs from a criterion's", Mdex.Coverage.missing_key (0, "gone") != Mdex.Coverage.missing_key (1, "gone"));
    check ("equal numbers and text give equal keys", Mdex.Coverage.missing_key (3, "gone") == Mdex.Coverage.missing_key (3, "gone"));

    return failures == 0 ? 0 : 1;
}
