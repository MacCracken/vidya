# Vidya — SQL Parsing in Python
#
# Idiomatic shape: an Enum for token kinds, a hand-written character
# scanner with a position cursor, and frozen dataclasses for
# tokens. Keywords are recognised case-insensitively by uppercasing.
# Mirrors the cyrius.cyr reference: SELECT/FROM/WHERE keywords plus
# IDENT, INT, single-char operators, and EOF.

from __future__ import annotations
from enum import Enum, auto
from dataclasses import dataclass


class Tok(Enum):
    EOF = auto()
    IDENT = auto()
    INT = auto()
    STAR = auto()
    EQ = auto()
    LPAREN = auto()
    RPAREN = auto()
    COMMA = auto()
    SELECT = auto()
    FROM = auto()
    WHERE = auto()


@dataclass(frozen=True)
class Token:
    kind: Tok
    text: str


KEYWORDS = {
    "SELECT": Tok.SELECT,
    "FROM": Tok.FROM,
    "WHERE": Tok.WHERE,
}

SINGLE = {
    "*": Tok.STAR,
    "=": Tok.EQ,
    "(": Tok.LPAREN,
    ")": Tok.RPAREN,
    ",": Tok.COMMA,
}


def _is_alpha(c: str) -> bool:
    # ASCII only, like _is_digit: str.isalpha() is Unicode-wide, and
    # "ſ".upper() == "S", so "ſelect" lexed as the keyword SELECT.
    return ("a" <= c <= "z") or ("A" <= c <= "Z") or c == "_"


def _is_digit(c: str) -> bool:
    # NOT str.isdigit(): that is Unicode-wide and accepts "²" or "٣", which
    # int() then rejects. An INT token must be ASCII 0-9.
    return "0" <= c <= "9"


def _is_alnum(c: str) -> bool:
    return _is_alpha(c) or _is_digit(c)


def tokenize(sql: str) -> list[Token]:
    """Raises ValueError on a character this lexer does not know.

    Refusing matters: silently dropping '<' turns `id < 5` into `id 5`,
    dropping '!' turns `id != 1` into `id = 1`, and dropping ';' lets
    `FROM t; DROP TABLE t` reach the parser as plain identifiers.
    """
    out: list[Token] = []
    pos = 0
    n = len(sql)
    while pos < n:
        c = sql[pos]
        if c.isspace():
            pos += 1
            continue
        if _is_alpha(c):
            start = pos
            while pos < n and _is_alnum(sql[pos]):
                pos += 1
            text = sql[start:pos]
            kind = KEYWORDS.get(text.upper(), Tok.IDENT)
            out.append(Token(kind, text))
            continue
        if _is_digit(c):
            start = pos
            while pos < n and _is_digit(sql[pos]):
                pos += 1
            out.append(Token(Tok.INT, sql[start:pos]))
            continue
        if c in SINGLE:
            out.append(Token(SINGLE[c], c))
            pos += 1
            continue
        raise ValueError(f"unexpected character {c!r} at position {pos}")

    out.append(Token(Tok.EOF, ""))
    return out


def is_valid_select(toks: list[Token]) -> bool:
    """Minimal SELECT structure check."""
    if not toks or toks[0].kind != Tok.SELECT:
        return False
    try:
        from_idx = next(i for i, t in enumerate(toks) if t.kind == Tok.FROM)
    except StopIteration:
        return False
    if from_idx == 1:
        return False  # nothing between SELECT and FROM
    if from_idx + 1 >= len(toks) or toks[from_idx + 1].kind != Tok.IDENT:
        return False
    # ...then end of input, or exactly WHERE <ident> = <int|ident>. Without
    # this, anything after the table name ("FROM t DROP TABLE t") passed.
    tail = [t.kind for t in toks[from_idx + 2:]]
    if tail == [Tok.EOF]:
        return True
    return (len(tail) == 5 and tail[:3] == [Tok.WHERE, Tok.IDENT, Tok.EQ]
            and tail[3] in (Tok.INT, Tok.IDENT) and tail[4] == Tok.EOF)


