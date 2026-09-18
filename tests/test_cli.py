from __future__ import annotations

import importlib.machinery
import importlib.util
import io
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch


CLI = Path(__file__).parents[1] / "desk-lights"
LOADER = importlib.machinery.SourceFileLoader("desk_lights", str(CLI))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC is not None
desk_lights = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(desk_lights)


class CLITest(unittest.TestCase):
    def test_pink_sets_solid_colour_and_brightness(self) -> None:
        self.assertEqual(
            desk_lights.state_payload("pink", 200),
            {
                "on": True,
                "bri": 200,
                "seg": [{"id": 0, "fx": 0, "col": [[255, 20, 147]]}],
            },
        )

    def test_blue_sets_solid_colour(self) -> None:
        self.assertEqual(
            desk_lights.state_payload("blue", None),
            {
                "on": True,
                "seg": [{"id": 0, "fx": 0, "col": [[0, 122, 255]]}],
            },
        )

    def test_pulse_uses_breathe_and_keeps_current_colour(self) -> None:
        self.assertEqual(
            desk_lights.state_payload("pulse", None),
            {"on": True, "seg": [{"id": 0, "fx": 2}]},
        )

    def test_status_reports_controller_state(self) -> None:
        state = {"on": True, "bri": 128, "seg": [{"fx": 2}]}
        output = io.StringIO()
        with patch.object(desk_lights, "request_json", return_value=state) as request:
            with redirect_stdout(output):
                result = desk_lights.main(["status", "--host", "lights.test"])

        self.assertEqual(result, 0)
        self.assertEqual(output.getvalue().strip(), "Desk lights: on, brightness 128, effect 2")
        request.assert_called_once_with("lights.test", "/json/state")


if __name__ == "__main__":
    unittest.main()
