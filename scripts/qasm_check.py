"""qasm_check.py <file.qasm> — the OpenQASM 3 gate for one example.

1. The file must load with qiskit's OpenQASM 3 importer (qiskit.qasm3,
   backed by qiskit_qasm3_import). That is the parse-and-resolve check
   every example gets.
2. Every `// @expect` line must hold in a seeded qiskit-aer simulation.
   The prose in a circuit says what it measures ("result will always be
   101"); an @expect line says the same thing in a form the gate can run:

       // @expect <creg> == <int>           every shot reads this value
       // @expect <creg> in {<int>, ...}    every shot is in the set, and
                                            each listed value occurs

   A value is the register read as an unsigned integer with bit [0] as the
   least significant bit, which is how `if (c == n)` reads it. So
   `// @expect result == 5` means result[0] = 1, result[1] = 0,
   result[2] = 1.

Called by scripts/validate-content.sh and by `vidya validate`
(validate_command in src/vidya_core.cyr); change both together.
"""
import re
import sys

SHOTS = 2048
SEED = 1234
EXPECT = re.compile(r'//\s*@expect\s+(\w+)\s*(==|in)\s*(.+?)\s*$')


def parse_expectations(src):
    out = []
    for n, line in enumerate(src.split('\n'), 1):
        if '@expect' not in line:
            continue
        m = EXPECT.search(line)
        if not m:
            raise SystemExit('line %d: malformed @expect: %s' % (n, line.strip()))
        reg, op, rhs = m.groups()
        if op == '==':
            if not re.fullmatch(r'\d+', rhs):
                raise SystemExit('line %d: @expect %s == needs an integer, got %r' % (n, reg, rhs))
            out.append((n, reg, op, {int(rhs)}))
        else:
            if not re.fullmatch(r'\{\s*\d+(\s*,\s*\d+)*\s*\}', rhs):
                raise SystemExit('line %d: @expect %s in needs {int, ...}, got %r' % (n, reg, rhs))
            out.append((n, reg, op, {int(v) for v in re.findall(r'\d+', rhs)}))
    return out


def register_values(qc, counts):
    """{creg name: {int value: shots}}; qiskit prints the last creg first."""
    vals = {}
    for key, n in counts.items():
        for reg, bits in zip(qc.cregs, key.split(' ')[::-1]):
            v = int(bits, 2)
            vals.setdefault(reg.name, {}).setdefault(v, 0)
            vals[reg.name][v] += n
    return vals


def main():
    path = sys.argv[1]
    src = open(path, encoding='utf-8').read()
    from qiskit import qasm3
    qc = qasm3.loads(src)
    print('OpenQASM OK: %dq, depth %d' % (qc.num_qubits, qc.depth()))
    expects = parse_expectations(src)
    if not expects:
        return 0
    names = {r.name for r in qc.cregs}
    for n, reg, _, _ in expects:
        if reg not in names:
            raise SystemExit('line %d: @expect names %r, which is not a classical register' % (n, reg))
    from qiskit import transpile
    from qiskit_aer import AerSimulator
    method = 'automatic' if qc.num_qubits <= 20 else 'matrix_product_state'
    sim = AerSimulator(method=method, seed_simulator=SEED)
    counts = sim.run(transpile(qc, sim), shots=SHOTS).result().get_counts()
    vals = register_values(qc, counts)
    failed = 0
    for n, reg, op, want in expects:
        seen = vals.get(reg, {})
        stray = sorted(set(seen) - want)
        missing = sorted(want - set(seen))
        if stray or (op == 'in' and missing):
            failed += 1
            print('line %d: @expect %s %s %s — measured %s' % (
                n, reg, op, sorted(want), dict(sorted(seen.items()))))
    if failed:
        print('%d of %d @expect lines failed' % (failed, len(expects)))
        return 1
    print('@expect: %d checked in %d shots' % (len(expects), SHOTS))
    return 0


sys.exit(main())
