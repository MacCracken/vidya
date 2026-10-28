// Vidya — Framebuffer Rendering in OpenQASM (qubit-as-pixel analog)
//
// Classical framebuffer: a flat array of pixel cells, each in some
// color state, addressed by (x, y). The quantum analog is a *qubit
// register where each qubit represents one pixel*: the register's
// state vector encodes the entire framebuffer as a superposition of
// all possible pixel configurations.
//
// We use 4 qubits = a 2x2 framebuffer (4 pixels). Each qubit is one
// pixel; |0> means dark, |1> means lit. Operations:
//   - X gate    — "fb_set": flip pixel from |0> to |1>
//   - measure   — "fb_get": collapse and read pixel state
//
// The quantum framebuffer has one structural advantage over classical:
// because all pixels exist as a single register, sub-grid
// effects (cellular automata, convolutions, region fills) can be
// expressed as gate sequences over the whole register at once. This
// is the structural argument for "GPU-as-quantum-processor": both
// fundamentally parallelize across the entire pixel grid in one shot,
// rather than per-pixel like the CPU framebuffer model.
//
// Real quantum image representations are denser than one qubit per
// pixel: FRQI (Le et al. 2011) and NEQR (Zhang et al. 2013) use
// log2(#pixels) position qubits holding every pixel address in
// superposition, entangled with color qubits (FRQI: one qubit whose
// rotation angle is the intensity; NEQR: the gray value as a basis
// state). Image transformations are unitary gate sequences on that
// register.

OPENQASM 3.1;
include "stdgates.inc";

qubit[4] q;
bit[4] c;

// Initial state: all pixels dark (|0000>) — analog of fb_clear.

// fb_set: light pixels (0,0) and (1,1) — diagonal stripe
x q[0];     // pixel (0,0)
x q[3];     // pixel (1,1)

// "Draw horizontal line on row 0": pixel (0,0) and (1,0)
x q[1];     // pixel (1,0) — q[0] already lit

// fb_get: measure all four pixels
c = measure q;
// c = 1011 on every shot: q[0], q[1], q[3] lit, q[2] dark
// @expect c == 11
