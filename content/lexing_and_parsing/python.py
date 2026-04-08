# Vidya — Lexing and Parsing in Python
#
# Demonstrates a complete lexer + recursive-descent parser for arithmetic
# expressions. The pipeline mirrors what every hand-written compiler does:
#   1. Lexer: chars -> tokens (with position tracking for error messages)
#   2. Parser: tokens -> AST (recursive descent with Pratt binding power)
#   3. Evaluator: AST -> result (tree-walk interpreter)
#
# Supports +, -, *, /, unary minus, and parenthesized sub-expressions.
# Operator precedence is encoded via binding power (Pratt parsing).

from enum import Enum, auto


# ── Tokens ────────────────────────────────────────────────────────────

class TokenKind(Enum):
    NUMBER = auto()
    PLUS = auto()
    MINUS = auto()
    STAR = auto()
    SLASH = auto()
    LPAREN = auto()
    RPAREN = auto()
    EOF = auto()


class Token:
    __slots__ = ("kind", "text", "pos")

    def __init__(self, kind: TokenKind, text: str, pos: int):
        self.kind = kind
        self.text = text
        self.pos = pos

    def __repr__(self) -> str:
        return f"Token({self.kind.name}, {self.text!r}, pos={self.pos})"


# ── Lexer ─────────────────────────────────────────────────────────────

class Lexer:
    """Scans source string into a stream of tokens."""

    def __init__(self, source: str):
        self.source = source
        self.pos = 0

    def _peek(self) -> str | None:
        if self.pos < len(self.source):
            return self.source[self.pos]
        return None

    def _advance(self) -> str | None:
        if self.pos < len(self.source):
            c = self.source[self.pos]
            self.pos += 1
            return c
        return None

    def _skip_whitespace(self) -> None:
        while self._peek() is not None and self._peek().isspace():
            self._advance()

    def next_token(self) -> Token:
        self._skip_whitespace()
        start = self.pos

        c = self._advance()
        if c is None:
            return Token(TokenKind.EOF, "", self.pos)

        single = {
            "+": TokenKind.PLUS,
            "-": TokenKind.MINUS,
            "*": TokenKind.STAR,
            "/": TokenKind.SLASH,
            "(": TokenKind.LPAREN,
            ")": TokenKind.RPAREN,
        }

        if c in single:
            return Token(single[c], c, start)

        if c.isdigit():
            while self._peek() is not None and self._peek().isdigit():
                self._advance()
            return Token(TokenKind.NUMBER, self.source[start:self.pos], start)

        raise ValueError(f"unexpected character {c!r} at position {start}")


# ── AST ───────────────────────────────────────────────────────────────

class Expr:
    """Base class for AST nodes."""
    pass


class NumberExpr(Expr):
    __slots__ = ("value",)

    def __init__(self, value: int):
        self.value = value

    def __repr__(self) -> str:
        return str(self.value)


class UnaryMinusExpr(Expr):
    __slots__ = ("operand",)

    def __init__(self, operand: Expr):
        self.operand = operand

    def __repr__(self) -> str:
        return f"(-{self.operand})"


class BinOpExpr(Expr):
    __slots__ = ("op", "left", "right")

    def __init__(self, op: str, left: Expr, right: Expr):
        self.op = op
        self.left = left
        self.right = right

    def __repr__(self) -> str:
        return f"({self.left} {self.op} {self.right})"


# ── Pratt Parser ──────────────────────────────────────────────────────

def infix_binding_power(kind: TokenKind) -> tuple[int, int] | None:
    """Returns (left_bp, right_bp). Left < right = left-associative."""
    if kind in (TokenKind.PLUS, TokenKind.MINUS):
        return (1, 2)
    if kind in (TokenKind.STAR, TokenKind.SLASH):
        return (3, 4)
    return None


def prefix_binding_power(kind: TokenKind) -> int | None:
    """Binding power for prefix (unary) operators."""
    if kind == TokenKind.MINUS:
        return 5
    return None


OP_CHARS = {
    TokenKind.PLUS: "+",
    TokenKind.MINUS: "-",
    TokenKind.STAR: "*",
    TokenKind.SLASH: "/",
}


class Parser:
    """Pratt parser: recursive descent with operator precedence."""

    def __init__(self, source: str):
        self.lexer = Lexer(source)
        self.current = self.lexer.next_token()

    def _advance(self) -> Token:
        prev = self.current
        self.current = self.lexer.next_token()
        return prev

    def _peek(self) -> TokenKind:
        return self.current.kind

    def _expect(self, kind: TokenKind) -> None:
        if self._peek() != kind:
            raise SyntaxError(
                f"expected {kind.name} at pos {self.current.pos}, "
                f"found {self.current.kind.name} {self.current.text!r}"
            )
        self._advance()

    def parse_expr(self, min_bp: int = 0) -> Expr:
        # ── Prefix / atoms ────────────────────────────────────────
        kind = self._peek()

        if kind == TokenKind.NUMBER:
            tok = self._advance()
            lhs = NumberExpr(int(tok.text))
        elif kind == TokenKind.LPAREN:
            self._advance()
            lhs = self.parse_expr(0)
            self._expect(TokenKind.RPAREN)
        elif (pbp := prefix_binding_power(kind)) is not None:
            self._advance()
            operand = self.parse_expr(pbp)
            lhs = UnaryMinusExpr(operand)
        else:
            raise SyntaxError(
                f"expected expression at pos {self.current.pos}, "
                f"found {self.current.kind.name} {self.current.text!r}"
            )

        # ── Infix loop ────────────────────────────────────────────
        while True:
            op_kind = self._peek()
            if op_kind in (TokenKind.EOF, TokenKind.RPAREN):
                break

            bp = infix_binding_power(op_kind)
            if bp is None:
                break
            l_bp, r_bp = bp

            if l_bp < min_bp:
                break

            self._advance()
            rhs = self.parse_expr(r_bp)
            lhs = BinOpExpr(OP_CHARS[op_kind], lhs, rhs)

        return lhs


# ── Tree-walk evaluator ───────────────────────────────────────────────

def evaluate(expr: Expr) -> int:
    if isinstance(expr, NumberExpr):
        return expr.value
    if isinstance(expr, UnaryMinusExpr):
        return -evaluate(expr.operand)
    if isinstance(expr, BinOpExpr):
        left = evaluate(expr.left)
        right = evaluate(expr.right)
        match expr.op:
            case "+": return left + right
            case "-": return left - right
            case "*": return left * right
            case "/": return left // right
            case _: raise ValueError(f"unknown operator: {expr.op}")
    raise TypeError(f"unknown AST node: {type(expr)}")


# ── Main ──────────────────────────────────────────────────────────────

def main():
    tests = [
        ("42", 42),
        ("2 + 3", 5),
        ("2 + 3 * 4", 14),
        ("(2 + 3) * 4", 20),
        ("-5 + 3", -2),
        ("10 - 3 - 2", 5),
        ("2 * 3 + 4 * 5", 26),
        ("-(3 + 4) * 2", -14),
        ("3 + 4 * (2 - 1)", 7),
    ]

    print(f"{'Input':<25} {'AST':<30} {'Result':>6} {'Expected':>8}")
    print("-" * 72)

    for source, expected in tests:
        parser = Parser(source)
        ast = parser.parse_expr()
        result = evaluate(ast)
        status = "ok" if result == expected else "FAIL"
        print(f"{source:<25} {str(ast):<30} {result:>6} {expected:>8} {status}")
        assert result == expected, f"failed on {source!r}: got {result}, expected {expected}"

    print(f"\nAll {len(tests)} tests passed.")


if __name__ == "__main__":
    main()
