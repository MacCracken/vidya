// Vidya — SQL Parsing in Go
//
// Idiomatic shape: a typed `Tok` constant family + a struct-of-tokens
// returned from `tokenize`. The lexer walks the input rune-by-rune
// using a position cursor (similar to a `bufio.Scanner` but
// hand-written for span tracking). Keywords are matched case-
// insensitively via `strings.ToUpper`. Mirrors cyrius.cyr.

package main

import (
	"fmt"
	"strings"
)

type Tok int

const (
	TEOF Tok = iota
	TIdent
	TInt
	TStar
	TEq
	TLParen
	TRParen
	TComma
	TSelect
	TFrom
	TWhere
)

type Token struct {
	Kind Tok
	Text string
}

func isAlpha(c byte) bool {
	return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_'
}

func isAlnum(c byte) bool {
	return isAlpha(c) || (c >= '0' && c <= '9')
}

func classify(text string) Tok {
	switch strings.ToUpper(text) {
	case "SELECT":
		return TSelect
	case "FROM":
		return TFrom
	case "WHERE":
		return TWhere
	}
	return TIdent
}

func tokenize(sql string) []Token {
	out := make([]Token, 0, 16)
	pos := 0
	n := len(sql)

	for pos < n {
		c := sql[pos]
		if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
			pos++
			continue
		}
		if isAlpha(c) {
			start := pos
			for pos < n && isAlnum(sql[pos]) {
				pos++
			}
			text := sql[start:pos]
			out = append(out, Token{Kind: classify(text), Text: text})
			continue
		}
		if c >= '0' && c <= '9' {
			start := pos
			for pos < n && sql[pos] >= '0' && sql[pos] <= '9' {
				pos++
			}
			out = append(out, Token{Kind: TInt, Text: sql[start:pos]})
			continue
		}
		var k Tok
		switch c {
		case '*':
			k = TStar
		case '=':
			k = TEq
		case '(':
			k = TLParen
		case ')':
			k = TRParen
		case ',':
			k = TComma
		default:
			pos++
			continue
		}
		out = append(out, Token{Kind: k, Text: string(c)})
		pos++
	}
	out = append(out, Token{Kind: TEOF, Text: ""})
	return out
}

func isValidSelect(toks []Token) bool {
	if len(toks) == 0 || toks[0].Kind != TSelect {
		return false
	}
	fromIdx := -1
	for i, t := range toks {
		if t.Kind == TFrom {
			fromIdx = i
			break
		}
	}
	if fromIdx < 0 || fromIdx == 1 {
		return false
	}
	if fromIdx+1 >= len(toks) || toks[fromIdx+1].Kind != TIdent {
		return false
	}
	return true
}

func assertKinds(toks []Token, expected []Tok, msg string) {
	if len(toks) != len(expected) {
		panic(fmt.Sprintf("%s: token count %d != expected %d", msg, len(toks), len(expected)))
	}
	for i := range toks {
		if toks[i].Kind != expected[i] {
			panic(fmt.Sprintf("%s [%d]: kind %d != %d (text=%q)",
				msg, i, toks[i].Kind, expected[i], toks[i].Text))
		}
	}
}

func main() {
	// Test 1: canonical SELECT (mirrors cyrius reference)
	toks := tokenize("SELECT * FROM users WHERE id = 1")
	assertKinds(toks, []Tok{TSelect, TStar, TFrom, TIdent, TWhere,
		TIdent, TEq, TInt, TEOF}, "canonical")
	if toks[3].Text != "users" {
		panic("expected 'users'")
	}
	if toks[5].Text != "id" {
		panic("expected 'id'")
	}
	if toks[7].Text != "1" {
		panic("expected '1'")
	}

	// Test 2: case insensitive
	toks = tokenize("select * from T")
	assertKinds(toks, []Tok{TSelect, TStar, TFrom, TIdent, TEOF}, "lowercase")
	toks = tokenize("Select * From T")
	assertKinds(toks, []Tok{TSelect, TStar, TFrom, TIdent, TEOF}, "mixed case")

	// Test 3: 'selected' is an identifier
	toks = tokenize("selected")
	if toks[0].Kind != TIdent || toks[0].Text != "selected" {
		panic("expected ident 'selected'")
	}

	// Test 4: parens + commas
	toks = tokenize("SELECT (a, b) FROM t")
	assertKinds(toks, []Tok{TSelect, TLParen, TIdent, TComma, TIdent, TRParen,
		TFrom, TIdent, TEOF}, "parens")

	// Test 5: integer literal
	toks = tokenize("12345")
	if toks[0].Kind != TInt || toks[0].Text != "12345" {
		panic("expected int 12345")
	}

	// Test 6: validator
	if !isValidSelect(tokenize("SELECT * FROM t")) {
		panic("validator should accept simple")
	}
	if !isValidSelect(tokenize("SELECT a FROM t WHERE id = 1")) {
		panic("validator should accept WHERE")
	}
	if isValidSelect(tokenize("FROM t")) {
		panic("validator should reject leading FROM")
	}
	if isValidSelect(tokenize("SELECT FROM t")) {
		panic("validator should reject empty col list")
	}
	if isValidSelect(tokenize("SELECT * FROM")) {
		panic("validator should reject missing table")
	}

	// Test 7: whitespace tolerance
	toks = tokenize("  SELECT\t*\nFROM\tt  ")
	assertKinds(toks, []Tok{TSelect, TStar, TFrom, TIdent, TEOF}, "whitespace")

	fmt.Println("All sql_parsing examples passed.")
}
