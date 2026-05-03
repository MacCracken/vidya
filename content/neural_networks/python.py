#!/usr/bin/env python3
"""Vidya — Neural Network Forward Pass — Python port. Q15 fixed-point.

Tiny 2 → 3 → 2 MLP. Hand-designed weights classify by which input
is larger. Skips softmax (argmax preserves order; production
inference does the same).
"""

SCALE = 15
ONE = 32768

N_IN, N_HIDDEN, N_OUT = 2, 3, 2


def q_mul(a, b):
    p = a * b
    return -((-p) >> SCALE) if p < 0 else (p >> SCALE)


# Weight matrix convention: W[j][i] = weight from input i to output j.
# Stored row-major as a flat list.

# Hidden: 3 neurons × 2 inputs
W_HIDDEN = [
    16384, -16384,    # h[0] = 0.5*x[0] - 0.5*x[1]
    -16384, 16384,    # h[1] = -0.5*x[0] + 0.5*x[1]
    16384, 16384,     # h[2] = 0.5*x[0] + 0.5*x[1]
]
B_HIDDEN = [0, 0, 0]

# Output: 2 neurons × 3 inputs
W_OUTPUT = [
    16384, 0, 0,      # logit[0] = 0.5 * h[0]
    0, 16384, 0,      # logit[1] = 0.5 * h[1]
]
B_OUTPUT = [0, 0]


def dense(W, b, x_in, n_in, n_out):
    out = []
    for j in range(n_out):
        acc = b[j]
        for i in range(n_in):
            acc += q_mul(W[j * n_in + i], x_in[i])
        out.append(acc)
    return out


def relu(x):
    return [max(0, v) for v in x]


def argmax(x):
    best_idx = 0
    best_val = x[0]
    for i in range(1, len(x)):
        if x[i] > best_val:
            best_val = x[i]
            best_idx = i
    return best_idx


# Module-level state for tests that inspect intermediate layers.
_last_hidden = []
_last_output = []


def forward(input_buf):
    global _last_hidden, _last_output
    hidden = dense(W_HIDDEN, B_HIDDEN, input_buf, N_IN, N_HIDDEN)
    hidden = relu(hidden)
    _last_hidden = hidden
    output = dense(W_OUTPUT, B_OUTPUT, hidden, N_HIDDEN, N_OUT)
    _last_output = output
    return argmax(output)


PASS, FAIL = 0, 0
def check(cond, name):
    global PASS, FAIL
    if cond: PASS += 1
    else: FAIL += 1; print(f"  FAIL: {name}")


def test_q_mul_sanity():
    check(q_mul(ONE, 100) == 100, "ONE * 100 = 100")
    check(q_mul(16384, 16384) == 8192, "0.5 * 0.5 = 0.25")
    check(q_mul(-16384, 16384) == -8192, "-0.5 * 0.5 = -0.25")


def test_dense_layer():
    W = [16384, 16384, 8192, 24576]   # [[0.5,0.5], [0.25,0.75]]
    b = [0, 0]
    x = [32767, 32767]
    y = dense(W, b, x, 2, 2)
    check(32765 <= y[0] <= 32769, "dense y[0] ~= 1.0")
    check(32765 <= y[1] <= 32769, "dense y[1] ~= 1.0")


def test_dense_with_bias():
    W = [0, 0]
    b = [12345]
    x = [32767, 32767]
    y = dense(W, b, x, 2, 1)
    check(y[0] == 12345, "bias passes through")


def test_relu_clips_negatives():
    out = relu([-100, 200, -300, 400])
    check(out == [0, 200, 0, 400], "relu clips negatives")


def test_relu_zero_passes():
    check(relu([0]) == [0], "relu(0) = 0")


def test_argmax_picks_max():
    check(argmax([100, 500, 200, 300]) == 1, "argmax picks index 1")


def test_argmax_first_found_on_ties():
    check(argmax([100, 500, 500]) == 1, "first-found wins on ties")


def test_forward_input0_dominant():
    check(forward([26214, 6553]) == 0, "x=[0.8,0.2] → class 0")


def test_forward_input1_dominant():
    check(forward([6553, 26214]) == 1, "x=[0.2,0.8] → class 1")


def test_forward_strong_input0():
    check(forward([32767, 0]) == 0, "x=[1.0,0.0] → class 0")


def test_forward_strong_input1():
    check(forward([0, 32767]) == 1, "x=[0.0,1.0] → class 1")


def test_forward_relu_actually_fires():
    forward([32767, 0])
    check(_last_hidden[1] == 0, "relu zeroed hidden[1]")
    check(_last_hidden[0] > 0, "hidden[0] passed through")


if __name__ == "__main__":
    test_q_mul_sanity()
    test_dense_layer()
    test_dense_with_bias()
    test_relu_clips_negatives()
    test_relu_zero_passes()
    test_argmax_picks_max()
    test_argmax_first_found_on_ties()
    test_forward_input0_dominant()
    test_forward_input1_dominant()
    test_forward_strong_input0()
    test_forward_strong_input1()
    test_forward_relu_actually_fires()
    print("=== neural_networks ===")
    print(f"{PASS} passed, {FAIL} failed ({PASS + FAIL} total)")
    raise SystemExit(0 if FAIL == 0 else 1)
