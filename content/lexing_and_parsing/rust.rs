// Lexing and Parsing — Rust Implementation
//
// Demonstrates a complete lexer + Pratt parser for arithmetic expressions.
// The lexer produces tokens with spans. The parser uses operator precedence
// (binding power) to handle +, -, *, /, unary minus, and parentheses.
//
// This is the pattern used by every hand-written compiler frontend:
//   1. Lexer: chars → tokens (with spans for error reporting)
//   2. Parser: tokens → AST (recursive descent + Pratt for expressions)
//   3. Evaluator: AST → result (tree-walk, or codegen in a compiler)

use std::fmt;

// ── Tokens ────────────────────────────────────────────────────────────────

/// Byte range in source text.
#[derive(Debug, Clone, Copy)]
struct Span {
    start: usize,
    end: usize,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum TokenKind {
    Number,  // integer literal
    Plus,
    Minus,
    Star,
    Slash,
    LParen,
    RParen,
    Eof,
}

#[derive(Debug, Clone)]
struct Token {
    kind: TokenKind,
    span: Span,
    text: String, // owned for simplicity; production code would use &str or interning
}

// ── Lexer ─────────────────────────────────────────────────────────────────

struct Lexer {
    source: Vec<char>,
    pos: usize,
}

impl Lexer {
    fn new(source: &str) -> Self {
        Self {
            source: source.chars().collect(),
            pos: 0,
        }
    }

    fn peek_char(&self) -> Option<char> {
        self.source.get(self.pos).copied()
    }

    fn advance_char(&mut self) -> Option<char> {
        let c = self.source.get(self.pos).copied();
        if c.is_some() {
            self.pos += 1;
        }
        c
    }

    fn skip_whitespace(&mut self) {
        while self.peek_char().is_some_and(|c| c.is_ascii_whitespace()) {
            self.advance_char();
        }
    }

    fn next_token(&mut self) -> Token {
        self.skip_whitespace();

        let start = self.pos;

        let Some(c) = self.advance_char() else {
            return Token {
                kind: TokenKind::Eof,
                span: Span {
                    start: self.pos,
                    end: self.pos,
                },
                text: String::new(),
            };
        };

        let kind = match c {
            '+' => TokenKind::Plus,
            '-' => TokenKind::Minus,
            '*' => TokenKind::Star,
            '/' => TokenKind::Slash,
            '(' => TokenKind::LParen,
            ')' => TokenKind::RParen,
            '0'..='9' => {
                while self.peek_char().is_some_and(|c| c.is_ascii_digit()) {
                    self.advance_char();
                }
                TokenKind::Number
            }
            _ => panic!(
                "unexpected character '{}' at position {}",
                c, start
            ),
        };

        let text: String = self.source[start..self.pos].iter().collect();
        Token {
            kind,
            span: Span {
                start,
                end: self.pos,
            },
            text,
        }
    }
}

// ── AST ───────────────────────────────────────────────────────────────────

#[derive(Debug)]
enum Expr {
    Number(i64),
    UnaryMinus(Box<Expr>),
    BinOp {
        op: char,
        left: Box<Expr>,
        right: Box<Expr>,
    },
}

impl fmt::Display for Expr {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Expr::Number(n) => write!(f, "{}", n),
            Expr::UnaryMinus(e) => write!(f, "(-{})", e),
            Expr::BinOp { op, left, right } => write!(f, "({} {} {})", left, op, right),
        }
    }
}

// ── Pratt Parser ──────────────────────────────────────────────────────────

struct Parser {
    lexer: Lexer,
    current: Token,
}

/// Binding power: (left, right). Higher = tighter binding.
/// Left < right means left-associative. Left > right means right-associative.
fn infix_binding_power(op: TokenKind) -> Option<(u8, u8)> {
    match op {
        TokenKind::Plus | TokenKind::Minus => Some((1, 2)),   // left-assoc, low precedence
        TokenKind::Star | TokenKind::Slash => Some((3, 4)),   // left-assoc, high precedence
        _ => None,
    }
}

/// Prefix binding power (for unary operators).
fn prefix_binding_power(op: TokenKind) -> Option<u8> {
    match op {
        TokenKind::Minus => Some(5), // unary minus binds tighter than any infix op
        _ => None,
    }
}

