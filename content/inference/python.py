#!/usr/bin/env python3
"""Vidya — LLM Inference (Decoding) — Python port.

Three primitives: greedy decoding (argmax) + top-k filter +
autoregressive bigram decode loop with EOS termination and
max_length cap. All integer logits.
"""

VOCAB_SIZE = 8
TOK_UNK = 0
TOK_EOS = 1


def init_bigram_table():
    bigram = [[0] * VOCAB_SIZE for _ in range(VOCAB_SIZE)]
    bigram[2][3] = 1000   # hello → world
    bigram[2][4] = 100
    bigram[3][6] = 800    # world → the
    bigram[3][5] = 200
    bigram[4][5] = 700    # foo → bar
    bigram[5][1] = 600    # bar → EOS
    bigram[6][7] = 900    # the → end
    bigram[6][3] = 100
    bigram[7][1] = 950    # end → EOS
    return bigram


BIGRAM = init_bigram_table()


def argmax_logits(logits):
    best_idx = 0
    best_val = logits[0]
    for i in range(1, len(logits)):
        if logits[i] > best_val:
            best_val = logits[i]
            best_idx = i
    return best_idx


def topk_filter(logits, k):
    # Naive O(N*K) repeated argmax-on-unmarked.
    marks = [False] * len(logits)
    picked = 0
    while picked < k:
        best_idx = -1
        best_val = 0
        first = True
        for j in range(len(logits)):
            if not marks[j]:
                if first:
                    best_idx, best_val = j, logits[j]
                    first = False
                elif logits[j] > best_val:
                    best_idx, best_val = j, logits[j]
        if best_idx < 0:
            return picked
        marks[best_idx] = True
        picked += 1
    for m in range(len(logits)):
        if not marks[m]:
            logits[m] = 0
    return picked


def bigram_logits(prev_token):
    return list(BIGRAM[prev_token])


def decode_sequence(start_token, max_length):
    output = []
    current = start_token
    while len(output) < max_length:
        logits = bigram_logits(current)
        next_tok = argmax_logits(logits)
        output.append(next_tok)
        if next_tok == TOK_EOS:
            return output
        current = next_tok
    return output


PASS, FAIL = 0, 0
def check(cond, name):
    global PASS, FAIL
    if cond: PASS += 1
    else: FAIL += 1; print(f"  FAIL: {name}")


def test_argmax_picks_max():
    check(argmax_logits([100, 500, 200, 300]) == 1, "argmax picks 1")


def test_argmax_first_found_on_ties():
    check(argmax_logits([100, 500, 500]) == 1, "first-found wins on ties")


def test_argmax_negative_logits():
    check(argmax_logits([-100, -50, -200]) == 1, "argmax over negatives")


def test_topk_keeps_top3():
    logits = [10, 50, 30, 20, 40, 5, 60, 25]
    picked = topk_filter(logits, 3)
    check(picked == 3, "topk picked 3")
    check(logits[6] == 60 and logits[1] == 50 and logits[4] == 40, "top 3 kept")
    for i in [0, 2, 3, 5, 7]:
        check(logits[i] == 0, f"idx {i} zeroed")


def test_topk_k_equals_n_keeps_all():
    logits = [1, 2, 3]
    picked = topk_filter(logits, 3)
    check(picked == 3, "topk(3,3) keeps all")
    check(logits == [1, 2, 3], "all preserved")


def test_bigram_lookup():
    next_tok = argmax_logits(bigram_logits(2))
    check(next_tok == 3, "after hello → world")


def test_decode_hello_to_eos():
    out = decode_sequence(2, 10)
    check(out == [3, 6, 7, 1], f"hello → world,the,end,EOS (got {out})")


def test_decode_terminates_on_eos_short():
    out = decode_sequence(5, 10)   # bar → EOS
    check(out == [1], f"bar → EOS (got {out})")


def test_decode_respects_max_length():
    out = decode_sequence(2, 2)
    check(out == [3, 6], f"capped at 2 (got {out})")


def test_decode_deterministic():
    out1 = decode_sequence(2, 10)
    out2 = decode_sequence(2, 10)
    check(out1 == out2, "deterministic")


if __name__ == "__main__":
    test_argmax_picks_max()
    test_argmax_first_found_on_ties()
    test_argmax_negative_logits()
    test_topk_keeps_top3()
    test_topk_k_equals_n_keeps_all()
    test_bigram_lookup()
    test_decode_hello_to_eos()
    test_decode_terminates_on_eos_short()
    test_decode_respects_max_length()
    test_decode_deterministic()
    print("=== inference ===")
    print(f"{PASS} passed, {FAIL} failed ({PASS + FAIL} total)")
    raise SystemExit(0 if FAIL == 0 else 1)
