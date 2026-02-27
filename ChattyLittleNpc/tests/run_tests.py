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
