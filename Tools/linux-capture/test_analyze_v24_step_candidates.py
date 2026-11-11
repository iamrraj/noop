"""Unit tests for the v24 step-counter candidate search (synthetic records; stdlib only)."""

import json
import os
import struct
import tempfile
import unittest

import analyze_v24_step_candidates as mod

FRAME_LEN = 104
BASE_TS = 1_780_000_000


def make_frame(ts, gravity, fields=None, version=24, frame_type=0x2F):
    frame = bytearray(FRAME_LEN)
    frame[0] = 0xAA
    frame[4] = frame_type
    frame[5] = version
    struct.pack_into("<I", frame, mod.TS_OFFSET, ts)
    for offset, value in zip(mod.GRAVITY_OFFSETS, gravity):
        struct.pack_into("<f", frame, offset, value)
    for (offset, width), value in (fields or {}).items():
        struct.pack_into("<H" if width == 2 else "<B", frame, offset, value % (1 << (8 * width)))
    return bytes(frame)


def walk_then_sit(walk_seconds=120, sit_seconds=120, start_count=0, extra=None):
    """A walk at two steps a second followed by sitting still, with a counter planted at 92."""
    frames = []
    count = start_count
    for second in range(walk_seconds + sit_seconds):
        walking = second < walk_seconds
        # The arm keeps swinging through the second in which the last step lands.
        swing = 0.3 if (second <= walk_seconds and second % 2) else 0.0
        fields = {(92, 2): count}
        if extra:
            fields.update(extra(second, walking))
        frames.append(make_frame(BASE_TS + second, (swing, 0.0, 1.0), fields))
        if walking:
            count += 2
    return frames


class LoadTests(unittest.TestCase):
    def write(self, entries):
        handle = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8")
        json.dump(entries, handle)
        handle.close()
        self.addCleanup(os.unlink, handle.name)
        return handle.name

    def test_keeps_only_v24_sorted_and_deduplicated(self):
        a = make_frame(BASE_TS + 2, (0, 0, 1))
        b = make_frame(BASE_TS + 1, (0, 0, 1))
        path = self.write([
            {"hex": a.hex()}, {"hex": b.hex()}, {"hex": b.hex()},
            {"hex": make_frame(BASE_TS, (0, 0, 1), version=25).hex()},
            {"hex": make_frame(BASE_TS, (0, 0, 1), frame_type=0x28).hex()},
            {"hex": "zz"}, {"hex": "aa00"}, {"nohex": 1}, a.hex(),
        ])
        self.assertEqual(mod.load_v24(path), [b, a])

    def test_empty_capture(self):
        self.assertEqual(mod.load_v24(self.write([])), [])


class MotionTests(unittest.TestCase):
    def test_first_record_has_no_motion_and_deltas_follow(self):
        frames = [make_frame(BASE_TS + i, g) for i, g in enumerate([(0, 0, 1), (0.3, 0, 1), (0.3, 0, 1)])]
        moves = mod.motion(frames)
        self.assertEqual(moves[0], 0.0)
        self.assertAlmostEqual(moves[1], 0.3, places=5)
        self.assertEqual(moves[2], 0.0)

    def test_non_finite_gravity_counts_as_still(self):
        frames = [make_frame(BASE_TS, (0, 0, 1)), make_frame(BASE_TS + 1, (float("nan"), 0, 1))]
        self.assertEqual(mod.motion(frames), [0.0, 0.0])


class RankTests(unittest.TestCase):
    def test_planted_counter_is_found(self):
        results = mod.rank(walk_then_sit())
        self.assertTrue(results)
        self.assertEqual((results[0]["offset"], results[0]["width"]), (92, 2))
        self.assertEqual(results[0]["total"], 240)
        self.assertEqual(results[0]["rate_still"], 0.0)

    def test_counter_survives_a_u16_wrap(self):
        results = mod.rank(walk_then_sit(start_count=65_500))
        self.assertEqual((results[0]["offset"], results[0]["width"]), (92, 2))
        self.assertEqual(results[0]["total"], 240)

    def test_recovers_different_walk_lengths(self):
        for seconds in (30, 90, 300):
            with self.subTest(seconds=seconds):
                best = mod.rank(walk_then_sit(walk_seconds=seconds), expected_steps=seconds * 2)[0]
                self.assertEqual((best["offset"], best["total"]), (92, seconds * 2))

    def test_a_clock_like_field_is_rejected(self):
        # Rises every second whether or not the wrist moves: a record index, not a step counter.
        frames = walk_then_sit(extra=lambda second, walking: {(96, 2): second})
        offsets = {(r["offset"], r["width"]) for r in mod.rank(frames)}
        self.assertNotIn((96, 2), offsets)
        self.assertIn((92, 2), offsets)

    def test_a_noisy_field_is_rejected(self):
        frames = walk_then_sit(extra=lambda second, walking: {(88, 1): (second * 97) % 251})
        self.assertNotIn(88, {r["offset"] for r in mod.rank(frames)})

    def test_no_counter_present(self):
        frames = [make_frame(BASE_TS + i, (0.3 if i % 2 else 0.0, 0, 1)) for i in range(60)]
        frames += [make_frame(BASE_TS + 60 + i, (0, 0, 1)) for i in range(60)]
        self.assertEqual(mod.rank(frames), [])

    def test_too_few_records(self):
        self.assertEqual(mod.rank(walk_then_sit()[:2]), [])
        self.assertEqual(mod.rank([]), [])

    def test_constant_field_scores_none(self):
        frames = walk_then_sit()
        self.assertIsNone(mod.score_field(frames, mod.motion(frames), 86, 1))

    def test_expected_steps_orders_by_closeness(self):
        # A second counter at half the rate also looks counter-like; the expectation picks the right one.
        frames = walk_then_sit(extra=lambda second, walking: {(96, 2): min(second, 120)})
        best = mod.rank(frames, expected_steps=240)[0]
        self.assertEqual(best["offset"], 92)


class MainTests(unittest.TestCase):
    def run_main(self, frames, *args):
        handle = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8")
        json.dump([{"hex": f.hex()} for f in frames], handle)
        handle.close()
        self.addCleanup(os.unlink, handle.name)
        return mod.main([handle.name, *args])

    def test_exit_codes(self):
        self.assertEqual(self.run_main(walk_then_sit(), "--expected-steps", "240"), 0)
        self.assertEqual(self.run_main([]), 1)
        # All still: nothing can be told apart from a clock.
        self.assertEqual(self.run_main([make_frame(BASE_TS + i, (0, 0, 1)) for i in range(20)]), 1)


if __name__ == "__main__":
    unittest.main()
