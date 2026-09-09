"""
Compare two MOM6 ocean.stats files field by field.

Usage: compare_ocean_stats.py ref.stats new.stats [rel_tol]

Every numeric field on every step line must agree to within rel_tol, compared
relatively for large values and absolutely for values near zero. Truncation
counts must match exactly. Exits non-zero on the first kind of mismatch found.
"""
import re
import sys

NUM = re.compile(r'[-+]?\d*\.?\d+(?:[EeDd][-+]?\d+)?')


def step_lines(path):
    with open(path) as f:
        return [ln for ln in f if re.match(r'\s*\d+,', ln)]


def values(line):
    return [float(v.replace('D', 'E').replace('d', 'e')) for v in NUM.findall(line)]


def main():
    ref_path, new_path = sys.argv[1], sys.argv[2]
    rel_tol = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0e-9

    ref, new = step_lines(ref_path), step_lines(new_path)
    if len(ref) != len(new):
        print(f'  FAIL: {len(new)} step rows, reference has {len(ref)}')
        return 1

    worst, worst_at = 0.0, None
    for row, (a, b) in enumerate(zip(ref, new)):
        va, vb = values(a), values(b)
        if len(va) != len(vb):
            print(f'  FAIL: row {row} has {len(vb)} fields, reference has {len(va)}')
            return 1
        # Field 2 is the truncation count; it must match exactly.
        if va[2] != vb[2]:
            print(f'  FAIL: row {row} truncations {vb[2]:.0f}, reference {va[2]:.0f}')
            return 1
        for col, (x, y) in enumerate(zip(va, vb)):
            diff = abs(x - y) / max(abs(x), 1.0)
            if diff > worst:
                worst, worst_at = diff, (row, col)

    if worst > rel_tol:
        row, col = worst_at
        print(f'  FAIL: largest difference {worst:.3e} at row {row}, field {col}')
        return 1
    print(f'  OK: largest difference {worst:.3e}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
