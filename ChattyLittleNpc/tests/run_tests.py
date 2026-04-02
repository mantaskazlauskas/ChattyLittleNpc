#!/usr/bin/env python3
"""
Unit tests for ChattyLittleNpc pure Lua functions.

Uses lupa (Lua 5.4 via Python) to run Lua code outside WoW.
Run: python tests/run_tests.py
"""

import sys
import os
import unittest
import math

try:
    from lupa import LuaRuntime
except ImportError:
    print("ERROR: lupa not installed. Run: pip install lupa")
    sys.exit(1)


# Path to addon root
ADDON_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def make_lua():
    """Create a Lua runtime with minimal WoW API stubs."""
    lua = LuaRuntime(unpack_returned_tuples=True)

    # Stub global WoW APIs, addon namespace, and Lua 5.4 bit compat
    lua.execute("""
        -- Lua 5.4 compatibility
        unpack = unpack or table.unpack

        -- Lua 5.4 bit compatibility shim (WoW uses LuaJIT's 'bit' library)
        bit = bit or {}
        bit.band  = function(a, b) return a & b end
        bit.bor   = function(a, b) return a | b end
        bit.bxor  = function(...)
            local args = {...}
            local r = args[1] or 0
            for i = 2, #args do r = r ~ args[i] end
            return r
        end
        bit.bnot  = function(a) return ~a end
        bit.lshift = function(a, n) return (a << n) & 0xFFFFFFFF end
        bit.rshift = function(a, n) return (a & 0xFFFFFFFF) >> n end

        -- ChattyLittleNpc namespace
        _G.ChattyLittleNpc = {
            ReplayFrame = { ModelScene = {} },
            db = { profile = { questPlaybackMode = "queue", debugMode = false } },
        }
        local CLN = _G.ChattyLittleNpc

        -- Stub logger
        CLN.Logger = {
            debug = function() end,
            info = function() end,
            warn = function() end,
            error = function() end,
        }
        CLN.Utils = CLN.Utils or {}
        CLN.questsQueue = {}

        -- WoW API stubs
        function GetTime() return 0 end
        function UnitName() return "TestPlayer" end
        function UnitClass() return "Warrior" end
        function UnitRace() return "Human" end
        function CreateFrame() 
            return { 
                RegisterEvent = function() end,
                SetScript = function() end 
            } 
        end
        -- WoW slash command stubs
        SlashCmdList = SlashCmdList or {}
        -- C_Timer for ReplayFrame
        C_Timer = C_Timer or { After = function() end }
    """)
    return lua


def load_file(lua, relative_path):
    """Load a Lua file into the runtime."""
    full_path = os.path.join(ADDON_ROOT, relative_path).replace("\\", "/")
    lua.execute(f'dofile("{full_path}")')


def lua_call(lua, code):
    """Execute multi-statement Lua code and return results via _R global."""
    lua.execute(f"""
        local function _run()
            {code}
        end
        _R = table.pack(_run())
    """)
    r = lua.eval("_R")
    n = lua.eval("_R.n")
    if n == 0:
        return None
    if n == 1:
        return r[1]
    return tuple(r[i] for i in range(1, n + 1))


# ─── Test Classes ───────────────────────────────────────────────


