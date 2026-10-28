// Vidya — SQL Parsing in TypeScript
//
// Idiomatic shape: a string-literal union for token kinds (TS tagged
// unions), and an interface holding {kind, text}. The lexer walks the
// input with a position cursor and switches on character class. Keyword
// recognition uppercases the lexeme before dictionary lookup. Mirrors
// the cyrius.cyr reference: SELECT/FROM/WHERE plus IDENT, INT,
// single-char operators, EOF.

type TokenKind =
    | "eof"
    | "ident"
    | "int"
    | "star"
    | "eq"
    | "lparen"
    | "rparen"
    | "comma"
    | "select"
    | "from"
    | "where";

interface Token {
    kind: TokenKind;
    text: string;
}

// Partial: a lookup of a non-keyword is undefined, and the type says so
// (a plain Record<string, TokenKind> would claim every string is a keyword).
const KEYWORDS: Partial<Record<string, TokenKind>> = {
    SELECT: "select",
    FROM: "from",
    WHERE: "where",
};

const SINGLE: Partial<Record<string, TokenKind>> = {
    "*": "star",
    "=": "eq",
    "(": "lparen",
    ")": "rparen",
    ",": "comma",
};

function isAlpha(c: string): boolean {
    return /[A-Za-z_]/.test(c);
}

function isAlnum(c: string): boolean {
    return /[A-Za-z0-9_]/.test(c);
}

function tokenize(sql: string): Token[] {
    const out: Token[] = [];
    let pos = 0;
    const n = sql.length;

    while (pos < n) {
        const c = sql[pos];
        if (/\s/.test(c)) {
            pos++;
            continue;
        }
        if (isAlpha(c)) {
            const start = pos;
            while (pos < n && isAlnum(sql[pos])) pos++;
            const text = sql.slice(start, pos);
            const kw = KEYWORDS[text.toUpperCase()];
            out.push({ kind: kw ?? "ident", text });
            continue;
        }
        if (/[0-9]/.test(c)) {
            const start = pos;
            while (pos < n && /[0-9]/.test(sql[pos])) pos++;
            out.push({ kind: "int", text: sql.slice(start, pos) });
            continue;
        }
        const k = SINGLE[c];
        if (k !== undefined) {
            out.push({ kind: k, text: c });
            pos++;
            continue;
        }
        // Unknown char — reject. Skipping it would silently change the
        // query: "id != 1" would lex as "id = 1", 'x' as the identifier x.
        throw new Error(`unexpected character ${JSON.stringify(c)} at ${pos}`);
    }
    out.push({ kind: "eof", text: "" });
    return out;
}

function isValidSelect(toks: Token[]): boolean {
    if (toks.length === 0 || toks[0].kind !== "select") return false;
    const fromIdx = toks.findIndex(t => t.kind === "from");
    if (fromIdx < 0) return false;
    if (fromIdx === 1) return false; // no columns
    if (fromIdx + 1 >= toks.length || toks[fromIdx + 1].kind !== "ident") return false;
    // ...then end of input, or exactly WHERE <ident> = <int|ident>. Checking
    // only the next token let anything after WHERE through
    // ("FROM t WHERE DROP TABLE t").
    const tail = toks.slice(fromIdx + 2).map(t => t.kind).join(",");
    return tail === "eof" || tail === "where,ident,eq,int,eof" || tail === "where,ident,eq,ident,eof";
}

function assertKinds(toks: Token[], expected: TokenKind[], msg: string): void {
    if (toks.length !== expected.length) {
        throw new Error(`${msg}: token count ${toks.length} != ${expected.length}`);
    }
    for (let i = 0; i < toks.length; i++) {
        if (toks[i].kind !== expected[i]) {
            throw new Error(
                `${msg} [${i}]: kind ${toks[i].kind} != ${expected[i]} (text=${JSON.stringify(toks[i].text)})`
            );
        }
    }
}

function assert(cond: boolean, msg: string): void {
    if (!cond) throw new Error(`Assertion failed: ${msg}`);
}

function main(): void {
    // Test 1: canonical SELECT (mirrors cyrius reference)
    let toks = tokenize("SELECT * FROM users WHERE id = 1");
    assertKinds(
        toks,
        ["select", "star", "from", "ident", "where", "ident", "eq", "int", "eof"],
        "canonical",
    );
    assert(toks[3].text === "users", "users");
    assert(toks[5].text === "id", "id");
    assert(toks[7].text === "1", "1");

    // Test 2: case insensitive
    toks = tokenize("select * from T");
    assertKinds(toks, ["select", "star", "from", "ident", "eof"], "lowercase");
    toks = tokenize("Select * From T");
    assertKinds(toks, ["select", "star", "from", "ident", "eof"], "mixed");

    // Test 3: 'selected' is identifier
    toks = tokenize("selected");
    assert(toks[0].kind === "ident" && toks[0].text === "selected", "selected as ident");

    // Test 4: parens + commas
    toks = tokenize("SELECT (a, b) FROM t");
    assertKinds(
        toks,
        ["select", "lparen", "ident", "comma", "ident", "rparen", "from", "ident", "eof"],
        "parens",
    );

    // Test 5: integer literal
    toks = tokenize("12345");
    assert(toks[0].kind === "int" && toks[0].text === "12345", "int 12345");

    // Test 6: validator
    assert(isValidSelect(tokenize("SELECT * FROM t")), "valid simple");
    assert(isValidSelect(tokenize("SELECT a FROM t WHERE id = 1")), "valid where");
    assert(!isValidSelect(tokenize("FROM t")), "leading FROM rejected");
    assert(!isValidSelect(tokenize("SELECT FROM t")), "empty cols rejected");
    assert(!isValidSelect(tokenize("SELECT * FROM")), "missing table rejected");

    // Nothing may follow the table except one WHERE <ident> = <value>
    for (const q of ["SELECT * FROM t u", "SELECT * FROM t DROP TABLE t",
                     "SELECT * FROM t WHERE DROP TABLE t",
                     "SELECT * FROM t WHERE id = 1 DROP TABLE t"]) {
        assert(!isValidSelect(tokenize(q)), `trailing tokens rejected: ${q}`);
    }

    // Test 7: characters the lexer does not know are errors, not skipped
    for (const bad of ["SELECT * FROM t WHERE id != 1", "SELECT * FROM t; DROP TABLE t"]) {
        let threw = false;
        try { tokenize(bad); } catch { threw = true; }
        assert(threw, `unknown character rejected: ${bad}`);
    }

    // Test 8: whitespace tolerance
    toks = tokenize("  SELECT\t*\nFROM\tt  ");
    assertKinds(toks, ["select", "star", "from", "ident", "eof"], "whitespace");

    console.log("All sql_parsing examples passed.");
}

main();
