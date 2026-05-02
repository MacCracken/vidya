// Vidya — Sprite Rendering in OpenQASM (quantum image encoding)
//
// Classical sprite rendering writes 8-bit palette indices into a
// flat byte framebuffer. The quantum analog is to encode pixel
// values as the *amplitudes* of a state register: a 4-pixel
// row maps to a 2-qubit position register tensored with an
// intensity qubit, and the joint state |pos⟩|intensity⟩ stores
// every pixel's brightness in superposition simultaneously.
//
// This is the basis of FRQI (Flexible Representation of Quantum
// Images): position qubits index pixels, an intensity qubit's
// rotation angle encodes brightness, and a single measurement
// samples one pixel per shot — full image read-out costs many
// shots, but transformations on the entire image cost one gate.
//
// Note: qiskit's qasm2.load does not define `swap`; we expand any
// swap as 3 CNOTs. We stick to qelib1.inc gates only.

OPENQASM 2.0;
include "qelib1.inc";

// ── 4-pixel row: 2 position qubits + 1 intensity qubit ──────────────
// Pixel layout (matches the test sprite's top row 0,1,1,0):
//   pos=00 → intensity=0 (transparent)
//   pos=01 → intensity=1
//   pos=10 → intensity=1
//   pos=11 → intensity=0 (transparent)
//
// Equal-superposition position register: each pixel address
// occurs with amplitude 1/2.

qreg pos[2];        // pixel address
qreg intens[1];     // intensity / "color level"
creg pos_c[2];
creg int_c[1];

// Place the position register in superposition over all 4 pixels.
h pos[0];
h pos[1];

// Conditional intensity rotation: only pixels (01) and (10) are lit.
// Encode "intensity bit = 1 when pos == 01 OR pos == 10" using two
// Toffoli-style controls. We use ccx (Toffoli) from qelib1.

// pos == 01 → set intensity = 1
// We need control = (pos[1]=0, pos[0]=1). Bit-flip pos[1] around the
// Toffoli so we control on its zero-state.
x pos[1];
ccx pos[1], pos[0], intens[0];
x pos[1];

// pos == 10 → set intensity = 1
x pos[0];
ccx pos[1], pos[0], intens[0];
x pos[0];

// Measure both registers. Each shot samples one pixel address with
// uniform probability 1/4 and reads its intensity.
measure pos -> pos_c;
measure intens -> int_c;

// ── Color-key transparency analog ──────────────────────────────────
// Classical color-key skips writes when pixel == COLOR_KEY (0).
// Quantum analog: a Z-rotation on the intensity qubit, controlled
// by NOT-equal-to-key, applies a sprite-only phase. Here we just
// demonstrate the conditional flip: "if intensity != 0, flip an
// alpha qubit to mark the pixel as drawn."

qreg alpha[1];
creg alpha_c[1];

// alpha = intensity (CNOT from intensity → alpha) — in a real FRQI
// pipeline this would gate a write into a destination register,
// matching the classical "if pixel != COLOR_KEY then write" branch.
cx intens[0], alpha[0];

measure alpha -> alpha_c;

// ── Scaled blit / fixed-point stepping analog ──────────────────────
// Classical scaled blit advances a fixed-point accumulator
// `src_x += step` and snaps to integer source-pixel coordinates
// via right-shift. The quantum analog is a discrete-time quantum
// walk on the position register: a coin qubit decides "stay /
// step" and a controlled-shift on the position register advances.
// Below: a single coin-flipped quantum walk step on a 2-pixel
// position register, illustrating the structure without committing
// to a specific scaling factor.

qreg coin[1];
qreg walk_pos[2];
creg walk_c[2];

// Coin in equal superposition.
h coin[0];

// Controlled increment of walk_pos when coin = 1.
// Increment-by-one on a 2-qubit register with control:
//   pos[1] ^= pos[0] (when coin = 1)  — Toffoli
//   pos[0] ^= 1      (when coin = 1)  — CNOT
ccx coin[0], walk_pos[0], walk_pos[1];
cx  coin[0], walk_pos[0];

measure walk_pos -> walk_c;

// ── Notes — classical raster vs quantum image encoding ─────────────
//
// Classical software blit:
//   - Per-pixel: bounds check, color-key compare, byte write
//   - O(width × height) work per sprite
//   - Memory-bandwidth bound on the framebuffer
//
// Quantum image (FRQI / NEQR):
//   - Whole-image transformations cost O(1) gate depth
//   - Encoding cost: O(2^n) state preparation for 2^n pixels
//   - Measurement is the bottleneck — many shots to reconstruct
//   - Useful for image-processing kernels that benefit from
//     amplitude-level superposition (e.g., quantum edge detection,
//     quantum Fourier transform on image rows)