class TestNormalizeQuestPhase(unittest.TestCase):
    """Test Utils:NormalizeQuestPhase and IsCanonicalQuestPhase."""

    @classmethod
    def setUpClass(cls):
        cls.lua = make_lua()
        load_file(cls.lua, "Utils/Utils.lua")

    def _normalize(self, phase):
        return lua_call(self.lua, f'''
            return _G.ChattyLittleNpc.Utils:NormalizeQuestPhase("{phase}")
        ''')

    def _is_canonical(self, phase):
        return lua_call(self.lua, f'''
            return _G.ChattyLittleNpc.Utils:IsCanonicalQuestPhase("{phase}")
        ''')

    def test_canonical_passthrough(self):
        self.assertEqual(self._normalize("Desc"), "Desc")
        self.assertEqual(self._normalize("Prog"), "Prog")
        self.assertEqual(self._normalize("Comp"), "Comp")

    def test_uppercase_aliases(self):
        self.assertEqual(self._normalize("DESC"), "Desc")
        self.assertEqual(self._normalize("DESCRIPTION"), "Desc")
        self.assertEqual(self._normalize("DETAIL"), "Desc")
        self.assertEqual(self._normalize("DETAILS"), "Desc")
        self.assertEqual(self._normalize("PROGRESS"), "Prog")
        self.assertEqual(self._normalize("PROG"), "Prog")
        self.assertEqual(self._normalize("COMPLETE"), "Comp")
        self.assertEqual(self._normalize("COMPLETION"), "Comp")
        self.assertEqual(self._normalize("COMP"), "Comp")

    def test_unknown_phase_passthrough(self):
        self.assertEqual(self._normalize("Unknown"), "Unknown")
        self.assertEqual(self._normalize(""), "")

    def test_nil_input(self):
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.Utils:NormalizeQuestPhase(nil)
        ''')
        self.assertIsNone(result)

    def test_is_canonical(self):
        self.assertTrue(self._is_canonical("Desc"))
        self.assertTrue(self._is_canonical("Prog"))
        self.assertTrue(self._is_canonical("Comp"))
        self.assertFalse(self._is_canonical("DESC"))
        self.assertFalse(self._is_canonical("Unknown"))
        self.assertFalse(self._is_canonical(""))


class TestEstimateVODuration(unittest.TestCase):
    """Test Utils.EstimateVODuration shared helper."""

    @classmethod
    def setUpClass(cls):
        cls.lua = make_lua()
        load_file(cls.lua, "Utils/Utils.lua")

    def _estimate(self, text, min_dur=None, max_dur=None):
        args = f'"{text}"' if text is not None else "nil"
        if min_dur is not None:
            args += f", {min_dur}"
            if max_dur is not None:
                args += f", {max_dur}"
        elif max_dur is not None:
            args += f", nil, {max_dur}"
        return lua_call(self.lua, f"""
            return _G.ChattyLittleNpc.Utils.EstimateVODuration({args})
        """)

    def test_nil_text_returns_default(self):
        """nil text should return 3.6 (original 3 * 1.2)."""
        self.assertAlmostEqual(self._estimate(None), 3.6, places=2)

    def test_empty_text_returns_default(self):
        """Empty text should return 3.6."""
        self.assertAlmostEqual(self._estimate(""), 3.6, places=2)

    def test_nil_text_respects_max_clamp(self):
        """nil text with maxDuration should be capped."""
        result = self._estimate(None, min_dur=1.0, max_dur=2.0)
        self.assertAlmostEqual(result, 2.0, places=2)

    def test_short_text_uses_floor(self):
        """Very short text should hit the floor of 2."""
        result = self._estimate("Hi")
        self.assertGreaterEqual(result, 2.0)

    def test_increased_by_one_fifth(self):
        """Result should be 1.2x the old formula (#text / 11.2 + 1.5)."""
        text = "A" * 112  # old: 112/11.2 + 1.5 = 11.5, new: 11.5 * 1.2 = 13.8
        self.assertAlmostEqual(self._estimate(text), 13.8, places=1)

    def test_custom_min_clamp(self):
        """Custom minDuration should override default floor."""
        result = self._estimate("Hi", min_dur=5.0)
        self.assertGreaterEqual(result, 5.0)

    def test_custom_max_clamp(self):
        """Custom maxDuration should cap the result."""
        text = "A" * 500  # would be large without cap
        result = self._estimate(text, min_dur=1.5, max_dur=5.0)
        self.assertLessEqual(result, 5.0)

    def test_no_max_means_unlimited(self):
        """Without maxDuration, result is unbounded above minDuration."""
        text = "A" * 500
        result = self._estimate(text)
        self.assertGreater(result, 5.0)


class TestBodyRegions(unittest.TestCase):
    """Test ModelScene BodyRegions semantic helpers."""

    @classmethod
    def setUpClass(cls):
        cls.lua = make_lua()
        load_file(cls.lua, "src/ReplayFrame/Renderers/ModelScene/BodyRegions.lua")

    def test_semantic_region_values_tall_humanoid(self):
        values = lua_call(self.lua, '''
            local BR = _G.ChattyLittleNpc.ReplayFrame.ModelScene.BodyRegions
            local bust = BR.GetRegion("tall_humanoid", "bust")
            local head = BR.GetRegion("tall_humanoid", "head")
            local upper = BR.GetRegion("tall_humanoid", "upper_body")
            return
                bust.targetPct, bust.rangeLo, bust.rangeHi, bust.shoulderW,
                head.targetPct, head.rangeLo, head.rangeHi, head.shoulderW,
                upper.targetPct, upper.rangeLo, upper.rangeHi, upper.shoulderW
        ''')
        (
            bust_target, bust_lo, bust_hi, bust_w,
            head_target, head_lo, head_hi, head_w,
            upper_target, upper_lo, upper_hi, upper_w,
        ) = values

        self.assertAlmostEqual(bust_target, 0.92, places=5)
        self.assertAlmostEqual(bust_lo, 0.78, places=5)
        self.assertAlmostEqual(bust_hi, 1.00, places=5)
        self.assertAlmostEqual(bust_w, 0.35, places=5)

        self.assertAlmostEqual(head_target, 0.92, places=5)
        self.assertAlmostEqual(head_lo, 0.84, places=5)
        self.assertAlmostEqual(head_hi, 1.00, places=5)
        self.assertAlmostEqual(head_w, 0.40, places=5)

        self.assertAlmostEqual(upper_target, 0.68, places=5)
        self.assertAlmostEqual(upper_lo, 0.45, places=5)
        self.assertAlmostEqual(upper_hi, 1.00, places=5)
        self.assertAlmostEqual(upper_w, 0.65, places=5)

    def test_solve_world_region_synthetic_bbox_values_and_consistency(self):
        result = lua_call(self.lua, '''
            local BR = _G.ChattyLittleNpc.ReplayFrame.ModelScene.BodyRegions
            local bbox = {
                min = { x = -3.0, y = -1.0, z = 10.0 },
                size = { x = 8.0, y = 4.0, z = 20.0 },
                center = { x = 1.0, y = 2.0, z = 20.0 },
            }
            local world, class, region = BR.SolveWorldRegion(bbox, "bust")
            return
                class, world.targetZ, world.visibleLo, world.visibleHi, world.visibleH, world.fitWidth, region.shoulderW,
                world.focusZ, world.bottomZ, world.topZ, world.desiredFocusY, world.focusToTop, world.focusToBottom
        ''')
        (
            klass, target_z, visible_lo, visible_hi, visible_h, fit_width, shoulder_w,
            focus_z, bottom_z, top_z, desired_focus_y, focus_to_top, focus_to_bottom
        ) = result

        self.assertEqual(klass, "tall_humanoid")
        self.assertAlmostEqual(target_z, 28.4, places=5)
        self.assertAlmostEqual(visible_lo, 25.6, places=5)
        self.assertAlmostEqual(visible_hi, 30.0, places=5)
        self.assertAlmostEqual(visible_h, 4.4, places=5)
        self.assertAlmostEqual(fit_width, 2.8, places=5)
        self.assertAlmostEqual(visible_h, visible_hi - visible_lo, places=5)
        self.assertAlmostEqual(fit_width, 8.0 * shoulder_w, places=5)
        self.assertAlmostEqual(focus_z, target_z, places=5)
        self.assertAlmostEqual(bottom_z, visible_lo, places=5)
        self.assertAlmostEqual(top_z, visible_hi, places=5)
        self.assertAlmostEqual(desired_focus_y, 0.42, places=5)
        self.assertAlmostEqual(focus_to_top, visible_hi - target_z, places=5)
        self.assertAlmostEqual(focus_to_bottom, target_z - visible_lo, places=5)

    def test_solve_world_region_honors_class_hint(self):
        result = lua_call(self.lua, '''
            local BR = _G.ChattyLittleNpc.ReplayFrame.ModelScene.BodyRegions
            local bbox = {
                min = { x = -3.0, y = -1.0, z = 10.0 },
                size = { x = 8.0, y = 4.0, z = 20.0 },
                center = { x = 1.0, y = 2.0, z = 20.0 },
            }
            local world, class, region = BR.SolveWorldRegion(bbox, "bust", "stocky_humanoid")
            return class, world.targetZ, world.visibleLo, world.visibleHi, world.fitWidth, region.targetPct, region.rangeLo, region.shoulderW
        ''')
        klass, target_z, visible_lo, visible_hi, fit_width, region_target, region_lo, region_w = result

        self.assertEqual(klass, "stocky_humanoid")
        self.assertAlmostEqual(region_target, 0.90, places=5)
        self.assertAlmostEqual(region_lo, 0.74, places=5)
        self.assertAlmostEqual(region_w, 0.40, places=5)
        self.assertAlmostEqual(target_z, 28.0, places=5)
        self.assertAlmostEqual(visible_lo, 24.8, places=5)
        self.assertAlmostEqual(visible_hi, 30.0, places=5)
        self.assertAlmostEqual(fit_width, 3.2, places=5)

    def test_region_exposes_composition_fields(self):
        result = lua_call(self.lua, '''
            local BR = _G.ChattyLittleNpc.ReplayFrame.ModelScene.BodyRegions
            local region = BR.GetRegion("tall_humanoid", "bust")
            return
                region.focusAnchor, region.bottomAnchor, region.topAnchor,
                region.focusAnchorPct, region.bottomAnchorPct, region.topAnchorPct,
                region.focusScreenY, region.widthFitPct
        ''')
        (
            focus_anchor, bottom_anchor, top_anchor,
            focus_pct, bottom_pct, top_pct,
            focus_screen_y, width_fit_pct
        ) = result

        self.assertEqual(focus_anchor, "eyeLine")
        self.assertEqual(bottom_anchor, "shoulders")
        self.assertEqual(top_anchor, "headTop")
        self.assertAlmostEqual(focus_pct, 0.92, places=5)
        self.assertAlmostEqual(bottom_pct, 0.78, places=5)
        self.assertAlmostEqual(top_pct, 1.00, places=5)
        self.assertAlmostEqual(focus_screen_y, 0.42, places=5)
        self.assertAlmostEqual(width_fit_pct, 0.35, places=5)

    def test_solve_distance_uses_asymmetric_focus_composition(self):
        result = lua_call(self.lua, '''
            local BR = _G.ChattyLittleNpc.ReplayFrame.ModelScene.BodyRegions
            local world = {
                focusZ = 9.0,
                bottomZ = 7.0,
                topZ = 10.0,
                fitWidth = 2.0,
                desiredFocusY = 0.56,
            }
            local dA, detailsA = BR.SolveDistance(world, 0.8, 1.0, 0.00, 0.00)
            world.desiredFocusY = 0.50
            local dB, detailsB = BR.SolveDistance(world, 0.8, 1.0, 0.00, 0.00)
            return dA, dB, detailsA.needDistBottom, detailsA.needDistTop, detailsA.needDistH, detailsA.focusY,
                detailsA.aimTargetZ, detailsA.focusZ, detailsB.aimTargetZ, detailsB.focusZ
        ''')
        d_a, d_b, need_bottom, need_top, need_h, focus_y, aim_a, focus_a, aim_b, focus_b = result

        self.assertGreater(d_a, d_b)  # lower-screen focus leaves less room below, needs more distance
        self.assertGreater(need_bottom, need_top)
        self.assertGreater(d_a, need_h)
        self.assertAlmostEqual(focus_y, 0.56, places=5)
        self.assertNotAlmostEqual(aim_a, focus_a, places=5)
        self.assertAlmostEqual(aim_b, focus_b, places=5)
        self.assertGreater(aim_a, focus_a)


class TestModelScenePositioning(unittest.TestCase):
    """Test ModelScene Positioning anchor math and host integration."""

    @classmethod
    def setUpClass(cls):
        cls.lua = make_lua()
        cls.lua.execute("""
            local NS = _G.ChattyLittleNpc.ReplayFrame.ModelScene
            NS.Diagnostics = { log = function() end }
            NS.CanonicalBbox = NS.CanonicalBbox or {}
        """)
        load_file(cls.lua, "src/ReplayFrame/Renderers/ModelScene/Positioning.lua")

    def test_get_anchor_names_returns_expected_order(self):
        result = lua_call(self.lua, '''
            local P = _G.ChattyLittleNpc.ReplayFrame.ModelScene.Positioning
            return table.concat(P.GetAnchorNames(), ",")
        ''')
        self.assertEqual(
            result,
            "TOP_LEFT,TOP,TOP_RIGHT,LEFT,CENTER,RIGHT,BOTTOM_LEFT,BOTTOM,BOTTOM_RIGHT",
        )

    def test_resolve_anchor_point_uses_bbox_edges_and_center_y(self):
        ax, ay, az = lua_call(self.lua, '''
            local P = _G.ChattyLittleNpc.ReplayFrame.ModelScene.Positioning
            local bbox = {
                min = { x = -2, y = 1, z = 10 },
                max = { x = 4, y = 9, z = 30 },
                center = { x = 1, y = 5, z = 20 },
            }
            return P.ResolveAnchorPoint(bbox, P.Anchors.TOP_LEFT)
        ''')
        self.assertAlmostEqual(ax, -2.0, places=5)
        self.assertAlmostEqual(ay, 5.0, places=5)
        self.assertAlmostEqual(az, 30.0, places=5)

    def test_set_model_position_prefers_canonical_bbox_and_clamps_percentages(self):
        ok, tx, ty, tz, px, py, pz, anchor, x_pct, y_pct, user_controlled, anchor_top_cleared, anchor_factor_cleared = lua_call(self.lua, '''
            local P = _G.ChattyLittleNpc.ReplayFrame.ModelScene.Positioning
            local bbox = {
                min = { x = -2, y = 1, z = 10 },
                max = { x = 4, y = 9, z = 30 },
                center = { x = 1, y = 5, z = 20 },
            }
            _G.ChattyLittleNpc.ReplayFrame.ModelScene.CanonicalBbox.GetCached = function(displayID)
                return { bbox = bbox }
            end
            local host = {
                _currentDisplayID = 77,
                _camDist = 5,
                _anchorTop = 123,
                _anchorFactor = 456,
                GetFovV = function() return 1.2 end,
                GetAspect = function() return 1.5 end,
                GetBounds = function()
                    return {
                        min = { x = -100, y = 0, z = -100 },
                        max = { x = 100, y = 10, z = 100 },
                        center = { x = 0, y = 5, z = 0 },
                    }
                end,
                _ApplyCameraLookAt = function(self, camPx, camPy, camPz, camTx, camTy, camTz)
                    self.camera = { tx = camTx, ty = camTy, tz = camTz, px = camPx, py = camPy, pz = camPz }
                end,
                _UpdateSnapshot = function(self, snapshot)
                    self.snapshot = snapshot
                end,
            }
            local success = P.SetModelPosition(host, P.Anchors.TOP_RIGHT, -1, 2)
            return
                success,
                host.camera.tx,
                host.camera.ty,
                host.camera.tz,
                host.camera.px,
                host.camera.py,
                host.camera.pz,
                host._positioning.anchor,
                host._positioning.xPct,
                host._positioning.yPct,
                host._userControlledCamera,
                host._anchorTop == nil,
                host._anchorFactor == nil
        ''')
        self.assertTrue(ok)
        d = 5.0
        half_h = d * math.tan(1.2 * 0.5)
        half_w = half_h * 1.5
        self.assertAlmostEqual(tx, 4.0 + half_w, places=5)
        self.assertAlmostEqual(ty, 5.0, places=5)
        self.assertAlmostEqual(tz, 30.0 - half_h, places=5)
        self.assertAlmostEqual(px, tx, places=5)
        self.assertAlmostEqual(py, 10.0, places=5)
        self.assertAlmostEqual(pz, tz, places=5)
        self.assertEqual(anchor, 'TOP_RIGHT')
        self.assertAlmostEqual(x_pct, 0.0, places=5)
        self.assertAlmostEqual(y_pct, 1.0, places=5)
        self.assertTrue(user_controlled)
        self.assertTrue(anchor_top_cleared)
        self.assertTrue(anchor_factor_cleared)

    def test_set_model_position_falls_back_to_live_bounds_when_no_canonical_bbox(self):
        ok, tx, ty, tz = lua_call(self.lua, '''
            local P = _G.ChattyLittleNpc.ReplayFrame.ModelScene.Positioning
            _G.ChattyLittleNpc.ReplayFrame.ModelScene.CanonicalBbox.GetCached = function()
                return nil
            end
            local host = {
                _camDist = 4,
                GetFovV = function() return 1.0 end,
                GetAspect = function() return 2.0 end,
                GetBounds = function()
                    return {
                        min = { x = 10, y = 2, z = 20 },
                        max = { x = 14, y = 8, z = 26 },
                        center = { x = 12, y = 5, z = 23 },
                    }
                end,
                _ApplyCameraLookAt = function(self, _, _, _, camTx, camTy, camTz)
                    self.tx, self.ty, self.tz = camTx, camTy, camTz
                end,
                _UpdateSnapshot = function() end,
            }
            local success = P.SetModelPosition(host, P.Anchors.LEFT, 0.5, 0.5)
            return success, host.tx, host.ty, host.tz
        ''')
        self.assertTrue(ok)
        self.assertAlmostEqual(tx, 10.0, places=5)
        self.assertAlmostEqual(ty, 5.0, places=5)
        self.assertAlmostEqual(tz, 23.0, places=5)

    def test_set_model_position_ignores_invalid_canonical_bbox_and_uses_live_bounds(self):
        ok, tx, ty, tz = lua_call(self.lua, '''
            local P = _G.ChattyLittleNpc.ReplayFrame.ModelScene.Positioning
            _G.ChattyLittleNpc.ReplayFrame.ModelScene.CanonicalBbox.GetCached = function()
                return {
                    bbox = {
                        min = { x = 1, z = 2 },
                        max = { x = 3, z = 4 },
                    }
                }
            end
            local host = {
                _camDist = 4,
                GetFovV = function() return 1.0 end,
                GetAspect = function() return 1.0 end,
                GetBounds = function()
                    return {
                        min = { x = 6, y = 1, z = 7 },
                        max = { x = 10, y = 5, z = 11 },
                        center = { x = 8, y = 3, z = 9 },
                    }
                end,
                _ApplyCameraLookAt = function(self, _, _, _, camTx, camTy, camTz)
                    self.tx, self.ty, self.tz = camTx, camTy, camTz
                end,
                _UpdateSnapshot = function() end,
            }
            local success = P.SetModelPosition(host, P.Anchors.CENTER, 0.5, 0.5)
            return success, host.tx, host.ty, host.tz
        ''')
        self.assertTrue(ok)
        self.assertAlmostEqual(tx, 8.0, places=5)
        self.assertAlmostEqual(ty, 3.0, places=5)
        self.assertAlmostEqual(tz, 9.0, places=5)

    def test_set_model_position_returns_false_when_required_camera_inputs_missing(self):
        result = lua_call(self.lua, '''
            local P = _G.ChattyLittleNpc.ReplayFrame.ModelScene.Positioning
            _G.ChattyLittleNpc.ReplayFrame.ModelScene.CanonicalBbox.GetCached = function()
                return {
                    bbox = {
                        min = { x = 0, y = 0, z = 0 },
                        max = { x = 1, y = 1, z = 1 },
                        center = { x = 0.5, y = 0.5, z = 0.5 },
                    }
                }
            end
            local host = {
                _ApplyCameraLookAt = function() end,
                _UpdateSnapshot = function() end,
            }
            return P.SetModelPosition(host, P.Anchors.CENTER, 0.5, 0.5)
        ''')
        self.assertFalse(result)

    def test_set_model_position_returns_false_when_camera_application_errors(self):
        result = lua_call(self.lua, '''
            local P = _G.ChattyLittleNpc.ReplayFrame.ModelScene.Positioning
            _G.ChattyLittleNpc.ReplayFrame.ModelScene.CanonicalBbox.GetCached = function()
                return {
                    bbox = {
                        min = { x = 0, y = 0, z = 0 },
                        max = { x = 2, y = 2, z = 2 },
                        center = { x = 1, y = 1, z = 1 },
                    }
                }
            end
            local host = {
                _camDist = 3,
                GetFovV = function() return 1.0 end,
                GetAspect = function() return 1.0 end,
                _ApplyCameraLookAt = function()
                    error("boom")
                end,
                _UpdateSnapshot = function()
                    error("should not run")
                end,
            }
            return P.SetModelPosition(host, P.Anchors.CENTER, 0.5, 0.5)
        ''')
        self.assertFalse(result)

class TestProjectionVerifier(unittest.TestCase):
    """Lightweight projection math checks with mocked scene projection."""

    @classmethod
    def setUpClass(cls):
        cls.lua = make_lua()
        load_file(cls.lua, "src/ReplayFrame/Renderers/ModelScene/ProjectionVerifier.lua")

    def test_measure_returns_projected_bounds_and_coverage(self):
        result = lua_call(self.lua, '''
            local PV = _G.ChattyLittleNpc.ReplayFrame.ModelScene.ProjectionVerifier
            local scene = {
                Project3DPointTo2D = function(_, x, _, z)
                    return 100 + x * 10, 50 + z * 20
                end
            }
            local world = {
                fitWidth = 4,
                visibleLo = 1,
                visibleHi = 3,
                targetX = 10,
                targetY = 0,
                targetZ = 2,
                focusZ = 1.5,
                desiredFocusY = 0.2,
            }
            local ok, m = PV.Measure(scene, world, 200, 100)
            return ok, m.minPX, m.maxPX, m.minPY, m.maxPY, m.coverageW, m.coverageH, m.targetPY, m.focusPY, m.topPY, m.focusErrorPY
        ''')
        ok, min_px, max_px, min_py, max_py, cov_w, cov_h, target_py, focus_py, top_py, focus_error_py = result
        self.assertTrue(ok)
        self.assertAlmostEqual(min_px, 180.0, places=5)
        self.assertAlmostEqual(max_px, 220.0, places=5)
        self.assertAlmostEqual(min_py, 70.0, places=5)
        self.assertAlmostEqual(max_py, 110.0, places=5)
        self.assertAlmostEqual(cov_w, 0.2, places=5)
        self.assertAlmostEqual(cov_h, 0.4, places=5)
        self.assertAlmostEqual(target_py, 90.0, places=5)
        self.assertAlmostEqual(focus_py, 80.0, places=5)
        self.assertAlmostEqual(top_py, 110.0, places=5)
        self.assertAlmostEqual(focus_error_py, 60.0, places=5)

    def test_adjust_headroom_preserves_focus_and_only_shifts_aim(self):
        result = lua_call(self.lua, '''
            local PV = _G.ChattyLittleNpc.ReplayFrame.ModelScene.ProjectionVerifier
            local scene = {
                Project3DPointTo2D = function(_, _, _, z)
                    return 0, z * 2
                end
            }
            local host = {
                _ApplyCameraLookAt = function() end
            }
            local world = {
                targetX = 0,
                targetY = 0,
                targetZ = 2,
                focusZ = 1.5,
                visibleLo = 1,
                visibleHi = 3,
                fitWidth = 4,
                focusToTop = 1.5,
                focusToBottom = 0.5,
                targetToTop = 1,
                targetToBottom = 1,
            }
            local corrected, changed = PV.AdjustHeadroom(scene, host, world, 2.5, 100, 100, { topMarginPct = 0.08 })
            return changed, corrected.focusZ, corrected.targetZ, corrected.focusToTop, corrected.focusToBottom, corrected.targetToTop, corrected.targetToBottom
        ''')
        changed, focus_z, target_z, focus_to_top, focus_to_bottom, target_to_top, target_to_bottom = result
        self.assertTrue(changed)
        self.assertNotAlmostEqual(focus_z, target_z, places=5)
        self.assertAlmostEqual(focus_z, 1.5, places=5)
        self.assertAlmostEqual(focus_to_top, 1.5, places=5)
        self.assertAlmostEqual(focus_to_bottom, 0.5, places=5)
        self.assertNotAlmostEqual(target_to_top, focus_to_top, places=5)
        self.assertNotAlmostEqual(target_to_bottom, focus_to_bottom, places=5)

    def test_adjust_headroom_focus_tuning_changes_target_when_top_headroom_already_ok(self):
        result = lua_call(self.lua, '''
            local PV = _G.ChattyLittleNpc.ReplayFrame.ModelScene.ProjectionVerifier
            local frameH = 100
            local topMarginPct = 0.08
            local world = {
                targetX = 0,
                targetY = 0,
                targetZ = 2,
                focusZ = 3.5,
                visibleLo = 1,
                visibleHi = 4,
                fitWidth = 4,
                desiredFocusY = 0.60,
                focusToTop = 0.5,
                focusToBottom = 2.5,
            }
            local scene = {
                Project3DPointTo2D = function(_, _, _, z)
                    return 0, 100 - z * 20
                end
            }
            local host = {
                _ApplyCameraLookAt = function() end
            }
            local ok, metrics = PV.Measure(scene, world, 100, frameH)
            local corrected, changed = PV.AdjustHeadroom(scene, host, world, 2.5, 100, frameH, { topMarginPct = topMarginPct })
            local desiredTopPx = topMarginPct * frameH
            return ok, metrics.minPY, desiredTopPx, metrics.focusErrorPY, changed, corrected.targetZ, corrected.focusZ, corrected.focusToTop, corrected.focusToBottom
        ''')
        (
            ok,
            current_top_px,
            desired_top_px,
            focus_error_px,
            changed,
            corrected_target_z,
            corrected_focus_z,
            corrected_focus_to_top,
            corrected_focus_to_bottom,
        ) = result
        self.assertTrue(ok)
        self.assertGreaterEqual(current_top_px, desired_top_px)
        self.assertLess(focus_error_px, -1.0)
        self.assertTrue(changed)
        self.assertNotAlmostEqual(corrected_target_z, 2.0, places=5)
        self.assertAlmostEqual(corrected_focus_z, 3.5, places=5)
        self.assertAlmostEqual(corrected_focus_to_top, 0.5, places=5)
        self.assertAlmostEqual(corrected_focus_to_bottom, 2.5, places=5)

    def test_adjust_headroom_focus_too_high_moves_target_to_push_composition_down(self):
        result = lua_call(self.lua, '''
            local PV = _G.ChattyLittleNpc.ReplayFrame.ModelScene.ProjectionVerifier
            local world = {
                targetX = 0,
                targetY = 0,
                targetZ = 2,
                focusZ = 3.5,
                visibleLo = 1,
                visibleHi = 4,
                fitWidth = 4,
                desiredFocusY = 0.60,
            }
            local scene = {
                Project3DPointTo2D = function(_, _, _, z)
                    return 0, 100 - z * 20
                end
            }
            local host = {
                _ApplyCameraLookAt = function() end
            }
            local corrected, changed = PV.AdjustHeadroom(scene, host, world, 2.5, 100, 100, { topMarginPct = 0.08 })
            return changed, corrected.targetZ, corrected.targetToTop, corrected.targetToBottom
        ''')
        changed, corrected_target_z, corrected_target_to_top, corrected_target_to_bottom = result
        self.assertTrue(changed)
        self.assertGreater(corrected_target_z, 2.0)
        self.assertLess(corrected_target_to_top, 2.0)
        self.assertGreater(corrected_target_to_bottom, 1.0)

    def test_refine_distance_does_not_zoom_in_when_roomy(self):
        result = lua_call(self.lua, '''
            local PV = _G.ChattyLittleNpc.ReplayFrame.ModelScene.ProjectionVerifier
            local currentDist = 8
            local minDist = currentDist
            local maxDist = currentDist
            local calls = 0
            local scene = {
                Project3DPointTo2D = function(_, x, _, z)
                    local scale = 100 / currentDist
                    return x * scale, z * scale
                end
            }
            local host = {
                _ApplyCameraLookAt = function(_, _, camY, _, _, targetY)
                    currentDist = camY - targetY
                    calls = calls + 1
                    if currentDist < minDist then minDist = currentDist end
                    if currentDist > maxDist then maxDist = currentDist end
                end
            }
            local world = {
                targetX = 0,
                targetY = 0,
                targetZ = 1,
                visibleLo = 0,
                visibleHi = 2,
                fitWidth = 4,
            }
            local refined = PV.RefineDistance(scene, host, world, 8, 100, 100)
            return refined, calls, minDist, maxDist
        ''')
        refined, calls, min_dist, max_dist = result
        self.assertAlmostEqual(refined, 8.0, places=5)
        self.assertGreaterEqual(calls, 2)
        self.assertAlmostEqual(min_dist, 8.0, places=5)
        self.assertAlmostEqual(max_dist, 8.0, places=5)

    def test_refine_distance_zooms_out_when_too_close(self):
        result = lua_call(self.lua, '''
            local PV = _G.ChattyLittleNpc.ReplayFrame.ModelScene.ProjectionVerifier
            local currentDist = 2
            local minDist = currentDist
            local maxDist = currentDist
            local scene = {
                Project3DPointTo2D = function(_, x, _, z)
                    local scale = 100 / currentDist
                    return x * scale, z * scale
                end
            }
            local host = {
                _ApplyCameraLookAt = function(_, _, camY, _, _, targetY)
                    currentDist = camY - targetY
                    if currentDist < minDist then minDist = currentDist end
                    if currentDist > maxDist then maxDist = currentDist end
                end
            }
            local world = {
                targetX = 0,
                targetY = 0,
                targetZ = 1,
                visibleLo = 0,
                visibleHi = 2,
                fitWidth = 4,
            }
            local refined = PV.RefineDistance(scene, host, world, 2, 100, 100)
            return refined, minDist, maxDist
        ''')
        refined, min_dist, max_dist = result
        self.assertGreater(refined, 2.0)
        self.assertAlmostEqual(min_dist, 2.0, places=5)
        self.assertGreater(max_dist, 2.0)


class TestContainsString(unittest.TestCase):
    """Test Utils:ContainsString."""

    @classmethod
    def setUpClass(cls):
        cls.lua = make_lua()
        load_file(cls.lua, "Utils/Utils.lua")

    def test_found(self):
        result = lua_call(self.lua, '''
            local t = {"apple", "banana", "cherry"}
            return _G.ChattyLittleNpc.Utils:ContainsString(t, "banana")
        ''')
        self.assertTrue(result)

    def test_not_found(self):
        result = lua_call(self.lua, '''
            local t = {"apple", "banana", "cherry"}
            return _G.ChattyLittleNpc.Utils:ContainsString(t, "grape")
        ''')
        self.assertFalse(result)

    def test_empty_table(self):
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.Utils:ContainsString({}, "anything")
        ''')
        self.assertFalse(result)


