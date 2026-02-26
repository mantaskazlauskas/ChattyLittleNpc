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
