#!/usr/bin/env python3
"""
Unit tests for ChattyLittleNpc pure Lua functions.

Uses lupa (Lua 5.4 via Python) to run Lua code outside WoW.
Run: python tests/run_tests.py
"""

import sys
import os
import unittest

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
        function CreateFrame() return {} end
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

            function VP:IsQuestPhaseQueued(questId, phase)
                if not (questId and phase) then return false end
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
        # This addon's MD5 impl produces 40 hex chars (5 x 8)
        self.assertEqual(len(result), 40, "MD5 hash should be 40 hex chars")

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


if __name__ == "__main__":
    os.chdir(ADDON_ROOT)
    unittest.main(verbosity=2)