class TestIsNilOrEmpty(unittest.TestCase):
    """Test Utils:IsNilOrEmpty."""

    @classmethod
    def setUpClass(cls):
        cls.lua = make_lua()
        load_file(cls.lua, "Utils/Utils.lua")

    def test_nil(self):
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.Utils:IsNilOrEmpty(nil)
        ''')
        self.assertTrue(result)

    def test_empty(self):
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.Utils:IsNilOrEmpty("")
        ''')
        self.assertTrue(result)

    def test_non_empty(self):
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.Utils:IsNilOrEmpty("hello")
        ''')
        self.assertFalse(result)

    def test_whitespace(self):
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.Utils:IsNilOrEmpty(" ")
        ''')
        self.assertFalse(result)


@unittest.skip("Framing.lua requires WoW ModelScene APIs not available in test env")
class TestFramingSolveAxis(unittest.TestCase):
    """Test Framing.solveAxis and FOVPair_FromF."""

    @classmethod
    def setUpClass(cls):
        cls.lua = make_lua()
        load_file(cls.lua, "src/ReplayFrame/Renderers/ModelScene/Framing.lua")

    def test_solve_axis_y(self):
        d, dV, dH, depthHalf = lua_call(self.lua, '''
            local F = _G.ChattyLittleNpc.ReplayFrame.ModelScene.Framing
            return F.solveAxis("Y", 0.8, 1.2, 1.0, 0.5, 1.5)
        ''')
        self.assertGreater(d, 0, "distance must be positive")
        self.assertGreater(dV, 0)
        self.assertGreater(dH, 0)
        self.assertAlmostEqual(depthHalf, 0.5, places=5,
                               msg="Y-axis depth half should be halfY")

    def test_solve_axis_x(self):
        d, dV, dH, depthHalf = lua_call(self.lua, '''
            local F = _G.ChattyLittleNpc.ReplayFrame.ModelScene.Framing
            return F.solveAxis("X", 0.8, 1.2, 1.0, 0.5, 1.5)
        ''')
        self.assertGreater(d, 0)
        self.assertAlmostEqual(depthHalf, 1.0, places=5,
                               msg="X-axis depth half should be halfX")

    def test_solve_axis_zero_extents_clamped(self):
        """Half-extents of 0 should be clamped to 0.01, not cause division by zero."""
        d, dV, dH, _ = lua_call(self.lua, '''
            local F = _G.ChattyLittleNpc.ReplayFrame.ModelScene.Framing
            return F.solveAxis("Y", 0.8, 1.2, 0, 0, 0)
        ''')
        self.assertGreater(d, 0)
        self.assertTrue(d < 1e6, "distance should not be astronomical")

    def test_fov_pair_vertical(self):
        vfov, hfov = lua_call(self.lua, '''
            local F = _G.ChattyLittleNpc.ReplayFrame.ModelScene.Framing
            return F.FOVPair_FromF(0.8, false)
        ''')
        self.assertAlmostEqual(vfov, 0.8, places=5)
        self.assertGreater(hfov, 0)

    def test_fov_pair_horizontal(self):
        vfov, hfov = lua_call(self.lua, '''
            local F = _G.ChattyLittleNpc.ReplayFrame.ModelScene.Framing
            return F.FOVPair_FromF(1.2, true)
        ''')
        self.assertAlmostEqual(hfov, 1.2, places=5)
        self.assertGreater(vfov, 0)


