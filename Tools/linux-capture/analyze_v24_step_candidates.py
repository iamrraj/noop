#!/usr/bin/env python3
"""analyze_v24_step_candidates.py — look for a step counter in WHOOP 4.0 type-47 *version-24* records.

The 4.0 counts steps on the strap, but no wire field for the count is mapped: the v24 layout leaves
bytes 15-20, 37-39, 52-54 and everything from 84 to the CRC unnamed. This script tests every unnamed
byte and little-endian u16 in those regions for the behaviour a cumulative step counter must have,
using the record's own motion (the gravity vector at 40/44/48) as internal ground truth:

  - it only ever goes up, apart from a wrap back through zero;
  - it climbs in seconds where the wrist is moving and stays flat where it is still;
  - over a walk of known length its total rise is the number of steps taken (--expected-steps).

A field that passes on ONE capture is a candidate, not a finding. A fixed-size record can carry a
value that happens to rise with activity (an HR-derived accumulator, a record index); the counter is
only established once it tracks walks of different lengths on more than one strap.

Usage:
  python3 analyze_v24_step_candidates.py capture.json [--expected-steps 1200]

capture.json is the list `whoop_sync.py export --only-type 47` writes: [{"hex": "aa64…"}, …].
"""

import argparse
import json
import math
import struct
import sys

from capture_io import configure_utf8_stdio

TYPE_HISTORICAL = 0x2F
VERSION_V24 = 24
TS_OFFSET = 11
GRAVITY_OFFSETS = (40, 44, 48)
CRC_BYTES = 4
# Unnamed regions of the v24 layout, as (first, last) inclusive frame offsets; the open-ended tail is
# bounded per frame by its own length.
UNMAPPED = ((15, 20), (37, 39), (52, 54))
TAIL_START = 84
# A gravity change this large between consecutive seconds counts as the wrist moving.
MOVING_DELTA_G = 0.05
# Faster than any human cadence, so a larger one-second rise is a reset or a different kind of field.
MAX_RISE_PER_SECOND = 6


def load_v24(path):
    """Return the capture's v24 records as bytes, oldest first, one per unix second."""
    with open(path, encoding="utf-8") as handle:
        entries = json.load(handle)
    by_ts = {}
    for entry in entries:
        text = entry.get("hex") if isinstance(entry, dict) else entry
        try:
            frame = bytes.fromhex(text)
        except (TypeError, ValueError):
            continue
        if len(frame) <= TAIL_START + CRC_BYTES or frame[0] != 0xAA:
            continue
        if frame[4] != TYPE_HISTORICAL or frame[5] != VERSION_V24:
            continue
        by_ts[struct.unpack_from("<I", frame, TS_OFFSET)[0]] = frame
    return [by_ts[ts] for ts in sorted(by_ts)]


def motion(frames):
    """Per-record wrist movement: the gravity vector's change from the previous record."""
    out = [0.0]
    previous = None
    for frame in frames:
        vector = tuple(struct.unpack_from("<f", frame, off)[0] for off in GRAVITY_OFFSETS)
        if previous is not None:
            delta = math.sqrt(sum((a - b) ** 2 for a, b in zip(vector, previous)))
            out.append(delta if math.isfinite(delta) else 0.0)
        previous = vector
    return out[: len(frames)]


def candidate_fields(frames):
    """Every (offset, width) inside the unnamed regions that exists in all frames."""
    shortest = min(len(frame) for frame in frames)
    regions = list(UNMAPPED) + [(TAIL_START, shortest - CRC_BYTES - 1)]
    fields = []
    for first, last in regions:
        for offset in range(first, last + 1):
            fields.append((offset, 1))
            if offset + 1 <= last:
                fields.append((offset, 2))
    return fields


def score_field(frames, moves, offset, width):
    """Measure how counter-like one field is. Returns None for a field that never changes."""
    modulus = 1 << (8 * width)
    fmt = "<H" if width == 2 else "<B"
    values = [struct.unpack_from(fmt, frame, offset)[0] for frame in frames]
    if len(set(values)) < 2:
        return None
    total = 0
    violations = 0
    rise_moving = rise_still = 0
    moving_seconds = still_seconds = 0
    for index in range(1, len(values)):
        rise = (values[index] - values[index - 1]) % modulus
        is_moving = moves[index] >= MOVING_DELTA_G
        moving_seconds += is_moving
        still_seconds += not is_moving
        if rise > MAX_RISE_PER_SECOND:
            violations += 1
            continue
        total += rise
        if is_moving:
            rise_moving += rise
        else:
            rise_still += rise
    steps = len(values) - 1
    rate_moving = rise_moving / moving_seconds if moving_seconds else 0.0
    rate_still = rise_still / still_seconds if still_seconds else 0.0
    return {
        "offset": offset,
        "width": width,
        "total": total,
        "monotonic": 1.0 - violations / steps,
        "rate_moving": rate_moving,
        "rate_still": rate_still,
    }


def is_counter_like(result):
    """The gate a candidate must clear: almost never jumps, rises while moving, flat while still."""
    return (
        result["monotonic"] >= 0.98
        and result["total"] > 0
        and result["rate_moving"] > 0
        and result["rate_moving"] >= 5 * result["rate_still"]
    )


def rank(frames, expected_steps=None):
    """Counter-like fields, best first. With expected_steps, closest total first."""
    if len(frames) < 3:
        return []
    moves = motion(frames)
    results = []
    for offset, width in candidate_fields(frames):
        result = score_field(frames, moves, offset, width)
        if result is not None and is_counter_like(result):
            results.append(result)
    # The low byte of a wider counter is counter-like too, so on a tie the wider reading wins.
    if expected_steps:
        results.sort(key=lambda r: (abs(r["total"] - expected_steps), -r["width"]))
    else:
        results.sort(key=lambda r: (r["rate_still"], -r["rate_moving"], -r["width"]))
    return results


def main(argv=None):
    configure_utf8_stdio()
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("capture")
    parser.add_argument("--expected-steps", type=int, default=None,
                        help="steps counted independently over the same span (phone or by hand)")
    args = parser.parse_args(argv)

    frames = load_v24(args.capture)
    if len(frames) < 3:
        print(f"Only {len(frames)} v24 records in {args.capture}; need a capture spanning a walk.")
        return 1
    moves = motion(frames)
    moving = sum(1 for m in moves if m >= MOVING_DELTA_G)
    print(f"{len(frames)} v24 records, {moving} s moving, {len(frames) - moving} s still.")
    if moving == 0 or moving == len(frames):
        print("The capture needs BOTH walking and sitting still, or no field can be told from a clock.")
        return 1

    results = rank(frames, args.expected_steps)
    if not results:
        print("No unnamed field behaves like a step counter in this capture.")
        return 0
    print("offset width  total  monotonic  rise/s moving  rise/s still")
    for r in results[:10]:
        print(f"{r['offset']:>6} {r['width']:>5} {r['total']:>6} {r['monotonic']:>10.3f} "
              f"{r['rate_moving']:>14.3f} {r['rate_still']:>13.3f}")
    if args.expected_steps:
        best = results[0]
        error = abs(best["total"] - args.expected_steps) / args.expected_steps * 100
        print(f"Closest to {args.expected_steps} expected steps: offset {best['offset']} "
              f"(width {best['width']}) at {best['total']}, {error:.1f}% off.")
    print("A candidate is not a finding until it tracks walks of different lengths.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