impl Parser {
    fn new(source: &str) -> Self {
        let mut lexer = Lexer::new(source);
        let current = lexer.next_token();
        Self { lexer, current }
    }

    fn advance(&mut self) -> Token {
        let prev = self.current.clone();
        self.current = self.lexer.next_token();
        prev
    }

    fn peek(&self) -> TokenKind {
        self.current.kind
    }

    fn expect(&mut self, kind: TokenKind) {
        if self.peek() != kind {
            panic!(
                "expected {:?} at position {}, found {:?} '{}'",
                kind, self.current.span.start, self.current.kind, self.current.text
            );
        }
        self.advance();
    }

    /// Pratt parser entry point. `min_bp` is the minimum binding power.
    fn parse_expr(&mut self, min_bp: u8) -> Expr {
        // Parse prefix (atoms and unary operators)
        let mut lhs = match self.peek() {
            TokenKind::Number => {
                let tok = self.advance();
                Expr::Number(tok.text.parse().unwrap())
            }
            TokenKind::LParen => {
                self.advance(); // consume '('
                let expr = self.parse_expr(0);
                self.expect(TokenKind::RParen);
                expr
            }
            op if prefix_binding_power(op).is_some() => {
                let bp = prefix_binding_power(op).unwrap();
                self.advance(); // consume operator
                let rhs = self.parse_expr(bp);
                Expr::UnaryMinus(Box::new(rhs))
            }
            _ => panic!(
                "expected expression at position {}, found {:?} '{}'",
                self.current.span.start, self.current.kind, self.current.text
            ),
        };

        // Parse infix operators with binding power loop
        loop {
            let op_kind = self.peek();
            if op_kind == TokenKind::Eof || op_kind == TokenKind::RParen {
                break;
            }

            let Some((l_bp, r_bp)) = infix_binding_power(op_kind) else {
                break;
            };

            // If left binding power is less than minimum, stop
            // (the caller has higher precedence)
            if l_bp < min_bp {
                break;
            }

            let op_char = match op_kind {
                TokenKind::Plus => '+',
                TokenKind::Minus => '-',
                TokenKind::Star => '*',
                TokenKind::Slash => '/',
                _ => unreachable!(),
            };

            self.advance(); // consume operator
            let rhs = self.parse_expr(r_bp);
            lhs = Expr::BinOp {
                op: op_char,
                left: Box::new(lhs),
                right: Box::new(rhs),
            };
        }

        lhs
    }
}

// ── Tree-walk evaluator ───────────────────────────────────────────────────

fn eval(expr: &Expr) -> i64 {
    match expr {
        Expr::Number(n) => *n,
        Expr::UnaryMinus(e) => -eval(e),
        Expr::BinOp { op, left, right } => {
            let l = eval(left);
            let r = eval(right);
            match op {
                '+' => l + r,
                '-' => l - r,
                '*' => l * r,
                '/' => l / r,
                _ => unreachable!(),
            }
        }
    }
}

fn main() {
    let tests = [
        ("42", 42),
        ("2 + 3", 5),
        ("2 + 3 * 4", 14),         // precedence: * before +
        ("(2 + 3) * 4", 20),       // parentheses override precedence
        ("-5 + 3", -2),            // unary minus
        ("10 - 3 - 2", 5),        // left-associative: (10-3)-2
        ("2 * 3 + 4 * 5", 26),    // (2*3) + (4*5)
        ("-(3 + 4) * 2", -14),    // unary minus on grouped expression
    ];

    println!("Pratt parser — expression evaluation:");
    println!("{:<25} {:<30} {:>6} {:>6}", "Input", "AST", "Result", "Expected");
    println!("{}", "-".repeat(70));

    for (input, expected) in &tests {
        let mut parser = Parser::new(input);
        let ast = parser.parse_expr(0);
        let result = eval(&ast);
        let status = if result == *expected { "✓" } else { "✗ FAIL" };
        println!(
            "{:<25} {:<30} {:>6} {:>6} {}",
            input, ast, result, expected, status
        );
        assert_eq!(result, *expected, "failed on input: {}", input);
    }

    println!("\nAll {} tests passed.", tests.len());
}