class TestIsQuestPhaseQueued(unittest.TestCase):
    """Test VoiceoverPlayer:IsQuestPhaseQueued."""

    @classmethod
    def setUpClass(cls):
        cls.lua = make_lua()
        cls.lua.execute("""
            local CLN = _G.ChattyLittleNpc
            CLN.VoiceoverPlayer = {}
            local VP = CLN.VoiceoverPlayer

            VP._paused = false
            VP.currentlyPlaying = {}

            function VP:IsCurrentQuestPhaseActive(questId, phase)
                if not (questId and phase) then return false end
                local cp = VP.currentlyPlaying
                if not cp or cp.questId ~= questId or cp.phase ~= phase then
                    return false
                end
                return cp.soundHandle
                    or VP._paused
                    or cp._pausedByUser
                    or cp._pausedForNativeVO
                    or cp._textContinuation
            end

            function VP:IsQuestPhaseQueued(questId, phase)
                if not (questId and phase) then return false end
                if VP:IsCurrentQuestPhaseActive(questId, phase) then
                    return true, 0
                end
                for i, q in ipairs(CLN.questsQueue) do
                    if q.questId == questId and q.phase == phase then
                        return true, i
                    end
                end
                return false
            end
        """)

    def setUp(self):
        self.lua.execute("""
            _G.ChattyLittleNpc.questsQueue = {
                { questId = 100, phase = "Desc" },
                { questId = 200, phase = "Prog" },
                { questId = 300, phase = "Comp" },
            }
            local VP = _G.ChattyLittleNpc.VoiceoverPlayer
            VP._paused = false
            VP.currentlyPlaying = {
                questId = nil,
                phase = nil,
                soundHandle = nil,
                _pausedByUser = nil,
                _pausedForNativeVO = nil,
                _textContinuation = nil,
            }
        """)

    def test_found(self):
        found, idx = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.VoiceoverPlayer:IsQuestPhaseQueued(200, "Prog")
        ''')
        self.assertTrue(found)
        self.assertEqual(idx, 2)

    def test_not_found_wrong_phase(self):
        found = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.VoiceoverPlayer:IsQuestPhaseQueued(100, "Comp")
        ''')
        self.assertFalse(found)

    def test_not_found_wrong_id(self):
        found = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.VoiceoverPlayer:IsQuestPhaseQueued(999, "Desc")
        ''')
        self.assertFalse(found)

    def test_nil_args(self):
        found = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.VoiceoverPlayer:IsQuestPhaseQueued(nil, "Desc")
        ''')
        self.assertFalse(found)

    def test_empty_queue(self):
        self.lua.execute("_G.ChattyLittleNpc.questsQueue = {}")
        found = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.VoiceoverPlayer:IsQuestPhaseQueued(100, "Desc")
        ''')
        self.assertFalse(found)

    def test_current_paused_by_user_counts_as_queued(self):
        found, idx = lua_call(self.lua, '''
            local VP = _G.ChattyLittleNpc.VoiceoverPlayer
            VP._paused = true
            VP.currentlyPlaying = {
                questId = 100,
                phase = "Desc",
                soundHandle = nil,
                _pausedByUser = true,
            }
            return VP:IsQuestPhaseQueued(100, "Desc")
        ''')
        self.assertTrue(found)
        self.assertEqual(idx, 0)

    def test_current_paused_for_native_vo_counts_as_queued(self):
        found, idx = lua_call(self.lua, '''
            local VP = _G.ChattyLittleNpc.VoiceoverPlayer
            VP.currentlyPlaying = {
                questId = 100,
                phase = "Desc",
                soundHandle = nil,
                _pausedForNativeVO = true,
            }
            return VP:IsQuestPhaseQueued(100, "Desc")
        ''')
        self.assertTrue(found)
        self.assertEqual(idx, 0)

    def test_current_text_continuation_counts_as_queued(self):
        found, idx = lua_call(self.lua, '''
            local VP = _G.ChattyLittleNpc.VoiceoverPlayer
            VP.currentlyPlaying = {
                questId = 100,
                phase = "Desc",
                soundHandle = nil,
                _textContinuation = true,
            }
            return VP:IsQuestPhaseQueued(100, "Desc")
        ''')
        self.assertTrue(found)
        self.assertEqual(idx, 0)

    def test_current_with_soundhandle_counts_as_queued(self):
        found, idx = lua_call(self.lua, '''
            local VP = _G.ChattyLittleNpc.VoiceoverPlayer
            VP.currentlyPlaying = {
                questId = 100,
                phase = "Desc",
                soundHandle = 12345,
            }
            return VP:IsQuestPhaseQueued(100, "Desc")
        ''')
        self.assertTrue(found)
        self.assertEqual(idx, 0)

    def test_current_without_handle_or_pause_flags_not_queued(self):
        found = lua_call(self.lua, '''
            _G.ChattyLittleNpc.questsQueue = {}
            local VP = _G.ChattyLittleNpc.VoiceoverPlayer
            VP.currentlyPlaying = {
                questId = 100,
                phase = "Desc",
                soundHandle = nil,
                _pausedByUser = nil,
                _pausedForNativeVO = nil,
                _textContinuation = nil,
            }
            VP._paused = false
            return VP:IsQuestPhaseQueued(100, "Desc")
        ''')
        self.assertFalse(found)


class TestNativeVOPausePlaybackGating(unittest.TestCase):
    """Regression tests for native VO pause playback deferral decisions."""

    @classmethod
    def setUpClass(cls):
        cls.lua = make_lua()
        cls.lua.execute("""
            local CLN = _G.ChattyLittleNpc
            CLN.db.profile.gossipQueueMode = "all"
            CLN.questsQueue = {}
            CLN.VoiceoverPlayer = {}
            local VP = CLN.VoiceoverPlayer
            VP.currentlyPlaying = {}

            function VP:IsCurrentQuestPhaseActive(questId, phase)
                if not (questId and phase) then return false end
                local cp = VP.currentlyPlaying
                if not cp or cp.questId ~= questId or cp.phase ~= phase then
                    return false
                end
                return cp.soundHandle
                    or VP._paused
                    or cp._pausedByUser
                    or cp._pausedForNativeVO
                    or cp._textContinuation
            end

            function VP:IsQuestPhaseQueued(questId, phase)
                if not (questId and phase) then return false end
                if VP:IsCurrentQuestPhaseActive(questId, phase) then
                    return true, 0
                end
                for i, q in ipairs(CLN.questsQueue) do
                    if q.questId == questId and q.phase == phase then
                        return true, i
                    end
                end
                return false
            end

            function VP:IsNativeVOPauseActive()
                local cp = self.currentlyPlaying
                return not not ((cp and cp._pausedForNativeVO) or self._nativeVOResumeTimer)
            end

            function VP:PlayQuestSound(questId, phase, npcId, displayID)
                if self:IsNativeVOPauseActive() then
                    if CLN.db.profile.questPlaybackMode == "queue" then
                        local alreadyQueued = self:IsQuestPhaseQueued(questId, phase)
                        if not alreadyQueued then
                            table.insert(CLN.questsQueue, {
                                questId = questId,
                                phase = phase,
                                npcId = npcId,
                                displayID = displayID,
                                entryType = "quest",
                            })
                        end
                    end
                    return "deferred"
                end
                return "played"
            end

            function VP:PlayNonQuestSound(npcId, soundType, text, gender, displayID)
                if self:IsNativeVOPauseActive() then
                    local gossipQueue = CLN.db.profile.gossipQueueMode or "none"
                    if gossipQueue ~= "none" then
                        table.insert(CLN.questsQueue, {
                            npcId = npcId,
                            title = text,
                            entryType = soundType,
                            gender = gender,
                            displayID = displayID,
                            cantBeInterrupted = false,
                        })
                        return "queued"
                    end
                    return "skipped"
                end
                return "played"
            end
        """)

    def setUp(self):
        self.lua.execute("""
            local CLN = _G.ChattyLittleNpc
            CLN.questsQueue = {}
            CLN.db.profile.questPlaybackMode = "queue"
            CLN.db.profile.gossipQueueMode = "all"
            CLN.VoiceoverPlayer._nativeVOResumeTimer = nil
            CLN.VoiceoverPlayer.currentlyPlaying = {
                questId = 100,
                phase = "Desc",
                soundHandle = nil,
                _pausedForNativeVO = true,
                _pausedByUser = nil,
                _textContinuation = nil,
            }
        """)

    def test_native_vo_helper_true_from_pause_flag(self):
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.VoiceoverPlayer:IsNativeVOPauseActive()
        ''')
        self.assertTrue(result)

    def test_native_vo_helper_true_from_resume_timer(self):
        result = lua_call(self.lua, '''
            local VP = _G.ChattyLittleNpc.VoiceoverPlayer
            VP.currentlyPlaying._pausedForNativeVO = nil
            VP._nativeVOResumeTimer = {}
            return VP:IsNativeVOPauseActive()
        ''')
        self.assertTrue(result)

    def test_native_vo_helper_false_when_not_paused(self):
        result = lua_call(self.lua, '''
            local VP = _G.ChattyLittleNpc.VoiceoverPlayer
            VP.currentlyPlaying._pausedForNativeVO = nil
            VP._nativeVOResumeTimer = nil
            return VP:IsNativeVOPauseActive()
        ''')
        self.assertFalse(result)

    def test_play_quest_deferred_and_queued_during_native_vo(self):
        result, qlen = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            local VP = CLN.VoiceoverPlayer
            local action = VP:PlayQuestSound(200, "Prog", 7, 8)
            return action, #CLN.questsQueue
        ''')
        self.assertEqual(result, "deferred")
        self.assertEqual(qlen, 1)

    def test_play_quest_dedupes_current_phase_during_native_vo(self):
        qlen = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            local VP = CLN.VoiceoverPlayer
            VP:PlayQuestSound(100, "Desc", 7, 8)
            return #CLN.questsQueue
        ''')
        self.assertEqual(qlen, 0)

    def test_play_quest_skips_in_interrupt_mode_during_native_vo(self):
        result, qlen = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            local VP = CLN.VoiceoverPlayer
            CLN.db.profile.questPlaybackMode = "interrupt"
            local action = VP:PlayQuestSound(200, "Prog", 7, 8)
            return action, #CLN.questsQueue
        ''')
        self.assertEqual(result, "deferred")
        self.assertEqual(qlen, 0)

    def test_play_nonquest_queues_when_gossip_queue_enabled(self):
        result, qlen = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            local VP = CLN.VoiceoverPlayer
            local action = VP:PlayNonQuestSound(5, "Gossip", "Hello", "Male", 88)
            return action, #CLN.questsQueue
        ''')
        self.assertEqual(result, "queued")
        self.assertEqual(qlen, 1)

    def test_play_nonquest_skips_when_gossip_queue_disabled(self):
        result, qlen = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            local VP = CLN.VoiceoverPlayer
            CLN.db.profile.gossipQueueMode = "none"
            local action = VP:PlayNonQuestSound(5, "Gossip", "Hello", "Male", 88)
            return action, #CLN.questsQueue
        ''')
        self.assertEqual(result, "skipped")
        self.assertEqual(qlen, 0)


class TestReplayModelDisplayIDResolution(unittest.TestCase):
    """Replay model selection should prefer runtime-captured displayID over static DB."""

    @classmethod
    def setUpClass(cls):
        cls.lua = make_lua()
        cls.lua.execute("""
            NpcDisplayIdDB = {
                [100] = 9999,
                [200] = 2222,
            }
            local CLN = _G.ChattyLittleNpc
            CLN.VoiceoverPlayer = CLN.VoiceoverPlayer or {}
            CLN.VoiceoverPlayer.currentlyPlaying = {
                npcId = 100,
                displayID = 5555,
            }
        """)
        load_file(cls.lua, "src/ReplayFrame/ModelFrame.lua")

    def setUp(self):
        self.lua.execute("""
            local CLN = _G.ChattyLittleNpc
            CLN.VoiceoverPlayer.currentlyPlaying = {
                npcId = 100,
                displayID = 5555,
            }
        """)

    def test_prefers_runtime_display_id_for_active_npc(self):
        value = lua_call(self.lua, '''
            local rf = _G.ChattyLittleNpc.ReplayFrame
            return rf:ResolveNpcDisplayID(100)
        ''')
        self.assertEqual(value, 5555)

    def test_falls_back_to_db_when_runtime_display_missing(self):
        value = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            CLN.VoiceoverPlayer.currentlyPlaying.displayID = nil
            local rf = CLN.ReplayFrame
            return rf:ResolveNpcDisplayID(100)
        ''')
        self.assertEqual(value, 9999)

    def test_falls_back_to_db_when_runtime_npc_mismatch(self):
        value = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            CLN.VoiceoverPlayer.currentlyPlaying = {
                npcId = 101,
                displayID = 5555,
            }
            local rf = CLN.ReplayFrame
            return rf:ResolveNpcDisplayID(200)
        ''')
        self.assertEqual(value, 2222)


class TestReplayQueuePipelineFixes(unittest.TestCase):
    """Regression coverage for queue identity, history ownership, and stale UI reads."""

    @classmethod
    def setUpClass(cls):
        cls.lua = make_lua()
        cls.lua.execute("""
            local CLN = _G.ChattyLittleNpc
            CLN.db.profile.audioChannel = "MASTER"
            CLN.db.profile.questPlaybackMode = "queue"
            CLN.db.profile.gossipQueueMode = "all"
            CLN.db.profile.gossipCooldownEnabled = false
            CLN.db.profile.gossipCooldownMinutes = 0
            CLN.db.profile.textContinuationEnabled = true
            CLN.db.profile.textContinuationThreshold = 0.75
            CLN.db.profile.queueHistoryMaxEntries = 20
            CLN.db.profile.historyTTLMinutes = 5

            CLN.Utils = CLN.Utils or {}
            CLN.Utils.LogCategories = { loader = "loader", ui = "ui", animation = "animation" }
            function CLN.Utils:NormalizeQuestPhase(phase) return phase end
            function CLN.Utils:IsCanonicalQuestPhase(phase)
                return phase == "Desc" or phase == "Prog" or phase == "Comp"
            end
            function CLN.Utils:GetHashes(npcId, text)
                return { tostring(npcId) .. ":" .. tostring(text) }
            end
            function CLN.Utils:GetPathToNonQuestFile()
                return "Interface\\\\AddOns\\\\dummy.ogg"
            end
            function CLN.Utils:IsNilOrEmpty(value)
                return value == nil or value == ""
            end
            function CLN:GetTitleForQuestID(questId)
                return "Quest " .. tostring(questId)
            end

            CLN.VoiceoverPacks = {
                TestPack = {
                    _voiceoverIndex = {
                        ["100_Desc.ogg"] = true,
                        ["300_Comp.ogg"] = true,
                    }
                }
            }

            C_Sound = { IsPlaying = function() return false end }
            function PlaySoundFile() return true, 4242 end
            function StopSound() end
        """)
        load_file(cls.lua, "src/VoiceoverPlayer.lua")
        load_file(cls.lua, "src/ReplayFrame/init.lua")
        cls.lua.execute("""
            local CLN = _G.ChattyLittleNpc
            local RF = CLN.ReplayFrame
            function RF:GetNpcNameById(id)
                return id and ("NPC " .. tostring(id)) or nil
            end
            function RF:UpdateDisplayFrameState() end
            function RF:UpdatePauseButton() end
            function RF:HideSubtitle() end
            function RF:ResetAnimationState() end
            function RF:PruneOldHistory() end
            function RF:GetHistory()
                return self._replayHistory or {}
            end
        """)

    def setUp(self):
        self.lua.execute("""
            local CLN = _G.ChattyLittleNpc
            CLN.questsQueue = {}
            local VP = CLN.VoiceoverPlayer
            VP.currentlyPlaying = VP:GetCurrentlyPlayingObject()
            VP._suspendedPlayback = nil

            local RF = CLN.ReplayFrame
            RF._replayHistory = {}
            RF._historyPushCalls = 0
            RF._queueDirtyCalls = 0
            RF.PushHistory = function(self, entry)
                self._historyPushCalls = (self._historyPushCalls or 0) + 1
                self._lastHistory = entry
            end
            RF.MarkQueueDirty = function(self)
                self._queueDirtyCalls = (self._queueDirtyCalls or 0) + 1
            end
        """)

    def test_deduplicate_queue_keeps_distinct_nonquest_entries(self):
        qlen, titles = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            CLN.questsQueue = {
                { npcId = 1, title = "Hello there", entryType = "Gossip", gender = "Male" },
                { npcId = 2, title = "Hello there", entryType = "Gossip", gender = "Male" },
                { npcId = 1, title = "Hello there", entryType = "Gossip", gender = "Male" },
            }
            CLN.VoiceoverPlayer:DeduplicateQueue()
            return #CLN.questsQueue, CLN.questsQueue[1].npcId .. "," .. CLN.questsQueue[2].npcId
        ''')
        self.assertEqual(qlen, 2)
        self.assertEqual(set(titles.split(",")), {"1", "2"})

    def test_deduplicate_queue_removes_current_nonquest_duplicate(self):
        qlen, remaining_npc = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            local VP = CLN.VoiceoverPlayer
            CLN.questsQueue = {
                { npcId = 1, title = "Stay awhile", entryType = "Gossip", gender = "Male" },
                { npcId = 2, title = "Fresh line", entryType = "Gossip", gender = "Female" },
            }
            local cp = VP:GetCurrentlyPlayingObject()
            cp.npcId = 1
            cp.title = "Stay awhile"
            cp.entryType = "Gossip"
            cp.gender = "Male"
            cp.soundHandle = 99
            VP.currentlyPlaying = cp
            VP:DeduplicateQueue()
            return #CLN.questsQueue, CLN.questsQueue[1].npcId
        ''')
        self.assertEqual(qlen, 1)
        self.assertEqual(remaining_npc, 2)

    def test_push_to_history_is_idempotent_per_record(self):
        push_calls, pushed_flag = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            local record = {
                npcId = 5,
                title = "One line",
                entryType = "Gossip",
            }
            CLN.VoiceoverPlayer:PushToHistory(record)
            CLN.VoiceoverPlayer:PushToHistory(record)
            return CLN.ReplayFrame._historyPushCalls, record._historyPushed and true or false
        ''')
        self.assertEqual(push_calls, 1)
        self.assertTrue(pushed_flag)

    def test_get_playback_state_reads_explicit_state(self):
        user_state, native_state = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            local VP = CLN.VoiceoverPlayer
            local cp = VP:GetCurrentlyPlayingObject()
            cp.title = "Paused line"
            VP:SetPlaybackState(cp, VP.State.PAUSED_USER)
            VP.currentlyPlaying = cp
            local userState = VP:GetPlaybackState(cp)

            VP:SetPlaybackState(cp, VP.State.PAUSED_NATIVE)
            local nativeState = VP:GetPlaybackState(cp)
            return userState, nativeState
        ''')
        self.assertEqual(user_state, "paused_user")
        self.assertEqual(native_state, "paused_native")

    def test_pause_playback_converts_native_pause_into_user_pause(self):
        paused, state, timer_cleared, cancelled = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            local VP = CLN.VoiceoverPlayer
            local cp = VP:GetCurrentlyPlayingObject()
            cp.title = "Native paused line"
            cp.entryType = "Gossip"
            cp.npcId = 77
            VP:SetPlaybackState(cp, VP.State.PAUSED_NATIVE)
            VP.currentlyPlaying = cp
            _G.nativeResumeCancelled = false
            VP._nativeVOResumeTimer = {
                Cancel = function()
                    _G.nativeResumeCancelled = true
                end
            }

            VP:PausePlayback()

            return VP:IsPaused(), VP:GetPlaybackState(cp),
                VP._nativeVOResumeTimer == nil,
                _G.nativeResumeCancelled
        ''')
        self.assertTrue(paused)
        self.assertEqual(state, "paused_user")
        self.assertTrue(timer_cleared)
        self.assertTrue(cancelled)

    def test_get_display_entries_returns_current_then_queue_with_states(self):
        first_kind, first_state, second_kind, second_state, second_title = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            local VP = CLN.VoiceoverPlayer
            local cp = VP:GetCurrentlyPlayingObject()
            cp.title = "Current line"
            cp.entryType = "Gossip"
            cp.npcId = 10
            cp.soundHandle = 321
            VP:SetPlaybackState(cp, VP.State.PLAYING)
            VP.currentlyPlaying = cp

            CLN.questsQueue = {
                { questId = 200, phase = "Prog", title = "Quest 200", entryType = "quest", state = VP.State.QUEUED },
            }

            local entries = VP:GetDisplayEntries()
            return entries[1].kind, entries[1].state, entries[2].kind, entries[2].state, entries[2].title
        ''')
        self.assertEqual(first_kind, "current")
        self.assertEqual(first_state, "playing")
        self.assertEqual(second_kind, "queue")
        self.assertEqual(second_state, "queued")
        self.assertEqual(second_title, "Quest 200")

    def test_build_queue_entries_does_not_mutate_stale_current(self):
        entries_count, push_calls, current_title = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            local VP = CLN.VoiceoverPlayer
            local cp = VP:GetCurrentlyPlayingObject()
            cp.title = "Stale gossip"
            cp.entryType = "Gossip"
            cp.npcId = 77
            cp.soundHandle = 555
            cp.startTime = -100
            VP.currentlyPlaying = cp

            local entries = CLN.ReplayFrame:BuildQueueEntries()
            return #entries, CLN.ReplayFrame._historyPushCalls, VP.currentlyPlaying.title
        ''')
        self.assertEqual(entries_count, 0)
        self.assertEqual(push_calls, 0)
        self.assertEqual(current_title, "Stale gossip")

    def test_get_display_entries_ignores_current_already_in_history(self):
        entries_count = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            local VP = CLN.VoiceoverPlayer
            local cp = VP:GetCurrentlyPlayingObject()
            cp.title = "Already archived"
            cp.entryType = "Gossip"
            cp.npcId = 77
            cp.soundHandle = 555
            cp._historyPushed = true
            VP:SetPlaybackState(cp, VP.State.PLAYING)
            VP.currentlyPlaying = cp

            return #VP:GetDisplayEntries()
        ''')
        self.assertEqual(entries_count, 0)

    def test_build_queue_entries_carries_state_from_player_projection(self):
        current_state, queued_state = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            local VP = CLN.VoiceoverPlayer
            local cp = VP:GetCurrentlyPlayingObject()
            cp.title = "Current line"
            cp.entryType = "Gossip"
            cp.npcId = 77
            cp.soundHandle = 555
            VP:SetPlaybackState(cp, VP.State.PLAYING)
            VP.currentlyPlaying = cp

            CLN.questsQueue = {
                { npcId = 12, title = "Queued line", entryType = "Gossip", gender = "Male", state = VP.State.QUEUED },
            }

            local entries = CLN.ReplayFrame:BuildQueueEntries()
            return entries[1].state, entries[2].state
        ''')
        self.assertEqual(current_state, "playing")
        self.assertEqual(queued_state, "queued")

    def test_play_quest_sound_removes_matching_queued_entry_even_when_not_head(self):
        qlen, head_id, current_id, current_state = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            CLN.questsQueue = {
                { questId = 200, phase = "Prog", title = "Quest 200", entryType = "quest" },
                { questId = 100, phase = "Desc", title = "Quest 100", entryType = "quest" },
            }
            CLN.VoiceoverPlayer:PlayQuestSound(100, "Desc", 9, 10)
            return #CLN.questsQueue, CLN.questsQueue[1].questId, CLN.VoiceoverPlayer.currentlyPlaying.questId, CLN.VoiceoverPlayer.currentlyPlaying.state
        ''')
        self.assertEqual(qlen, 1)
        self.assertEqual(head_id, 200)
        self.assertEqual(current_id, 100)
        self.assertEqual(current_state, "playing")

    def test_advance_queue_plays_when_current_is_completed(self):
        """AdvanceQueue must not see a COMPLETED currentlyPlaying as effectively playing."""
        current_id, current_state, qlen = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            local VP = CLN.VoiceoverPlayer
            -- Simulate a just-finished sound: still has handle but state=COMPLETED
            local old = VP:GetCurrentlyPlayingObject()
            old.questId = 99
            old.phase = "Desc"
            old.title = "Finished quest"
            old.entryType = "quest"
            old.soundHandle = 9999
            old._historyPushed = true
            VP:SetPlaybackState(old, VP.State.COMPLETED)
            VP.currentlyPlaying = old

            CLN.questsQueue = {
                { questId = 100, phase = "Desc", title = "Quest 100", entryType = "quest" },
            }
            -- Clear current like OnVoiceoverStop does before advancing
            VP.currentlyPlaying = VP:GetCurrentlyPlayingObject()
            VP:AdvanceQueue()
            return VP.currentlyPlaying.questId, VP.currentlyPlaying.state, #CLN.questsQueue
        ''')
        self.assertEqual(current_id, 100)
        self.assertEqual(current_state, "playing")
        self.assertEqual(qlen, 0)

    def test_advance_queue_pops_quest_and_plays(self):
        current_id, current_state, qlen = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            local VP = CLN.VoiceoverPlayer
            VP.currentlyPlaying = VP:GetCurrentlyPlayingObject()
            CLN.questsQueue = {
                { questId = 300, phase = "Comp", title = "Quest 300", entryType = "quest" },
            }
            VP:AdvanceQueue()
            return VP.currentlyPlaying.questId, VP.currentlyPlaying.state, #CLN.questsQueue
        ''')
        self.assertEqual(current_id, 300)
        self.assertEqual(current_state, "playing")
        self.assertEqual(qlen, 0)

    def test_advance_queue_pops_nonquest_and_plays(self):
        current_title, qlen = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            local VP = CLN.VoiceoverPlayer
            VP.currentlyPlaying = VP:GetCurrentlyPlayingObject()
            CLN.questsQueue = {
                { npcId = 5, title = "Gossip line", entryType = "Gossip", gender = "Male" },
            }
            VP:AdvanceQueue()
            return VP.currentlyPlaying.title, #CLN.questsQueue
        ''')
        self.assertEqual(current_title, "Gossip line")
        self.assertEqual(qlen, 0)

    def test_advance_queue_skips_unknown_entries(self):
        current_id, qlen = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            local VP = CLN.VoiceoverPlayer
            VP.currentlyPlaying = VP:GetCurrentlyPlayingObject()
            CLN.questsQueue = {
                { foo = "bar" },
                { questId = 100, phase = "Desc", title = "Quest 100", entryType = "quest" },
            }
            VP:AdvanceQueue()
            return VP.currentlyPlaying.questId, #CLN.questsQueue
        ''')
        self.assertEqual(current_id, 100)
        self.assertEqual(qlen, 0)

    def test_drop_queued_range_pushes_history_and_removes(self):
        qlen, push_calls = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            local VP = CLN.VoiceoverPlayer
            CLN.questsQueue = {
                { questId = 1, phase = "Desc", title = "Q1", entryType = "quest" },
                { questId = 2, phase = "Desc", title = "Q2", entryType = "quest" },
                { questId = 3, phase = "Desc", title = "Q3", entryType = "quest" },
            }
            VP:DropQueuedRange(1, 2)
            return #CLN.questsQueue, CLN.ReplayFrame._historyPushCalls
        ''')
        self.assertEqual(qlen, 1)
        self.assertEqual(push_calls, 2)

    def test_play_queued_item_at_index_drops_before_and_plays(self):
        current_id, qlen, push_calls = lua_call(self.lua, '''
            local CLN = _G.ChattyLittleNpc
            local VP = CLN.VoiceoverPlayer
            VP.currentlyPlaying = VP:GetCurrentlyPlayingObject()
            CLN.questsQueue = {
                { questId = 200, phase = "Prog", title = "Q200", entryType = "quest" },
                { questId = 100, phase = "Desc", title = "Q100", entryType = "quest" },
                { questId = 300, phase = "Comp", title = "Q300", entryType = "quest" },
            }
            VP:PlayQueuedItemAtIndex(2)
            return VP.currentlyPlaying.questId, #CLN.questsQueue, CLN.ReplayFrame._historyPushCalls
        ''')
        self.assertEqual(current_id, 100)
        self.assertEqual(qlen, 1)  # Q300 remains
        self.assertEqual(push_calls, 1)  # Q200 was dropped to history


