// Vidya — Lexing and Parsing in Go
//
// Demonstrates a complete lexer + recursive-descent parser for arithmetic
// expressions. This is the pattern used by every hand-written compiler:
//   1. Lexer: chars -> tokens (scanning with position tracking)
//   2. Parser: tokens -> AST (recursive descent with Pratt binding power)
//   3. Evaluator: AST -> result (tree-walk over the AST)
//
// Supports +, -, *, /, unary minus, and parenthesized sub-expressions.
// AST nodes use Go interfaces — each node type implements the Expr interface.

package main

import (
	"fmt"
	"strconv"
	"unicode"
)

// ── Tokens ────────────────────────────────────────────────────────────

type TokenKind int

const (
	TokNumber TokenKind = iota
	TokPlus
	TokMinus
	TokStar
	TokSlash
	TokLParen
	TokRParen
	TokEOF
)

type Token struct {
	Kind  TokenKind
	Text  string
	Pos   int
}

// ── Lexer ─────────────────────────────────────────────────────────────

type Lexer struct {
	source []rune
	pos    int
}

func NewLexer(source string) *Lexer {
	return &Lexer{source: []rune(source), pos: 0}
}

func (l *Lexer) peek() (rune, bool) {
	if l.pos < len(l.source) {
		return l.source[l.pos], true
	}
	return 0, false
}

func (l *Lexer) advance() (rune, bool) {
	if l.pos < len(l.source) {
		c := l.source[l.pos]
		l.pos++
		return c, true
	}
	return 0, false
}

func (l *Lexer) skipWhitespace() {
	for {
		c, ok := l.peek()
		if !ok || !unicode.IsSpace(c) {
			break
		}
		l.advance()
	}
}

func (l *Lexer) NextToken() Token {
	l.skipWhitespace()
	start := l.pos

	c, ok := l.advance()
	if !ok {
		return Token{Kind: TokEOF, Text: "", Pos: l.pos}
	}

	switch c {
	case '+':
		return Token{Kind: TokPlus, Text: "+", Pos: start}
	case '-':
		return Token{Kind: TokMinus, Text: "-", Pos: start}
	case '*':
		return Token{Kind: TokStar, Text: "*", Pos: start}
	case '/':
		return Token{Kind: TokSlash, Text: "/", Pos: start}
	case '(':
		return Token{Kind: TokLParen, Text: "(", Pos: start}
	case ')':
		return Token{Kind: TokRParen, Text: ")", Pos: start}
	}

	if unicode.IsDigit(c) {
		for {
			ch, ok := l.peek()
			if !ok || !unicode.IsDigit(ch) {
				break
			}
			l.advance()
		}
		text := string(l.source[start:l.pos])
		return Token{Kind: TokNumber, Text: text, Pos: start}
	}

	panic(fmt.Sprintf("unexpected character %q at position %d", c, start))
}

// ── AST ───────────────────────────────────────────────────────────────

// Expr is the interface all AST nodes implement.
type Expr interface {
	exprNode()
	String() string
}

type NumberExpr struct {
	Value int64
}

func (n *NumberExpr) exprNode()      {}
func (n *NumberExpr) String() string { return strconv.FormatInt(n.Value, 10) }

type UnaryMinusExpr struct {
	Operand Expr
}

func (u *UnaryMinusExpr) exprNode()      {}
func (u *UnaryMinusExpr) String() string { return fmt.Sprintf("(-%s)", u.Operand) }

type BinOpExpr struct {
	Op    byte
	Left  Expr
	Right Expr
}

func (b *BinOpExpr) exprNode()      {}
func (b *BinOpExpr) String() string { return fmt.Sprintf("(%s %c %s)", b.Left, b.Op, b.Right) }

// ── Pratt Parser ──────────────────────────────────────────────────────

type Parser struct {
	lexer   *Lexer
	current Token
}

func NewParser(source string) *Parser {
	lex := NewLexer(source)
	tok := lex.NextToken()
	return &Parser{lexer: lex, current: tok}
}

func (p *Parser) advance() Token {
	prev := p.current
	p.current = p.lexer.NextToken()
	return prev
}

