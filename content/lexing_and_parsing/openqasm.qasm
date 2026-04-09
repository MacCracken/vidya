// Vidya — Lexing and Parsing in OpenQASM (Circuit as Parse Tree)
//
// Analogy: a quantum circuit is a parse tree of gate applications.
// Each gate is a node, qubit wires are edges. Nested custom gates
// mirror recursive descent through grammar productions.

OPENQASM 2.0;
include "qelib1.inc";

// ── "Grammar production": compound gate built from primitives ────
// Production: bell -> h, cx  (like S -> A B in a grammar)
gate bell a, b { h a; cx a, b; }

// Production: ghz -> bell, cx  (recursive production)
gate ghz3 a, b, c { bell a, b; cx b, c; }

qreg tokens[3];
creg parsed[3];

// "Parse": expand high-level construct into primitive gates
ghz3 tokens[0], tokens[1], tokens[2];
// Parse tree: ghz3 -> bell -> {h, cx}, cx

measure tokens -> parsed;
