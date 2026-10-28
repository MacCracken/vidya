// Vidya — Lexing and Parsing in OpenQASM (Circuit as Parse Tree)
//
// Analogy: a quantum circuit is a parse tree of gate applications.
// Each gate is a node, qubit wires are edges. Nested custom gates
// mirror recursive descent through grammar productions.

OPENQASM 3.1;
include "stdgates.inc";

// ── "Grammar production": compound gate built from primitives ────
// Production: bell -> h, cx  (like S -> A B in a grammar)
gate bell a, b { h a; cx a, b; }

// Production: ghz -> bell, cx  (nested production: one rule uses
// another. True recursion is not allowed — OpenQASM forbids a gate
// that calls itself, so every gate expands to a finite tree.)
gate ghz3 a, b, c { bell a, b; cx b, c; }

qubit[3] tokens;
bit[3] parsed;

// "Parse": expand high-level construct into primitive gates
ghz3 tokens[0], tokens[1], tokens[2];
// Parse tree: ghz3 -> bell -> {h, cx}, cx

parsed = measure tokens;
// A GHZ state: parsed reads 000 or 111, each half the time
// @expect parsed in {0, 7}
