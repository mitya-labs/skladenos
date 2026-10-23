"""Логика сторожевой службы тача без железа:  python3 -m unittest discover -s packages/skladenos-config/tests"""
import importlib.machinery, importlib.util, os, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PATH = os.path.join(HERE, "..", "files", "usr", "sbin", "skladenos-touch-watchdog")
loader = importlib.machinery.SourceFileLoader("touch_watchdog", PATH)
spec = importlib.util.spec_from_loader("touch_watchdog", loader)
tw = importlib.util.module_from_spec(spec)
loader.exec_module(tw)

FREE = (-1, 0, 0)


class Detector(unittest.TestCase):
    def det(self):
        return tw.StuckDetector(stuck_secs=10, max_move=40)

    def test_no_touch(self):
        d = self.det()
        for t in range(0, 100, 5):
            self.assertFalse(d.update(t, [FREE] * 5))

    def test_stuck_touch_detected_after_threshold(self):
        d = self.det()
        self.assertFalse(d.update(0, [FREE, (164, 500, 900)] + [FREE] * 3))
        self.assertFalse(d.update(9, [FREE, (164, 502, 901)] + [FREE] * 3))
        self.assertTrue(d.update(10, [FREE, (164, 503, 903)] + [FREE] * 3))

    def test_slow_drift_still_stuck(self):
        """Из STATE п.148: за 65 с сдвиг 17 пикселей — всё равно застряло."""
        d = self.det()
        ok = [d.update(t, [FREE, (164, 500 + t // 4, 900)] + [FREE] * 3) for t in range(0, 66, 5)]
        self.assertTrue(ok[-1])

    def test_real_swipe_is_not_stuck(self):
        d = self.det()
        for t in range(0, 30):  # палец долго ведут по экрану
            self.assertFalse(d.update(t, [(7, 100 + t * 30, 900)] + [FREE] * 4))

    def test_new_tracking_id_restarts_timer(self):
        d = self.det()
        d.update(0, [(1, 500, 900)])
        self.assertFalse(d.update(9, [(1, 500, 900)]))
        self.assertFalse(d.update(10, [(2, 500, 900)]))  # другое касание
        self.assertFalse(d.update(15, [(2, 500, 900)]))
        self.assertTrue(d.update(20, [(2, 500, 900)]))

    def test_release_clears_state(self):
        d = self.det()
        d.update(0, [(1, 500, 900)])
        d.update(8, [FREE])
        self.assertFalse(d.update(12, [(1, 500, 900)]))  # палец убрали и приложили, tracking_id тот же

    def test_second_slot_stuck_while_first_is_active(self):
        d = self.det()
        for t in range(0, 12):
            stuck = d.update(t, [(10 + t, 100 + t * 50, 300), (164, 500, 900)])
        self.assertTrue(stuck)


class BackoffTest(unittest.TestCase):
    def test_doubles_and_caps_then_calms(self):
        b = tw.Backoff()
        self.assertTrue(b.allowed(0))
        b.fired(0)
        self.assertFalse(b.allowed(10))
        self.assertTrue(b.allowed(30))
        b.fired(30)
        self.assertEqual(b.pause, 60)
        t = 30
        for _ in range(10):
            t += b.pause
            b.fired(t)
        self.assertEqual(b.pause, tw.COOLDOWN_MAX)
        b.fired(t + tw.CALM_RESET + 1)
        self.assertEqual(b.pause, tw.COOLDOWN_MIN)


class Ioctl(unittest.TestCase):
    def test_request_codes_match_kernel(self):
        # EVIOCGMTSLOTS(len) = _IOC(_IOC_READ, 'E', 0x0a, len); EVIOCGABS(0x2f) = 0x80184576
        self.assertEqual(tw._ioc_read(0x40 + tw.ABS_MT_SLOT, 24), 0x8018456F)
        self.assertEqual(tw._ioc_read(0x0A, 44), 0x802C450A)


if __name__ == "__main__":
    unittest.main()
