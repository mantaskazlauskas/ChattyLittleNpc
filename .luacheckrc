-- luacheck config for Chatty Little NPC (run from the repo root: `luacheck ChattyLittleNpc`)
--
-- Main goal: catch accidental globals (a common source of taint and of clashes
-- with other addons) and unused locals.
--
-- Reading undefined globals (W113) is ignored for now because this config has no
-- list of WoW API globals, so every WoW API call would be flagged. To tighten it,
-- add a WoW globals list (e.g. a community `read_globals` table) and remove "113"
-- from `ignore`.

std = "lua51"
max_line_length = false
self = false          -- implicit `self` in methods is often unused
unused_args = false   -- event/script callbacks have fixed signatures

exclude_files = {
    "ChattyLittleNpc/types.lua",   -- LuaLS type annotations only
    "ChattyLittleNpc/tests/**",
}

ignore = {
    "113",  -- accessing undefined global (see note above)
}

-- Globals this addon defines or writes to on purpose
globals = {
    -- Addon namespace
    "ChattyLittleNpc",

    -- SavedVariables (see ChattyLittleNpc.toc)
    "ChattyLittleNpcDB",
    "ChattyLittleNpcCharDB",
    "NpcInfoDB",
    "UnitInfoDB",
    "VoicedNpcContributions",
    "NpcMetadataCache",
    "UnknownRaceModelsDB",

    -- Generated data tables
    "KnownVoicedNpcsDB",

    -- Key binding labels
    "BINDING_HEADER_CHATTYLITTLENPC",
    "BINDING_NAME_CHATTYLITTLENPC_PLAY_VOICEOVER",

    -- Slash commands
    "SlashCmdList",
    "SLASH_CHATTEST1",
    "SLASH_CLNDEBUG1",
    "SLASH_CLNDEBUG2",
    "SLASH_CLNEXP1",
    "SLASH_CLNIMP1",
    "SLASH_CLNLIBRARY1",
    "SLASH_CLNLOGS1",
    "SLASH_CLNMARK1",
    "SLASH_CLNSETTINGS1",
    "SLASH_CLNWELCOME1",
    "SLASH_MD5TEST1",
    "SLASH_SIMHASH64TEST1",

    -- Blizzard tables the addon registers entries in
    "StaticPopupDialogs",
    "UISpecialFrames",

    "ChattyLittleNpc_PendingAtlas",
}