def assert_kinds(toks: list[Token], expected: list[Tok], msg: str) -> None:
    assert len(toks) == len(expected), (
        f"{msg}: token count mismatch — got {len(toks)}, expected {len(expected)}"
    )
    for i, (t, k) in enumerate(zip(toks, expected)):
        assert t.kind == k, f"{msg} [{i}]: kind {t.kind} != {k} (text={t.text!r})"


def main() -> None:
    # Test 1: canonical SELECT (mirrors cyrius reference)
    toks = tokenize("SELECT * FROM users WHERE id = 1")
    assert_kinds(
        toks,
        [Tok.SELECT, Tok.STAR, Tok.FROM, Tok.IDENT, Tok.WHERE,
         Tok.IDENT, Tok.EQ, Tok.INT, Tok.EOF],
        "canonical select",
    )
    assert toks[3].text == "users"
    assert toks[5].text == "id"
    assert toks[7].text == "1"

    # Test 2: case insensitive
    toks = tokenize("select * from T")
    assert_kinds(toks, [Tok.SELECT, Tok.STAR, Tok.FROM, Tok.IDENT, Tok.EOF],
                 "lowercase")
    toks = tokenize("Select * From T")
    assert_kinds(toks, [Tok.SELECT, Tok.STAR, Tok.FROM, Tok.IDENT, Tok.EOF],
                 "mixed case")

    # Test 3: 'selected' is an identifier, not SELECT
    toks = tokenize("selected")
    assert toks[0].kind == Tok.IDENT
    assert toks[0].text == "selected"

    # Test 4: parens and commas
    toks = tokenize("SELECT (a, b) FROM t")
    assert_kinds(
        toks,
        [Tok.SELECT, Tok.LPAREN, Tok.IDENT, Tok.COMMA, Tok.IDENT, Tok.RPAREN,
         Tok.FROM, Tok.IDENT, Tok.EOF],
        "parens",
    )

    # Test 5: integer literal
    toks = tokenize("12345")
    assert toks[0].kind == Tok.INT and toks[0].text == "12345"
    # A superscript two is not an INT (int("²") raises ValueError): the
    # lexer refuses it rather than produce an INT token
    try:
        tokenize("id = ²")
        assert False, "'²' should be rejected"
    except ValueError:
        pass

    # Test 6: validator
    assert is_valid_select(tokenize("SELECT * FROM t"))
    assert is_valid_select(tokenize("SELECT a FROM t WHERE id = 1"))
    assert not is_valid_select(tokenize("FROM t"))
    assert not is_valid_select(tokenize("SELECT FROM t"))
    assert not is_valid_select(tokenize("SELECT * FROM"))
    # Nothing may follow the table except one WHERE <ident> = <value>
    for bad in ["SELECT * FROM t DROP TABLE t", "SELECT * FROM t u",
                "SELECT * FROM t WHERE DROP TABLE t",
                "SELECT * FROM t WHERE id = 1 DROP TABLE t"]:
        assert not is_valid_select(tokenize(bad)), f"trailing tokens: {bad!r}"

    # Test 7: whitespace tolerance
    toks = tokenize("  SELECT\t*\nFROM\tt  ")
    assert_kinds(toks, [Tok.SELECT, Tok.STAR, Tok.FROM, Tok.IDENT, Tok.EOF],
                 "whitespace")

    # Test 8: unknown characters are rejected, never dropped
    for bad in ["SELECT * FROM t WHERE id < 5", "SELECT * FROM t WHERE id != 1",
                "SELECT * FROM t; DROP TABLE t", "SELECT * FROM t WHERE n = 'x'",
                "ſelect * FROM t"]:
        try:
            tokenize(bad)
            assert False, f"should reject: {bad!r}"
        except ValueError:
            pass

    print("All sql_parsing examples passed.")


if __name__ == "__main__":
    main()
