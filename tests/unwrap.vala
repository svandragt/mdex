// Checks Editor.unwrap, which reflows hard-wrapped paragraphs.
//
// The rules it encodes are easy to break by accident: a setext underline joined
// onto its heading silently turns that heading into a paragraph, and a line
// joined into a code block corrupts the code. Both look fine until someone
// reads the output.

private int failures = 0;

private void check (string name, string source, string expected) {
    string actual = Mdex.Editor.unwrap (source);
    if (actual == expected) {
        print ("ok   %s\n", name);
        return;
    }
    failures++;
    print ("FAIL %s\n  expected: %s\n  actual:   %s\n",
           name, expected.escape (), actual.escape ());
}

public static int main (string[] args) {
    // Paragraphs reflow.
    check ("paragraph", "A para that\nwraps.\n", "A para that wraps.\n");

    // Lists and quotes take lazy continuations, keeping their own indent.
    check ("bullet", "- A bullet that is\nwrapped.\n", "- A bullet that is wrapped.\n");
    check ("nested bullet", "  - Nested that\nwraps.\n", "  - Nested that wraps.\n");
    check ("ordered item", "1. First that\nwraps.\n", "1. First that wraps.\n");
    check ("blockquote", "> line one\n> line two\n", "> line one line two\n");

    // Separate blocks stay separate.
    check ("adjacent bullets", "- one\n- two\n", "- one\n- two\n");
    check ("bullet then heading", "- item\n# Heading\n", "- item\n# Heading\n");
    check ("thematic break", "Text.\n\n---\n\nMore.\n", "Text.\n\n---\n\nMore.\n");

    // The cases that corrupt the document if the rule slips.
    check ("setext underline", "Heading text\n===\n", "Heading text\n===\n");
    check ("fenced code", "```\nsome prose line\nanother line\n```\n",
                          "```\nsome prose line\nanother line\n```\n");
    check ("indented code", "    code line\n    next line\n",
                            "    code line\n    next line\n");
    check ("table", "| a | b |\n| - | - |\n", "| a | b |\n| - | - |\n");

    // Two trailing spaces are a deliberate break, not a wrap.
    check ("hard break", "line one  \nline two\n", "line one  \nline two\n");

    print (failures == 0 ? "\nall passed\n" : "\n%d failed\n", failures);
    return failures == 0 ? 0 : 1;
}
