from __future__ import annotations

import tempfile
from pathlib import Path
import unittest
import json

from tools import validate_promotion_packets


class PromotionPacketValidationTests(unittest.TestCase):
    def test_checked_in_manifest_is_valid(self) -> None:
        validate_promotion_packets.validate_manifest()

    def test_three_three_live_negative_fixture_pins_non_promotion_facts(self) -> None:
        fixture_path = (
            validate_promotion_packets.REPO_ROOT
            / "tools"
            / "fixtures"
            / "promotion_packets"
            / "phase5_003_003_zone1_cellar_to_cube19_live_negative.json"
        )
        proof = json.loads(fixture_path.read_text(encoding="utf-8"))

        self.assertEqual("promotion-packet-evidence-v1", proof["schema"])
        self.assertEqual("phase5_003_003_zone1_cellar_to_cube19", proof["packet_id"])
        self.assertEqual("live_negative", proof["status"])
        self.assertEqual("zone_transition", proof["evidence_class"])
        self.assertEqual(3, proof["source"]["scene"])
        self.assertEqual(3, proof["source"]["background"])
        self.assertEqual(1, proof["source"]["zone_index"])
        self.assertEqual(19, proof["decoded_candidate"]["destination_cube"])
        observations = proof["live_observations"]
        self.assertTrue(observations["direct_center_zone_membership_observed"])
        self.assertTrue(observations["edge_crossing_attempted"])
        self.assertFalse(observations["new_cube_19_observed"])
        self.assertFalse(observations["active_cube_19_observed"])
        self.assertFalse(observations["new_pos_observed"])
        self.assertEqual(1024, observations["final_y"])
        self.assertEqual("decoded_candidate_live_negative", proof["verdict"])

    def test_canonical_runtime_requires_promotable_status(self) -> None:
        packet = {
            "id": "bad_decode_runtime",
            "status": "decode_only",
            "evidence_class": "zone_transition",
            "packet": "docs/promotion_packets/TEMPLATE.md",
            "fixture": None,
            "runtime_contracts": [],
            "canonical_runtime": True,
        }

        with self.assertRaisesRegex(
            validate_promotion_packets.PacketValidationError,
            "canonical_runtime=true requires",
        ):
            validate_promotion_packets.validate_packet_entry(packet, set())

    def test_packet_doc_identity_must_match_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            packet_path = Path(tmp) / "packet.md"
            packet_path.write_text(
                "\n".join(
                    [
                        "# Packet",
                        "## Packet Identity",
                        "- `id`: `wrong`",
                        "- `status`: `live_positive`",
                        "- `evidence_class`: `zone_transition`",
                        "- `canonical_runtime`: `true`",
                        "## Exact Seam Identity",
                        "## Decode Evidence",
                        "## Original Runtime Live Evidence",
                        "## Runtime Invariant",
                        "## Positive Test",
                        "## Negative Test",
                        "## Reproduction Command",
                        "## Failure Mode",
                        "## Docs And Memory",
                        "## Old Hypothesis Handling",
                        "## Revision History",
                    ]
                ),
                encoding="utf-8",
            )

            with self.assertRaisesRegex(
                validate_promotion_packets.PacketValidationError,
                "packet identity does not match",
            ):
                validate_promotion_packets.validate_packet_doc(
                    "expected",
                    "live_positive",
                    "zone_transition",
                    True,
                    packet_path,
                )

    def test_runtime_contract_coverage_rejects_unpacketed_contract(self) -> None:
        with self.assertRaisesRegex(
            validate_promotion_packets.PacketValidationError,
            "missing promotable packets",
        ):
            validate_promotion_packets.validate_runtime_contract_coverage(
                {"secret_room_key_gate_to_cellar", "new_unpacketed_contract"},
                {"secret_room_key_gate_to_cellar"},
            )

    def test_discovers_current_cli_runtime_contracts(self) -> None:
        contracts = validate_promotion_packets.discover_runtime_contracts()

        self.assertIn("secret_room_key_gate_to_cellar", contracts)
        self.assertIn("secret_room_cellar_return_free", contracts)


if __name__ == "__main__":
    unittest.main()