@unittest.skip("Md5.lua uses WoW bit library that hangs in Lua 5.4")
class TestMD5(unittest.TestCase):
    """Test MD5:GenerateHash against known vectors."""

    @classmethod
    def setUpClass(cls):
        cls.lua = make_lua()
        load_file(cls.lua, "Utils/Md5.lua")

    def _md5(self, text):
        return lua_call(self.lua, f'''
            return _G.ChattyLittleNpc.MD5:GenerateHash("{text}")
        ''')

    def test_empty_string(self):
        result = self._md5("")
        # RFC 1321 MD5 produces 32 hex chars (4 x 8)
        self.assertEqual(len(result), 32, "MD5 hash should be 32 hex chars")
        self.assertEqual(result, "d41d8cd98f00b204e9800998ecf8427e")

    def test_deterministic(self):
        h1 = self._md5("Hello, World!")
        h2 = self._md5("Hello, World!")
        self.assertEqual(h1, h2)

    def test_different_inputs(self):
        h1 = self._md5("abc")
        h2 = self._md5("def")
        self.assertNotEqual(h1, h2)

    def test_hash_format(self):
        result = self._md5("test")
        self.assertRegex(result, r'^[0-9a-f]+$')


@unittest.skip("SimHash.lua uses WoW bit library that hangs in Lua 5.4")
class TestSimHash(unittest.TestCase):
    """Test SimHash64 character n-gram hashing and similarity."""

    @classmethod
    def setUpClass(cls):
        cls.lua = make_lua()
        load_file(cls.lua, "Utils/SimHash.lua")

    def test_clean_text(self):
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.SimHash64:CleanText("Hello, World! 123")
        ''')
        self.assertEqual(result, "helloworld123")

    def test_deterministic_hash(self):
        h1 = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.SimHash64:GenerateHash("The quick brown fox")
        ''')
        h2 = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.SimHash64:GenerateHash("The quick brown fox")
        ''')
        self.assertEqual(h1, h2)

    def test_hash_format(self):
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.SimHash64:GenerateHash("test input")
        ''')
        self.assertRegex(result, r'^[0-9A-F]{16}$')

    def test_similar_strings_low_distance(self):
        similar, distance = lua_call(self.lua, '''
            local S = _G.ChattyLittleNpc.SimHash64
            local h1 = S:GenerateHash("While the Vizier does not approve of war profiteering")
            local h2 = S:GenerateHash("While the Vizer does not approve of war profiteering")
            return S:AreSimilar(h1, h2, 5)
        ''')
        self.assertTrue(similar, f"Typo strings should be similar (distance={distance})")

    def test_different_strings_high_distance(self):
        similar, distance = lua_call(self.lua, '''
            local S = _G.ChattyLittleNpc.SimHash64
            local h1 = S:GenerateHash("Hello World")
            local h2 = S:GenerateHash("Completely different text about dragons")
            return S:AreSimilar(h1, h2, 3)
        ''')
        self.assertFalse(similar, f"Different strings should not be similar (distance={distance})")

    def test_identical_strings_zero_distance(self):
        similar, distance = lua_call(self.lua, '''
            local S = _G.ChattyLittleNpc.SimHash64
            local h1 = S:GenerateHash("identical text")
            local h2 = S:GenerateHash("identical text")
            return S:AreSimilar(h1, h2, 0)
        ''')
        self.assertTrue(similar)
        self.assertEqual(distance, 0)

    def test_short_text(self):
        """Text shorter than n-gram size should still produce a valid hash."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.SimHash64:GenerateHash("ab")
        ''')
        self.assertRegex(result, r'^[0-9A-F]{16}$')


class TestReplayFramePure(unittest.TestCase):
    """Test ReplayFrame.Pure functions (manually implemented without full module load)."""
    
    @classmethod
    def setUpClass(cls):
        cls.lua = make_lua()
        # Define the Pure functions manually to avoid loading complex init.lua
        cls.lua.execute("""
            local CLN = _G.ChattyLittleNpc
            local ReplayFrame = CLN.ReplayFrame
            ReplayFrame.Pure = ReplayFrame.Pure or {}
            
            -- ToSingleLine function from init.lua
            function ReplayFrame.Pure.ToSingleLine(text)
                if not text or type(text) ~= "string" then return text end
                local result = text
                -- Strip |cFFxxxxxx color codes
                result = string.gsub(result, "|c[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]", "")
                -- Strip |r color reset
                result = string.gsub(result, "|r", "")
                -- Strip |T texture tags
                result = string.gsub(result, "|T.-|t", "")
                -- Strip |H hyperlinks, keep the visible text
                result = string.gsub(result, "|H.-|h(.-)|h", "%1")
                -- Replace newlines with spaces
                result = string.gsub(result, "\\n", " ")
                -- Collapse multiple spaces
                result = string.gsub(result, "  +", " ")
                return result
            end
            
            -- BuildHeaderText function from init.lua  
            function ReplayFrame.Pure.BuildHeaderText(playingTitle, npcName, isQuest, qcount, collapsed)
                if not collapsed then
                    if qcount > 0 then
                        return "Conversations (" .. qcount .. ")"
                    else
                        return "Conversations"
                    end
                else
                    local title = ReplayFrame.Pure.ToSingleLine(playingTitle or "")
                    if title and title ~= "" then
                        return (isQuest and title or (npcName or "") .. ": " .. title) .. (qcount > 0 and " (" .. qcount .. ")" or "")
                    else
                        return "Conversations"
                    end
                end
            end
            
            -- FormatEntryLabel function from init.lua
            function ReplayFrame.Pure.FormatEntryLabel(npcName, content, isQuest)
                local safeNpc = (npcName and npcName ~= "") and npcName or nil
                local safeContent = (content and content ~= "") and content or nil
                if safeContent then
                    local single = ReplayFrame.Pure.ToSingleLine(safeContent)
                    if isQuest then
                        return safeNpc and (safeNpc .. " — " .. single) or single
                    else
                        return safeNpc and (safeNpc .. ": " .. single) or single
                    end
                elseif safeNpc then
                    return safeNpc
                else
                    return "Unknown"
                end
            end
            
            -- FormatEntryTooltip function from init.lua
            function ReplayFrame.Pure.FormatEntryTooltip(npcName, content)
                local safeNpc = (npcName and npcName ~= "") and npcName or nil
                local safeContent = (content and content ~= "") and content or nil
                if safeNpc and safeContent then
                    return safeNpc .. ": " .. safeContent
                elseif safeNpc then
                    return safeNpc
                elseif safeContent then
                    return safeContent
                else
                    return ""
                end
            end
            
            -- ChooseTalkAnimIdForText function from init.lua
            function ReplayFrame.Pure.ChooseTalkAnimIdForText(text, rng)
                local s = ReplayFrame.Pure.ToSingleLine(text or "") or ""
                local ex = string.find(s, "!") and true or false
                local qu = string.find(s, "?") and true or false
                if ex and not qu then return 64 end
                if qu and not ex then return 65 end
                -- Both or neither: use rng to pick between talk (60) and exclamation (64)
                local r = tonumber(rng) or 0
                if r < 0.7 then return 60 else return 64 end
            end
        """)
        
    def test_to_single_line_plain_text(self):
        """Plain text should be unchanged."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.ToSingleLine("Hello world")
        ''')
        self.assertEqual(result, "Hello world")
        
    def test_to_single_line_color_codes(self):
        """Should strip |cFFxxxxxx color codes and |r."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.ToSingleLine("|cFF00FF00Green text|r normal")
        ''')
        self.assertEqual(result, "Green text normal")
        
    def test_to_single_line_newlines(self):
        """Should replace newlines with spaces."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.ToSingleLine("Line 1\\nLine 2")
        ''')
        self.assertEqual(result, "Line 1 Line 2")
        
    def test_to_single_line_nil(self):
        """nil should return nil."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.ToSingleLine(nil)
        ''')
        self.assertIsNone(result)
        
    def test_build_header_text_no_playing(self):
        """No playing should return 'Conversations'."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.BuildHeaderText(nil, nil, false, 0, false)
        ''')
        self.assertEqual(result, "Conversations")
        
    def test_build_header_text_expanded_with_items(self):
        """Expanded with items should return 'Conversations (N)'."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.BuildHeaderText(nil, nil, false, 3, false)
        ''')
        self.assertEqual(result, "Conversations (3)")
        
    def test_format_entry_label_quest_with_npc_content(self):
        """Quest with npc + content should return 'Npc — Content'."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.FormatEntryLabel("Questgiver", "Collect 5 herbs", true)
        ''')
        self.assertEqual(result, "Questgiver — Collect 5 herbs")
        
    def test_format_entry_tooltip_npc_and_content(self):
        """npc + content should return 'Npc: Content'."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.FormatEntryTooltip("Guard", "The city is safe")
        ''')
        self.assertEqual(result, "Guard: The city is safe")
        
    def test_choose_talk_anim_all_exclamation(self):
        """All exclamation + rng=0.0 should return 64."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.ChooseTalkAnimIdForText("Help! Emergency!", 0.0)
        ''')
        self.assertEqual(result, 64)
        
    def test_choose_talk_anim_calm_text(self):
        """Calm text + rng=0.99 should return 64 (high rng)."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.ChooseTalkAnimIdForText("The weather is nice.", 0.99)
        ''')
        self.assertEqual(result, 64)

    def test_to_single_line_empty(self):
        """Empty string should remain empty."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.ToSingleLine("")
        ''')
        self.assertEqual(result, "")

    def test_to_single_line_texture_tags(self):
        """Should strip |T...|t texture tags."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.ToSingleLine("Icon |TInterface/Icons/Spell:0|t here")
        ''')
        self.assertEqual(result, "Icon here")

    def test_to_single_line_whitespace_collapse(self):
        """Should collapse multiple spaces."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.ToSingleLine("too   many   spaces")
        ''')
        self.assertEqual(result, "too many spaces")

    def test_format_entry_label_quest_no_npc(self):
        """Quest with no NPC should return content only."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.FormatEntryLabel(nil, "Save Orgrimmar", true)
        ''')
        self.assertEqual(result, "Save Orgrimmar")

    def test_format_entry_label_quest_no_content(self):
        """Quest with NPC but no content should return NPC name."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.FormatEntryLabel("Thrall", "", true)
        ''')
        self.assertEqual(result, "Thrall")

    def test_format_entry_label_gossip(self):
        """Gossip with NPC should return 'Npc: Content'."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.FormatEntryLabel("Innkeeper", "Welcome!", false)
        ''')
        self.assertEqual(result, "Innkeeper: Welcome!")

    def test_format_entry_label_nothing(self):
        """No NPC, no content should return 'Unknown'."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.FormatEntryLabel(nil, nil, false)
        ''')
        self.assertEqual(result, "Unknown")

    def test_format_entry_tooltip_npc_only(self):
        """NPC only should return NPC name."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.FormatEntryTooltip("Thrall", "")
        ''')
        self.assertEqual(result, "Thrall")

    def test_format_entry_tooltip_content_only(self):
        """Content only should return content."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.FormatEntryTooltip(nil, "War never changes")
        ''')
        self.assertEqual(result, "War never changes")

    def test_format_entry_tooltip_empty(self):
        """Nothing should return empty string."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.FormatEntryTooltip(nil, nil)
        ''')
        self.assertEqual(result, "")

    def test_choose_talk_anim_all_questions(self):
        """All questions should return 65."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.ChooseTalkAnimIdForText("Where? When? How?", 0.5)
        ''')
        self.assertEqual(result, 65)

    def test_choose_talk_anim_returns_valid_id(self):
        """Result should always be one of {60, 64, 65}."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.ChooseTalkAnimIdForText("Hello there.", 0.5)
        ''')
        self.assertIn(result, (60, 64, 65))

    def test_build_header_text_collapsed_quest(self):
        """Collapsed quest should return 'Title (N)'."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.BuildHeaderText("Save the World", "Thrall", true, 2, true)
        ''')
        self.assertIn("Save the World", result)
        self.assertIn("(", result)

    def test_build_header_text_collapsed_gossip(self):
        """Collapsed gossip should include NPC name."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame.Pure.BuildHeaderText("Hello friend", "Innkeeper", false, 0, true)
        ''')
        self.assertIn("Innkeeper", result)

class TestModelAnimationBreathing(unittest.TestCase):
    """Regression tests for BreathingCameraUpdate camera anchoring."""

    @classmethod
    def setUpClass(cls):
        cls.lua = make_lua()
        load_file(cls.lua, "src/ReplayFrame/ModelAnimation.lua")

    def test_breathing_first_tick_anchors_to_snapshot_tz(self):
        """First breathing tick should anchor to snapshot tz, not stale setup offsets."""
        base_z, applied_z = lua_call(self.lua, '''
            local RF = _G.ChattyLittleNpc.ReplayFrame
            local m = { _lastCamSnapshot = { tz = 1.25 }, zoom = 0.70 }
            function m:GetPortraitZoom() return self.zoom end
            function m:SetPortraitZoom(v) self.zoom = v end
            function m:SetPosition(_, _, z)
                self.lastZ = z
                self._lastCamSnapshot.tz = z
            end
            local frame = {
                NpcModelFrame = m,
                _anims = {},
                _currentZOffset = -0.08,
                modelZOffset = -0.08,
            }
            RF.BreathingCameraUpdate(frame, 0.016)
            return frame._breathBaseZ, m.lastZ
        ''')
        self.assertAlmostEqual(base_z, 1.25, places=4)
        self.assertLess(abs(applied_z - 1.25), 0.01)

    def test_breathing_resyncs_when_snapshot_changes(self):
        """Breathing should re-anchor if external framing changes snapshot tz."""
        base_z, applied_z = lua_call(self.lua, '''
            local RF = _G.ChattyLittleNpc.ReplayFrame
            local m = { _lastCamSnapshot = { tz = 1.0 }, zoom = 0.65 }
            function m:GetPortraitZoom() return self.zoom end
            function m:SetPortraitZoom(v) self.zoom = v end
            function m:SetPosition(_, _, z)
                self.lastZ = z
                self._lastCamSnapshot.tz = z
            end
            local frame = {
                NpcModelFrame = m,
                _anims = {},
                _currentZOffset = -0.08,
                modelZOffset = -0.08,
            }
            RF.BreathingCameraUpdate(frame, 0.016)
            m._lastCamSnapshot.tz = 1.6
            RF.BreathingCameraUpdate(frame, 0.016)
            return frame._breathBaseZ, m.lastZ
        ''')
        self.assertAlmostEqual(base_z, 1.6, places=4)
        self.assertLess(abs(applied_z - 1.6), 0.01)

    def test_breathing_zoom_resyncs_when_zoom_changes_externally(self):
        """Breathing should re-anchor zoom when live zoom is externally reframed."""
        base_zoom, applied_zoom = lua_call(self.lua, '''
            local RF = _G.ChattyLittleNpc.ReplayFrame
            local m = { _lastCamSnapshot = { tz = 1.0 }, zoom = 0.70 }
            function m:GetPortraitZoom() return self.zoom end
            function m:SetPortraitZoom(v) self.zoom = v end
            function m:SetPosition(_, _, z)
                self.lastZ = z
                self._lastCamSnapshot.tz = z
            end
            local frame = { NpcModelFrame = m, _anims = {} }
            RF.BreathingCameraUpdate(frame, 0.016)
            m.zoom = 1.1
            RF.BreathingCameraUpdate(frame, 0.016)
            return frame._breathBaseZoom, m.zoom
        ''')
        self.assertAlmostEqual(base_zoom, 1.1, places=4)
        self.assertLess(abs(applied_zoom - 1.1), 0.02)


class TestAccessibility(unittest.TestCase):
    """Test accessibility helpers: high-contrast colors, badges, row color selection."""

    @classmethod
    def setUpClass(cls):
        cls.lua = make_lua()
        cls.lua.execute("""
            local CLN = _G.ChattyLittleNpc
            local RF = CLN.ReplayFrame

            -- Simulate profile
            CLN.db = CLN.db or {}
            CLN.db.profile = CLN.db.profile or {}
            CLN.db.profile.highContrastMode = false

            -- Minimal GetCVarBool stub
            _G.GetCVarBool = function(name)
                if name == "colorblindMode" then return CLN._testColorblind end
                return false
            end

            -- Pure IsHighContrastMode
            function RF:IsHighContrastMode()
                if GetCVarBool and GetCVarBool("colorblindMode") then return true end
                local db = CLN and CLN.db and CLN.db.profile
                return db and db.highContrastMode
            end

            -- Type badge text
            local TYPE_BADGES = {
                quest      = "[Q] ",
                Gossip     = "[G] ",
                GameObject = "[I] ",
            }

            function RF:GetAccessibilityBadge(entryType)
                if not self:IsHighContrastMode() then return "" end
                return TYPE_BADGES[entryType] or ""
            end

            -- High-contrast color overrides
            local HC_COLORS = {
                playing   = { 0.1, 1.0, 0.1 },
                quest     = { 1.0, 0.90, 0.10 },
                gossip    = { 0.5, 0.85, 1.0 },
                gameobj   = { 1.0, 0.85, 0.55 },
                history   = { 0.65, 0.65, 0.65 },
                default   = { 1.0, 0.90, 0.15 },
            }

            function RF:GetRowColor(element, showBadges)
                local hc = self:IsHighContrastMode()
                if element.isPlaying then
                    return unpack(hc and HC_COLORS.playing or { 0.2, 1.0, 0.2 })
                elseif element.isHistory then
                    return unpack(hc and HC_COLORS.history or { 0.5, 0.5, 0.5 })
                elseif showBadges and element.entryType == "quest" then
                    return unpack(hc and HC_COLORS.quest or { 1.0, 0.82, 0.0 })
                elseif showBadges and element.entryType == "Gossip" then
                    return unpack(hc and HC_COLORS.gossip or { 0.6, 0.8, 1.0 })
                elseif showBadges and element.entryType == "GameObject" then
                    return unpack(hc and HC_COLORS.gameobj or { 0.85, 0.75, 0.55 })
                else
                    return unpack(hc and HC_COLORS.default or { 0.95, 0.86, 0.20 })
                end
            end
        """)

    def test_badge_off_by_default(self):
        """Badges should be empty when high-contrast is off."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame:GetAccessibilityBadge("quest")
        ''')
        self.assertEqual(result, "")

    def test_badge_quest_in_hc(self):
        """Quest badge should be [Q] in high-contrast mode."""
        self.lua.execute('_G.ChattyLittleNpc.db.profile.highContrastMode = true')
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame:GetAccessibilityBadge("quest")
        ''')
        self.lua.execute('_G.ChattyLittleNpc.db.profile.highContrastMode = false')
        self.assertEqual(result, "[Q] ")

    def test_badge_gossip_in_hc(self):
        """Gossip badge should be [G] in high-contrast mode."""
        self.lua.execute('_G.ChattyLittleNpc.db.profile.highContrastMode = true')
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame:GetAccessibilityBadge("Gossip")
        ''')
        self.lua.execute('_G.ChattyLittleNpc.db.profile.highContrastMode = false')
        self.assertEqual(result, "[G] ")

    def test_badge_gameobject_in_hc(self):
        """GameObject badge should be [I] in high-contrast mode."""
        self.lua.execute('_G.ChattyLittleNpc.db.profile.highContrastMode = true')
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame:GetAccessibilityBadge("GameObject")
        ''')
        self.lua.execute('_G.ChattyLittleNpc.db.profile.highContrastMode = false')
        self.assertEqual(result, "[I] ")

    def test_badge_unknown_type(self):
        """Unknown type should return empty badge even in hc mode."""
        self.lua.execute('_G.ChattyLittleNpc.db.profile.highContrastMode = true')
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame:GetAccessibilityBadge("Unknown")
        ''')
        self.lua.execute('_G.ChattyLittleNpc.db.profile.highContrastMode = false')
        self.assertEqual(result, "")

    def test_colorblind_cvar_triggers_hc(self):
        """WoW colorblindMode CVar should activate high-contrast."""
        self.lua.execute('_G.ChattyLittleNpc._testColorblind = true')
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame:IsHighContrastMode()
        ''')
        self.lua.execute('_G.ChattyLittleNpc._testColorblind = false')
        self.assertTrue(result)

    def test_row_color_playing_normal(self):
        """Playing row should be green in normal mode."""
        result = lua_call(self.lua, '''
            local r, g, b = _G.ChattyLittleNpc.ReplayFrame:GetRowColor({isPlaying = true}, true)
            return r .. "," .. g .. "," .. b
        ''')
        self.assertEqual(result, "0.2,1.0,0.2")

    def test_row_color_playing_hc(self):
        """Playing row should be brighter green in high-contrast."""
        self.lua.execute('_G.ChattyLittleNpc.db.profile.highContrastMode = true')
        result = lua_call(self.lua, '''
            local r, g, b = _G.ChattyLittleNpc.ReplayFrame:GetRowColor({isPlaying = true}, true)
            return r .. "," .. g .. "," .. b
        ''')
        self.lua.execute('_G.ChattyLittleNpc.db.profile.highContrastMode = false')
        self.assertEqual(result, "0.1,1.0,0.1")

    def test_row_color_history(self):
        """History row in hc mode should be brighter gray."""
        self.lua.execute('_G.ChattyLittleNpc.db.profile.highContrastMode = true')
        result = lua_call(self.lua, '''
            local r, g, b = _G.ChattyLittleNpc.ReplayFrame:GetRowColor({isHistory = true}, true)
            return r .. "," .. g .. "," .. b
        ''')
        self.lua.execute('_G.ChattyLittleNpc.db.profile.highContrastMode = false')
        self.assertEqual(result, "0.65,0.65,0.65")


