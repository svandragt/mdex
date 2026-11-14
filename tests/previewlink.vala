// Checks which links a click in the preview may open. A document can link to
// anything, and the launcher hands the URI to whatever program handles its
// scheme, so only web links and mail links with the keys of a plain message go through.
//
// Preview.is_openable is a static string function, so no widget is built and
// the test needs no display.

private int failures = 0;

private void check (string uri, bool want) {
    if (Mdex.Preview.is_openable (uri) == want) {
        print ("ok   %s\n", uri == "" ? "(empty)" : uri);
        return;
    }
    failures++;
    print ("FAIL %s should be %s\n", uri == "" ? "(empty)" : uri, want ? "openable" : "refused");
}

public static int main (string[] args) {
    check ("https://x", true);
    check ("HTTP://x", true);
    check ("mailto:a@b", true);
    check ("mailto:a@b?", true);
    check ("mailto:a@b?subject=hi&body=x", true);
    check ("mailto:a@b?subject=50% off", true);
    check ("mailto:a@b?cc=c@d;e@f", true);
    check ("mailto:a@b?subject=Hi; all", true);
    check ("mailto:a@b?subject", true);
    check ("mailto:a@b?SUBJECT=x", true);
    check ("mailto:a@b?subject=attach", true);
    check ("mailto:a@b?%73ubject=x", true);
    // The ; is part of the subject, so the only key is subject.
    check ("mailto:a@b?subject=x;attach=/x", true);
    // So is the #y, and a # with no query holds no key.
    check ("mailto:a@b?subject=x#y", true);
    check ("mailto:a@b#frag", true);

    // Mail clients attach the file that some keys name, so only the keys of a plain message are allowed.
    check ("mailto:a@b?attach=/etc/passwd", false);
    check ("mailto:a@b?subject=x&ATTACH=/etc/passwd", false);
    check ("mailto:a@b?attachment=/x", false);
    check ("mailto:a@b?%61ttach=/etc/passwd", false);
    check ("mailto:a@b?insert=/x", false);
    check ("mailto:a@b?subject=x&insert=/x", false);
    check ("mailto:a@b?%20attach=/x", false);
    check ("mailto:a@b?subject=x#&attach=/etc/passwd", false);
    check ("mailto:a@b?subject=x#y&attach=/x", false);

    check ("javascript:alert(1)", false);
    check ("file:///etc/passwd", false);
    check ("data:text/html,x", false);
    check ("", false);
    check ("x", false);

    return failures == 0 ? 0 : 1;
}
