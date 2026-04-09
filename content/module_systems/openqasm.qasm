// Vidya — Module Systems in OpenQASM (Include as Module Import)
//
// Analogy: `include` imports gate definitions from another file,
// like a module system. The standard library qelib1.inc is the
// "prelude" module that every program imports.

OPENQASM 2.0;
include "qelib1.inc";  // module import: brings h, cx, t, s, etc.

// ── Using symbols from the imported module ───────────────────────
// All standard gates are "exported" by qelib1.inc
qreg q[2];
creg c[2];

// Gates from the standard module
h q[0];
s q[0];
cx q[0], q[1];

// Custom "local module" definition
gate local_op a { t a; h a; t a; }
local_op q[1];

measure q -> c;