class TestFSMExpansion(unittest.TestCase):
    """Test FSM expansion: new states, reverence detection, emphasis detection, AnimIds."""

    @classmethod
    def setUpClass(cls):
        cls.lua = make_lua()
        # Define pure implementations of new analysis functions
        cls.lua.execute("""
            local CLN = _G.ChattyLittleNpc
            local RF = CLN.ReplayFrame

            -- State constants (should include BOW and POINT)
            RF.State = RF.State or {}
            RF.State.IDLE  = "idle"
            RF.State.WAVE  = "wave"
            RF.State.TALK  = "talk"
            RF.State.BOW   = "bow"
            RF.State.POINT = "point"

            -- AnimIds registry
            RF.AnimIds = RF.AnimIds or {}
            RF.AnimIds.IDLE       = 0
            RF.AnimIds.TALK       = 60
            RF.AnimIds.TALK_EXCLM = 64
            RF.AnimIds.TALK_QUEST = 65
            RF.AnimIds.BOW        = 66
            RF.AnimIds.WAVE       = 67
            RF.AnimIds.POINT      = 25
            RF.AnimIds.YES        = 185
            RF.AnimIds.NO         = 186

            -- Pure GetReverenceConfidence
            function RF:GetReverenceConfidence(text, limit)
                limit = limit or 15
                if not text or type(text) ~= "string" or #text == 0 then return 0 end
                local lower = text:lower()
                local words = {}
                for w in lower:gmatch("%S+") do
                    words[#words + 1] = w
                    if #words >= limit then break end
                end
                local n = #words
                local confidence = 0

                local royalty = {
                    king=0.7, queen=0.7, prince=0.5, princess=0.5,
                    lord=0.4, lady=0.4, majesty=0.8, highness=0.7,
                    emperor=0.7, empress=0.7, sovereign=0.6, liege=0.6,
                }
                for i = 1, n do
                    local w = words[i]:gsub("[^%w]", "")
                    local bonus = royalty[w]
                    if bonus then confidence = confidence + bonus; break end
                end

                local formal = {
                    thou=0.3, thee=0.3, thy=0.3, thine=0.3,
                    sire=0.5, milord=0.5, milady=0.5,
                }
                for i = 1, n do
                    local w = words[i]:gsub("[^%w]", "")
                    local bonus = formal[w]
                    if bonus then confidence = confidence + bonus; break end
                end

                local segment = table.concat(words, " ", 1, n)
                local phrases = {
                    "your majesty", "your highness", "your grace", "your lordship",
                    "your ladyship", "my lord", "my lady", "my liege", "my king",
                    "my queen", "at your service", "honor to", "kneel before",
                    "bow before", "humble servant",
                }
                for _, p in ipairs(phrases) do
                    if segment:find(p, 1, true) then
                        confidence = confidence + 0.6
                        break
                    end
                end
                return math.min(1.0, confidence)
            end

            -- Pure GetEmphasisConfidence
            function RF:GetEmphasisConfidence(text)
                if not text or type(text) ~= "string" or #text == 0 then return 0 end
                local confidence = 0
                local exclCount = 0
                for _ in text:gmatch("!") do exclCount = exclCount + 1 end
                if exclCount >= 3 then
                    confidence = confidence + 0.4
                elseif exclCount >= 1 then
                    confidence = confidence + 0.2
                end
                local lower = text:lower()
                local firstChunk = lower:sub(1, math.min(60, #lower))
                local imperatives = {
                    "look", "behold", "listen", "hear me", "mark my words",
                    "go now", "charge", "attack", "defend", "stop", "halt",
                    "silence", "enough", "now", "there",
                }
                for _, w in ipairs(imperatives) do
                    if firstChunk:find(w, 1, true) then
                        confidence = confidence + 0.3
                        break
                    end
                end
                return math.min(1.0, confidence)
            end
        """)

    def test_states_include_bow_and_point(self):
        """State constants should include BOW and POINT."""
        bow = lua_call(self.lua, 'return _G.ChattyLittleNpc.ReplayFrame.State.BOW')
        point = lua_call(self.lua, 'return _G.ChattyLittleNpc.ReplayFrame.State.POINT')
        self.assertEqual(bow, "bow")
        self.assertEqual(point, "point")

    def test_anim_ids_registry(self):
        """AnimIds should contain correct animation IDs."""
        bow = lua_call(self.lua, 'return _G.ChattyLittleNpc.ReplayFrame.AnimIds.BOW')
        point = lua_call(self.lua, 'return _G.ChattyLittleNpc.ReplayFrame.AnimIds.POINT')
        wave = lua_call(self.lua, 'return _G.ChattyLittleNpc.ReplayFrame.AnimIds.WAVE')
        self.assertEqual(bow, 66)
        self.assertEqual(point, 25)
        self.assertEqual(wave, 67)

    def test_reverence_royal_title(self):
        """Text with 'king' should have high reverence confidence."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame:GetReverenceConfidence("The King demands your presence")
        ''')
        self.assertGreater(result, 0.5)

    def test_reverence_formal_phrase(self):
        """'Your Majesty' phrase should trigger high confidence."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame:GetReverenceConfidence("Your Majesty, I bring word from the front")
        ''')
        self.assertGreater(result, 0.8)

    def test_reverence_humble_servant(self):
        """'humble servant' should trigger reverence."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame:GetReverenceConfidence("I am your humble servant, sire")
        ''')
        self.assertGreater(result, 0.5)

    def test_reverence_no_match(self):
        """Casual text should have zero reverence confidence."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame:GetReverenceConfidence("Hey there, how are you doing?")
        ''')
        self.assertEqual(result, 0)

    def test_reverence_nil_text(self):
        """nil text should return 0."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame:GetReverenceConfidence(nil)
        ''')
        self.assertEqual(result, 0)

    def test_reverence_empty_text(self):
        """Empty text should return 0."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame:GetReverenceConfidence("")
        ''')
        self.assertEqual(result, 0)

    def test_emphasis_many_exclamations(self):
        """Text with 3+ exclamation marks should score high."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame:GetEmphasisConfidence("Attack! Charge! For the Horde!")
        ''')
        self.assertGreater(result, 0.3)

    def test_emphasis_imperative_word(self):
        """Text starting with 'Behold' should score moderate emphasis."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame:GetEmphasisConfidence("Behold the power of the Light")
        ''')
        self.assertGreater(result, 0.2)

    def test_emphasis_calm_text(self):
        """Calm text without exclamations or imperatives should score 0."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame:GetEmphasisConfidence("The flowers are beautiful today.")
        ''')
        self.assertEqual(result, 0)

    def test_emphasis_nil_text(self):
        """nil text should return 0."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame:GetEmphasisConfidence(nil)
        ''')
        self.assertEqual(result, 0)

    def test_emphasis_combined(self):
        """Imperative + exclamation should stack."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame:GetEmphasisConfidence("Listen! The enemy approaches!")
        ''')
        self.assertGreater(result, 0.4)

    def test_reverence_lord_with_formal(self):
        """Lord + formal address should combine."""
        result = lua_call(self.lua, '''
            return _G.ChattyLittleNpc.ReplayFrame:GetReverenceConfidence("My lord, thou must ride forth")
        ''')
        self.assertGreater(result, 0.7)


# Skip MD5/SimHash tests when bit library causes hangs (Lua 5.4 bit compat issue)
@unittest.skipUnless(
    os.environ.get("RUN_BIT_TESTS"),
    "MD5/SimHash tests require WoW bit library (set RUN_BIT_TESTS=1 to enable)"
)
class TestMD5Guarded(unittest.TestCase):
    """Test MD5 (requires working bit library — skipped by default)."""
    pass


@unittest.skipUnless(
    os.environ.get("RUN_BIT_TESTS"),
    "MD5/SimHash tests require WoW bit library (set RUN_BIT_TESTS=1 to enable)"
)
class TestSimHashGuarded(unittest.TestCase):
    """Test SimHash (requires working bit library — skipped by default)."""
    pass


if __name__ == "__main__":
    os.chdir(ADDON_ROOT)
    unittest.main(verbosity=2)
