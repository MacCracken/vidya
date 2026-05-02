// Vidya — SQL Parsing in OpenQASM (Circuit as Token Stream)
//
// Analogy: the tokens of a SQL statement are encoded as a quantum
// register, and a "parse" is a sequence of controlled gates that
// recognises a valid grammar production. Each compound gate models
// a grammar rule built from primitives — h is the quantum analog of
// "encode any keyword in superposition", cx is "if keyword token X
// fired then expect this column slot", and the final measurement
// collapses the parse tree to a single accepted derivation.
//
// Production: select_stmt -> SELECT cols FROM table
// Modeled as a 4-qubit register where each qubit represents one of
// the four lexical slots. The compound `select_stmt` gate threads
// the dependencies: SELECT enables cols, cols enables FROM, etc.

OPENQASM 2.0;
include "qelib1.inc";

// ── "Grammar productions" as compound gates ───────────────────────────
// Production: cols -> STAR | IDENT (one column slot)
// The control qubit = SELECT-fired flag. CX flips the cols-slot
// qubit when SELECT preceded it — encoding the dependency that the
// cols rule only fires after SELECT.
gate cols_after_select sel, c { cx sel, c; }

// Production: from_after_cols -> FROM following cols
gate from_after_cols c, f { cx c, f; }

// Production: table_after_from -> IDENT following FROM
gate table_after_from f, t { cx f, t; }

// Top-level production: select_stmt -> SELECT cols FROM table
// Composes the three sub-productions into one parse tree expansion.
gate select_stmt sel, c, f, t {
    cols_after_select sel, c;
    from_after_cols c, f;
    table_after_from f, t;
}

// ── Token slots and parsed register ───────────────────────────────────
// q[0] = SELECT seen, q[1] = cols slot, q[2] = FROM seen, q[3] = table slot
qreg toks[4];
creg parsed[4];

// Tokenizer "produces" the SELECT token first — flip q[0] to |1>
x toks[0];

// Run the parse — apply the compound production
select_stmt toks[0], toks[1], toks[2], toks[3];
// Parse tree expansion: select_stmt
//   ├── cols_after_select  (cx sel -> c)
//   ├── from_after_cols    (cx c -> f)
//   └── table_after_from   (cx f -> t)
// After this: |q[0..3]> = |1111> — every slot validated.

measure toks -> parsed;
// parsed = "1111" with probability 1 — the full SELECT * FROM t parse
// tree was accepted. Any production that fails to fire would leave
// a slot at |0>, which a downstream classical check could reject.
