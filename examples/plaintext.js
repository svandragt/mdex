// Example mdex plugin: strip markdown down to plain text.
//
// Copy to ~/.config/mdex/plugins/ and restart mdex. "Plain text" then appears
// in the Export menu alongside the built-in formats.
//
// An exporter gets the parsed token stream and the raw source, and returns a
// string. `tokens` is marked's lexer output, so you walk a tree rather than
// pattern-matching the source text.

(function () {
    // Source text is usually hard-wrapped, so newlines inside a paragraph are
    // an artefact of how it was typed, not meaning. Collapse them.
    function flatten (inline) {
        if (!inline) {
            return '';
        }
        return inline.map (function (t) {
            switch (t.type) {
                case 'link':
                    // Keep the URL, since plain text can't carry a hyperlink.
                    return t.text === t.href ? t.href : flatten (t.tokens) + ' (' + t.href + ')';
                case 'image':
                    return t.text ? '[' + t.text + ']' : '';
                case 'br':
                    return ' ';
                case 'codespan':
                    return t.text;
                default:
                    return t.tokens ? flatten (t.tokens) : (t.text || '');
            }
        }).join ('').replace (/\s+/g, ' ').trim ();
    }

    function list (token, depth) {
        const pad = '  '.repeat (depth);
        return token.items.map (function (item, i) {
            const marker = token.ordered ? (token.start || 1) + i + '. ' : '- ';
            const head = pad + marker + flatten (item.tokens.filter (function (t) {
                return t.type !== 'list';
            }).flatMap (function (t) {
                return t.tokens || [t];
            }));
            const nested = item.tokens.filter (function (t) {
                return t.type === 'list';
            }).map (function (t) {
                return list (t, depth + 1);
            });
            return [head].concat (nested).join ('\n');
        }).join ('\n');
    }

    function block (token) {
        switch (token.type) {
            case 'heading':
                return flatten (token.tokens);
            case 'paragraph':
                return flatten (token.tokens);
            case 'list':
                return list (token, 0);
            case 'code':
                return token.text.split ('\n').map (function (l) {
                    return '    ' + l;
                }).join ('\n');
            case 'blockquote':
                return token.tokens.map (block).filter (Boolean).join ('\n\n');
            case 'table':
                return token.rows.map (function (row) {
                    return row.map (function (cell, i) {
                        return flatten (token.header[i].tokens) + ': ' + flatten (cell.tokens);
                    }).join ('\n');
                }).join ('\n\n');
            case 'hr':
                return '---';
            case 'space':
                return '';
            default:
                return flatten (token.tokens) || (token.text || '').trim ();
        }
    }

    window.mdex.registerExporter ('plaintext', 'Plain text', function (tokens) {
        return tokens.map (block).filter (Boolean).join ('\n\n') + '\n';
    });
}) ();
