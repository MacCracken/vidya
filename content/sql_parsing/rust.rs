// Vidya — SQL Parsing in Rust
//
// Idiomatic shape: enum tokens + `match`. The tokenizer walks the byte
// slice with a `pos` cursor, classifies each lexeme into a `TokenKind`,
// and stores a slice of the original input as the token text. Keywords
// are matched case-insensitively by uppercasing during comparison.
// Mirrors the cyrius.cyr reference: SELECT/FROM/WHERE keywords, IDENT,
// INT, single-char operators (* = ( ) ,), and EOF.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum TokenKind {
    Eof,
    Ident,
    Int,
    Star,
    Eq,
    LParen,
    RParen,
    Comma,
    Select,
    From,
    Where,
}

#[derive(Debug, Clone)]
struct Token<'a> {
    kind: TokenKind,
    text: &'a str,
}

fn is_alpha(c: u8) -> bool {
    c.is_ascii_alphabetic() || c == b'_'
}

fn is_alnum(c: u8) -> bool {
    is_alpha(c) || c.is_ascii_digit()
}

fn classify_keyword(text: &str) -> TokenKind {
    // Case-insensitive keyword check via uppercase comparison.
    let up: String = text.chars().map(|c| c.to_ascii_uppercase()).collect();
    match up.as_str() {
        "SELECT" => TokenKind::Select,
        "FROM" => TokenKind::From,
        "WHERE" => TokenKind::Where,
        _ => TokenKind::Ident,
    }
}

fn tokenize(sql: &str) -> Vec<Token<'_>> {
    let bytes = sql.as_bytes();
    let mut pos = 0usize;
    let mut out: Vec<Token<'_>> = Vec::new();

    while pos < bytes.len() {
        let c = bytes[pos];
        if c == b' ' || c == b'\t' || c == b'\n' || c == b'\r' {
            pos += 1;
            continue;
        }

        if is_alpha(c) {
            let start = pos;
            while pos < bytes.len() && is_alnum(bytes[pos]) {
                pos += 1;
            }
            let text = &sql[start..pos];
            out.push(Token {
                kind: classify_keyword(text),
                text,
            });
            continue;
        }

        if c.is_ascii_digit() {
            let start = pos;
            while pos < bytes.len() && bytes[pos].is_ascii_digit() {
                pos += 1;
            }
            out.push(Token {
                kind: TokenKind::Int,
                text: &sql[start..pos],
            });
            continue;
        }

        let kind = match c {
            b'*' => TokenKind::Star,
            b'=' => TokenKind::Eq,
            b'(' => TokenKind::LParen,
            b')' => TokenKind::RParen,
            b',' => TokenKind::Comma,
            _ => {
                pos += 1;
                continue;
            }
        };
        out.push(Token {
            kind,
            text: &sql[pos..pos + 1],
        });
        pos += 1;
    }

    out.push(Token {
        kind: TokenKind::Eof,
        text: "",
    });
    out
}

/// Minimal SELECT validator: returns true if the token stream looks like
/// SELECT <cols> FROM <ident> [WHERE <ident> = <val>].
fn is_valid_select(toks: &[Token<'_>]) -> bool {
    if toks.is_empty() || toks[0].kind != TokenKind::Select {
        return false;
    }
    // Find FROM
    let from_idx = toks.iter().position(|t| t.kind == TokenKind::From);
    let Some(i) = from_idx else { return false };
    if i == 1 {
        return false; // need at least one column between SELECT and FROM
    }
    // Need an identifier after FROM
    if i + 1 >= toks.len() || toks[i + 1].kind != TokenKind::Ident {
        return false;
    }
    true
}

fn assert_kinds(toks: &[Token<'_>], expected: &[TokenKind], msg: &str) {
    assert_eq!(
        toks.len(),
        expected.len(),
        "{}: token count mismatch (got {}, expected {})",
        msg,
        toks.len(),
        expected.len()
    );
    for (i, (t, &k)) in toks.iter().zip(expected.iter()).enumerate() {
        assert_eq!(t.kind, k, "{} [{}]: kind mismatch (text={:?})", msg, i, t.text);
    }
}

fn main() {
    use TokenKind::*;

    // ── Test 1: canonical SELECT (mirrors cyrius reference) ──────────
    let toks = tokenize("SELECT * FROM users WHERE id = 1");
    assert_kinds(
        &toks,
        &[Select, Star, From, Ident, Where, Ident, Eq, Int, Eof],
        "canonical select",
    );
    assert_eq!(toks[3].text, "users");
    assert_eq!(toks[5].text, "id");
    assert_eq!(toks[7].text, "1");

    // ── Test 2: case insensitive keywords ──────────────────────────
    let toks = tokenize("select * from T");
    assert_kinds(&toks, &[Select, Star, From, Ident, Eof], "lowercase");
    let toks = tokenize("Select * From T");
    assert_kinds(&toks, &[Select, Star, From, Ident, Eof], "mixed case");

    // ── Test 3: identifiers vs keywords ─────────────────────────────
    let toks = tokenize("selected");
    assert_eq!(toks[0].kind, Ident, "'selected' is identifier, not SELECT");
    assert_eq!(toks[0].text, "selected");

    // ── Test 4: parentheses + comma ─────────────────────────────────
    let toks = tokenize("SELECT (a, b) FROM t");
    assert_kinds(
        &toks,
        &[Select, LParen, Ident, Comma, Ident, RParen, From, Ident, Eof],
        "parens and comma",
    );

    // ── Test 5: integer literal scanning ────────────────────────────
    let toks = tokenize("12345");
    assert_eq!(toks[0].kind, Int);
    assert_eq!(toks[0].text, "12345");

    // ── Test 6: validator accepts good, rejects bad ─────────────────
    assert!(is_valid_select(&tokenize("SELECT * FROM t")));
    assert!(is_valid_select(&tokenize("SELECT a FROM t WHERE id = 1")));
    assert!(!is_valid_select(&tokenize("FROM t")));
    assert!(!is_valid_select(&tokenize("SELECT FROM t")));
    assert!(!is_valid_select(&tokenize("SELECT * FROM")));

    // ── Test 7: whitespace tolerance ───────────────────────────────
    let toks = tokenize("  SELECT\t*\nFROM\tt  ");
    assert_kinds(&toks, &[Select, Star, From, Ident, Eof], "whitespace");

    println!("All sql_parsing examples passed.");
}