func (p *Parser) expect(kind TokenKind) {
	if p.current.Kind != kind {
		panic(fmt.Sprintf("expected token %d at pos %d, got %d %q",
			kind, p.current.Pos, p.current.Kind, p.current.Text))
	}
	p.advance()
}

// infixBP returns (left_bp, right_bp, ok).
// Left < right means left-associative.
func infixBP(kind TokenKind) (int, int, bool) {
	switch kind {
	case TokPlus, TokMinus:
		return 1, 2, true
	case TokStar, TokSlash:
		return 3, 4, true
	}
	return 0, 0, false
}

func prefixBP(kind TokenKind) (int, bool) {
	if kind == TokMinus {
		return 5, true
	}
	return 0, false
}

func opChar(kind TokenKind) byte {
	switch kind {
	case TokPlus:
		return '+'
	case TokMinus:
		return '-'
	case TokStar:
		return '*'
	case TokSlash:
		return '/'
	}
	return '?'
}

func (p *Parser) ParseExpr(minBP int) Expr {
	// ── Prefix / atoms ───────────────────────────────────────────
	var lhs Expr

	switch p.current.Kind {
	case TokNumber:
		tok := p.advance()
		val, err := strconv.ParseInt(tok.Text, 10, 64)
		if err != nil {
			panic(fmt.Sprintf("invalid number %q: %v", tok.Text, err))
		}
		lhs = &NumberExpr{Value: val}

	case TokLParen:
		p.advance()
		lhs = p.ParseExpr(0)
		p.expect(TokRParen)

	default:
		if bp, ok := prefixBP(p.current.Kind); ok {
			p.advance()
			operand := p.ParseExpr(bp)
			lhs = &UnaryMinusExpr{Operand: operand}
		} else {
			panic(fmt.Sprintf("expected expression at pos %d, got %q",
				p.current.Pos, p.current.Text))
		}
	}

	// ── Infix loop ───────────────────────────────────────────────
	for {
		opKind := p.current.Kind
		if opKind == TokEOF || opKind == TokRParen {
			break
		}

		lBP, rBP, ok := infixBP(opKind)
		if !ok {
			break
		}
		if lBP < minBP {
			break
		}

		op := opChar(opKind)
		p.advance()
		rhs := p.ParseExpr(rBP)
		lhs = &BinOpExpr{Op: op, Left: lhs, Right: rhs}
	}

	return lhs
}

// ── Tree-walk evaluator ───────────────────────────────────────────────

func Eval(expr Expr) int64 {
	switch e := expr.(type) {
	case *NumberExpr:
		return e.Value
	case *UnaryMinusExpr:
		return -Eval(e.Operand)
	case *BinOpExpr:
		l := Eval(e.Left)
		r := Eval(e.Right)
		switch e.Op {
		case '+':
			return l + r
		case '-':
			return l - r
		case '*':
			return l * r
		case '/':
			return l / r
		}
	}
	panic("unknown AST node")
}

// ── Main ──────────────────────────────────────────────────────────────

func main() {
	tests := []struct {
		input    string
		expected int64
	}{
		{"42", 42},
		{"2 + 3", 5},
		{"2 + 3 * 4", 14},
		{"(2 + 3) * 4", 20},
		{"-5 + 3", -2},
		{"10 - 3 - 2", 5},
		{"2 * 3 + 4 * 5", 26},
		{"-(3 + 4) * 2", -14},
		{"3 + 4 * (2 - 1)", 7},
	}

	for _, tc := range tests {
		parser := NewParser(tc.input)
		ast := parser.ParseExpr(0)
		result := Eval(ast)

		status := "ok"
		if result != tc.expected {
			status = "FAIL"
		}
		fmt.Printf("%-25s => %4d  (expected %4d) %s\n",
			tc.input, result, tc.expected, status)

		if result != tc.expected {
			panic(fmt.Sprintf("failed on %q: got %d, expected %d",
				tc.input, result, tc.expected))
		}
	}

	fmt.Printf("\nAll %d tests passed.\n", len(tests))
}
