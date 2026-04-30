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

    def test_three_three_zone8_live_negative_fixture_pins_non_promotion_facts(self) -> None:
        fixture_path = (
            validate_promotion_packets.REPO_ROOT
            / "tools"
            / "fixtures"
            / "promotion_packets"
            / "phase5_003_003_zone8_cellar_to_cube20_live_negative.json"
        )
        proof = json.loads(fixture_path.read_text(encoding="utf-8"))

        self.assertEqual("promotion-packet-evidence-v1", proof["schema"])
        self.assertEqual("phase5_003_003_zone8_cellar_to_cube20", proof["packet_id"])
        self.assertEqual("live_negative", proof["status"])
        self.assertEqual("zone_transition", proof["evidence_class"])
        self.assertEqual(3, proof["source"]["scene"])
        self.assertEqual(3, proof["source"]["background"])
        self.assertEqual(8, proof["source"]["zone_index"])
        self.assertEqual(20, proof["decoded_candidate"]["destination_cube"])
        observations = proof["live_observations"]
        self.assertTrue(observations["direct_center_zone_membership_observed"])
        self.assertFalse(observations["edge_crossing_attempted"])
        self.assertFalse(observations["new_cube_20_observed"])
        self.assertFalse(observations["active_cube_20_observed"])
        self.assertFalse(observations["new_pos_observed"])
        self.assertTrue(observations["life_loss_observed"])
        self.assertEqual(4, observations["final_clovers"])
        self.assertEqual(1024, observations["final_y"])
        self.assertEqual("decoded_candidate_live_negative_life_loss", proof["verdict"])

    def test_magic_ball_live_positive_fixture_pins_inventory_signal(self) -> None:
        fixture_path = (
            validate_promotion_packets.REPO_ROOT
            / "tools"
            / "fixtures"
            / "promotion_packets"
            / "phase5_magic_ball_pickup_live_positive.json"
        )
        proof = json.loads(fixture_path.read_text(encoding="utf-8"))

        self.assertEqual("promotion-packet-evidence-v1", proof["schema"])
        self.assertEqual("phase5_magic_ball_pickup", proof["packet_id"])
        self.assertEqual("live_positive", proof["status"])
        self.assertEqual("inventory_state", proof["evidence_class"])
        self.assertEqual(1, proof["classic_symbols"]["FLAG_BALLE_MAGIQUE"])
        self.assertEqual(0, proof["initial"]["magic_ball_flag"])
        self.assertEqual(1, proof["observed_transition"]["magic_ball_flag_after"])
        self.assertEqual(1, proof["final"]["magic_ball_flag"])
        self.assertEqual("SAVE\\new-game-cellar.LBA", proof["repeatable_launch"]["launched_save"])
        self.assertTrue(proof["repeatable_launch"]["autosave_hidden"])
        self.assertEqual(0, proof["repeatable_launch"]["initial"]["magic_ball_flag"])
        self.assertEqual(1, proof["repeatable_launch"]["observed_transition"]["magic_ball_flag_after"])
        self.assertEqual(1, proof["repeatable_launch"]["final"]["magic_ball_flag"])
        self.assertTrue(proof["observations"]["magic_ball_flag_0_to_1_observed"])
        self.assertTrue(proof["observations"]["repeatable_launch_magic_ball_flag_0_to_1_observed"])
        self.assertFalse(proof["observations"]["magic_level_changed"])
        self.assertFalse(proof["observations"]["magic_point_changed"])
        self.assertFalse(proof["observations"]["inventory_model_id_changed"])
        self.assertEqual("inventory_state_live_positive", proof["verdict"])

    def test_magic_ball_throw_live_positive_fixture_pins_projectile_launch(self) -> None:
        fixture_path = (
            validate_promotion_packets.REPO_ROOT
            / "tools"
            / "fixtures"
            / "promotion_packets"
            / "phase5_magic_ball_throw_projectile_launch_live_positive.json"
        )
        proof = json.loads(fixture_path.read_text(encoding="utf-8"))

        self.assertEqual("promotion-packet-evidence-v1", proof["schema"])
        self.assertEqual("phase5_magic_ball_throw_projectile_launch", proof["packet_id"])
        self.assertEqual("live_positive", proof["status"])
        self.assertEqual("collision_locomotion", proof["evidence_class"])
        self.assertEqual(1, proof["classic_symbols"]["FLAG_BALLE_MAGIQUE"])
        self.assertEqual("period", proof["launch_input"]["key"])
        self.assertEqual("hold_then_release", proof["launch_input"]["source_semantics"])
        self.assertEqual(0.75, proof["launch_input"]["conservative_hold_sec"])
        self.assertEqual(1, proof["initial"]["magic_ball_flag"])

        expected = {
            "normal": (-55, 18, 81, 0.63),
            "sporty": (-58, 13, 86, 0.63),
            "aggressive": (-62, 7, 91, 0.62),
            "discreet": (-36, 77, 53, 0.63),
        }
        for mode, (vx, vy, vz, hold_sec) in expected.items():
            projectile = proof["observed_projectiles"][mode]
            self.assertEqual(8, projectile["sprite"])
            self.assertEqual(33038, projectile["flags"])
            self.assertEqual(5071, projectile["org_x"])
            self.assertEqual(2224, projectile["org_y"])
            self.assertEqual(1820, projectile["org_z"])
            self.assertEqual(vx, projectile["vx"])
            self.assertEqual(vy, projectile["vy"])
            self.assertEqual(vz, projectile["vz"])
            self.assertEqual(hold_sec, projectile["hold_sec"])

        self.assertFalse(proof["negative_thresholds"]["normal_0_62_sec_launched"])
        self.assertFalse(proof["negative_thresholds"]["sporty_0_62_sec_launched"])
        self.assertFalse(proof["negative_thresholds"]["aggressive_0_61_sec_launched"])
        self.assertFalse(proof["negative_thresholds"]["discreet_0_62_sec_launched"])
        self.assertTrue(proof["observations"]["mode_dependent_velocity_observed"])
        self.assertFalse(proof["observations"]["damage_observed"])
        self.assertFalse(proof["observations"]["bounce_observed"])
        self.assertEqual("projectile_launch_live_positive", proof["verdict"])

    def test_magic_ball_bounce_return_live_positive_fixture_pins_wall_repeats(self) -> None:
        fixture_path = (
            validate_promotion_packets.REPO_ROOT
            / "tools"
            / "fixtures"
            / "promotion_packets"
            / "phase5_magic_ball_bounce_return_wall_repeat_live_positive.json"
        )
        proof = json.loads(fixture_path.read_text(encoding="utf-8"))

        self.assertEqual("promotion-packet-evidence-v1", proof["schema"])
        self.assertEqual("phase5_magic_ball_bounce_return_wall_repeat", proof["packet_id"])
        self.assertEqual("live_positive", proof["status"])
        self.assertEqual("collision_locomotion", proof["evidence_class"])
        self.assertEqual("period", proof["launch_input"]["key"])
        self.assertEqual("hold_then_release", proof["launch_input"]["source_semantics"])
        self.assertEqual(0.75, proof["launch_input"]["hold_sec"])
        self.assertEqual("normal", proof["launch_input"]["mode"])

        runs = proof["observed_runs"]
        self.assertEqual(4, len(runs))
        self.assertEqual(1, runs[0]["magic_level"])
        self.assertEqual(4, runs[0]["bounce_count"])
        self.assertEqual([["vx"], ["vy"], ["vy"], ["vx"]], runs[0]["bounce_flips"])
        self.assertEqual(1, runs[0]["return_count"])
        self.assertTrue(runs[0]["cleared"])
        self.assertEqual(4, runs[2]["magic_level"])
        self.assertEqual(4, runs[2]["bounce_count"])
        self.assertEqual([["vy"], ["vy"], ["vz"], ["vx"]], runs[2]["bounce_flips"])
        self.assertEqual(0, runs[2]["return_count"])
        self.assertTrue(runs[2]["cleared"])

        self.assertTrue(proof["observations"]["repeated_twice_per_save"])
        self.assertTrue(proof["observations"]["bounce_observed"])
        self.assertTrue(proof["observations"]["list_extra_velocity_sign_flip_observed"])
        self.assertTrue(proof["observations"]["list_extra_origin_timer_reset_observed"])
        self.assertTrue(proof["observations"]["magic_point_consumed"])
        self.assertTrue(proof["observations"]["level1_return_sprite_observed"])
        self.assertFalse(proof["observations"]["fire_return_sprite_sampled"])
        self.assertFalse(proof["observations"]["damage_observed"])
        self.assertFalse(proof["observations"]["switch_activation_observed"])
        self.assertFalse(proof["observations"]["remote_pickup_observed"])
        self.assertEqual("wall_bounce_return_live_positive", proof["verdict"])

    def test_magic_ball_enemy_damage_tralu_level1_fixture_pins_repeated_damage(self) -> None:
        fixture_path = (
            validate_promotion_packets.REPO_ROOT
            / "tools"
            / "fixtures"
            / "promotion_packets"
            / "phase5_magic_ball_enemy_damage_tralu_level1_live_positive.json"
        )
        proof = json.loads(fixture_path.read_text(encoding="utf-8"))

        self.assertEqual("promotion-packet-evidence-v1", proof["schema"])
        self.assertEqual("phase5_magic_ball_enemy_damage_tralu_level1", proof["packet_id"])
        self.assertEqual("live_positive", proof["status"])
        self.assertEqual("collision_locomotion", proof["evidence_class"])
        self.assertEqual("tralu-attack.LBA", proof["source"]["save"])
        self.assertEqual(3, proof["source"]["enemy_object_index"])
        self.assertEqual(0, proof["source"]["hero_object_index"])
        self.assertEqual(1, proof["initial"]["magic_level"])
        self.assertEqual(13, proof["initial"]["magic_point"])
        self.assertEqual(1, proof["initial"]["magic_ball_flag"])
        self.assertEqual("period", proof["launch_input"]["key"])
        self.assertEqual("hold_then_release", proof["launch_input"]["source_semantics"])
        self.assertEqual(0.75, proof["launch_input"]["hold_sec"])
        self.assertEqual(1.0, proof["launch_input"]["ready_delay_sec"])
        self.assertEqual(0.7, proof["launch_input"]["second_throw_after_first_tralu_hit_sec"])

        self.assertEqual(2, len(proof["observed_runs"]))
        for run in proof["observed_runs"]:
            self.assertEqual(3, run["tralu_object_index"])
            self.assertEqual(0, run["twinsen_object_index"])
            self.assertEqual(
                [(72, 63, 9), (63, 54, 9)],
                [
                    (event["before"], event["after"], event["damage"])
                    for event in run["tralu_life_events"]
                ],
            )
            self.assertEqual(194, run["twinsen_life_events"][0]["before"])
            self.assertLess(run["tralu_life_events"][1]["t"], run["twinsen_life_events"][0]["t"])

        self.assertTrue(proof["observations"]["tralu_damage_observed"])
        self.assertEqual(9, proof["observations"]["tralu_damage_per_hit"])
        self.assertEqual(2, proof["observations"]["tralu_hits_per_run"])
        self.assertTrue(proof["observations"]["tralu_damage_discriminated_from_twinsen_damage"])
        self.assertTrue(proof["observations"]["magic_level_1_only"])
        self.assertFalse(proof["observations"]["damage_scaling_observed"])
        self.assertFalse(proof["observations"]["enemy_vulnerability_table_observed"])
        self.assertFalse(proof["observations"]["switch_activation_observed"])
        self.assertFalse(proof["observations"]["remote_pickup_observed"])
        self.assertEqual("enemy_damage_tralu_level1_live_positive", proof["verdict"])

    def test_magic_ball_switch_activation_emerald_moon_fixture_pins_scoped_switch_hits(self) -> None:
        fixture_path = (
            validate_promotion_packets.REPO_ROOT
            / "tools"
            / "fixtures"
            / "promotion_packets"
            / "phase5_magic_ball_switch_activation_emerald_moon_live_positive.json"
        )
        proof = json.loads(fixture_path.read_text(encoding="utf-8"))

        self.assertEqual("promotion-packet-evidence-v1", proof["schema"])
        self.assertEqual("phase5_magic_ball_switch_activation_emerald_moon", proof["packet_id"])
        self.assertEqual("live_positive", proof["status"])
        self.assertEqual("collision_locomotion", proof["evidence_class"])
        self.assertEqual("moon-switches-room.LBA", proof["source"]["save"])
        self.assertEqual(31, proof["source"]["scene"])
        self.assertEqual([2, 3, 4], proof["source"]["switch_object_indices"])
        self.assertEqual([3, 4], proof["source"]["promoted_switch_object_indices"])
        self.assertEqual(3, proof["initial"]["magic_level"])
        self.assertEqual(57, proof["initial"]["magic_point"])
        self.assertEqual(1, proof["initial"]["magic_ball_flag"])
        self.assertEqual("period", proof["launch_input"]["key"])
        self.assertEqual("hold_then_release", proof["launch_input"]["source_semantics"])
        self.assertEqual(0.75, proof["launch_input"]["hold_sec"])

        runs = proof["observed_runs"]
        self.assertEqual(2, len(runs))
        self.assertEqual(3, runs[0]["target_object_index"])
        self.assertIsNone(runs[0]["forced_beta"])
        self.assertEqual(
            [(4, 1), (1, 2)],
            [(event["before"], event["after"]) for event in runs[0]["target_label_track_events"]],
        )
        self.assertEqual(4, runs[1]["target_object_index"])
        self.assertEqual(2760, runs[1]["forced_beta"])
        self.assertEqual(
            [(2, 3), (3, 4)],
            [(event["before"], event["after"]) for event in runs[1]["target_label_track_events"]],
        )

        self.assertTrue(proof["observations"]["switch_activation_observed"])
        self.assertTrue(proof["observations"]["target_label_track_transition_observed"])
        self.assertTrue(proof["observations"]["object_3_middle_switch_promoted"])
        self.assertTrue(proof["observations"]["object_4_corrected_switch_promoted"])
        self.assertFalse(proof["observations"]["object_2_promoted"])
        self.assertFalse(proof["observations"]["object_field_churn_alone_is_hit_proof"])
        self.assertFalse(proof["observations"]["generic_switch_family_observed"])
        self.assertFalse(proof["observations"]["radar_room_lever_observed"])
        self.assertFalse(proof["observations"]["damage_observed"])
        self.assertFalse(proof["observations"]["remote_pickup_observed"])
        self.assertEqual("emerald_moon_switch_activation_live_positive", proof["verdict"])

    def test_magic_ball_lever_activation_multi_family_fixture_pins_scoped_lever_hits(self) -> None:
        fixture_path = (
            validate_promotion_packets.REPO_ROOT
            / "tools"
            / "fixtures"
            / "promotion_packets"
            / "phase5_magic_ball_lever_activation_multi_family_live_positive.json"
        )
        proof = json.loads(fixture_path.read_text(encoding="utf-8"))

        self.assertEqual("promotion-packet-evidence-v1", proof["schema"])
        self.assertEqual("phase5_magic_ball_lever_activation_multi_family", proof["packet_id"])
        self.assertEqual("live_positive", proof["status"])
        self.assertEqual("collision_locomotion", proof["evidence_class"])
        self.assertEqual(
            ["lever-magic-ball.LBA", "lever-wizard-tent.LBA"],
            proof["source"]["primary_saves"],
        )
        self.assertEqual("01-warehouse.LBA", proof["source"]["negative_control_save"])
        self.assertEqual("period", proof["launch_input"]["key"])
        self.assertEqual("hold_then_release", proof["launch_input"]["source_semantics"])
        self.assertEqual(0.75, proof["launch_input"]["hold_sec"])

        primary = proof["primary_live_positive_runs"]
        self.assertEqual(2, len(primary))
        radar = primary[0]
        self.assertEqual("radar_room_lever", radar["name"])
        self.assertEqual(19, radar["target_object_index"])
        self.assertEqual(242, radar["observed_transition"]["target_gen_anim_before"])
        self.assertEqual(244, radar["observed_transition"]["target_gen_anim_after"])
        self.assertEqual(3, radar["observed_transition"]["linked_label_track_before"])
        self.assertEqual(0, radar["observed_transition"]["linked_label_track_after"])
        self.assertEqual("0x004386ec", radar["cdb_watch"]["writer"])
        self.assertEqual("InitAnim", radar["cdb_watch"]["source_cross_check"]["classic_symbol"])
        self.assertTrue(radar["cdb_watch"]["source_cross_check"]["not_magic_ball_specific"])

        wizard = primary[1]
        self.assertEqual("wizard_tent_lever", wizard["name"])
        self.assertEqual(2, wizard["target_object_index"])
        self.assertEqual([6, 8, 9], wizard["observed_transition"]["target_label_track_sequence"])
        self.assertEqual(155, wizard["observed_transition"]["target_gen_anim_before"])
        self.assertEqual(0, wizard["observed_transition"]["target_gen_anim_after"])
        self.assertEqual("valid", wizard["cdb_watch"]["arm_status"])
        self.assertEqual(1, wizard["cdb_watch"]["hits_observed"])
        self.assertEqual("0x0042468c", wizard["cdb_watch"]["writer"])
        self.assertEqual("DoTrack/TM_LABEL", wizard["cdb_watch"]["source_cross_check"]["classic_symbol"])
        self.assertTrue(wizard["cdb_watch"]["source_cross_check"]["not_magic_ball_specific"])

        negative = proof["negative_control"]
        self.assertEqual("warehouse_blocked_lever", negative["name"])
        self.assertEqual(8, negative["magic_ball_projectile_sprite_observed"])
        self.assertEqual(12, negative["magic_ball_return_sprite_observed"])
        self.assertFalse(negative["activation_observed"])

        self.assertTrue(proof["observations"]["magic_ball_impact_can_activate_lever_script_or_animation"])
        self.assertTrue(proof["observations"]["multiple_write_paths_observed"])
        self.assertFalse(proof["observations"]["all_levers_use_gen_anim_242_244"])
        self.assertFalse(proof["observations"]["all_levers_use_label_track"])
        self.assertFalse(proof["observations"]["impact_alone_is_sufficient_for_activation"])
        self.assertFalse(proof["observations"]["warehouse_blocked_control_promoted_as_activation"])
        self.assertTrue(proof["observations"]["source_cross_check_completed"])
        self.assertIn(
            "generic object animation and track-script paths",
            proof["observations"]["source_cross_check_conclusion"],
        )
        self.assertEqual("lever_activation_multi_family_live_positive", proof["verdict"])

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
        self.assertIn("magic_ball_pickup", contracts)
        self.assertIn("magic_ball_throw_projectile_launch", contracts)
        self.assertIn("magic_ball_bounce_return_wall_repeat", contracts)
        self.assertIn("magic_ball_enemy_damage_tralu_level1", contracts)
        self.assertIn("magic_ball_switch_activation_emerald_moon", contracts)
        self.assertIn("magic_ball_lever_activation_multi_family", contracts)


if __name__ == "__main__":
    unittest.main()
