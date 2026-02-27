-- Known voiced NPCs: baked-in list of NPC names confirmed to have native
-- voice acting in WoW. Seeded from community contributions.
-- Format: { ["NPC Name"] = { ids = { id1, id2, ... } } }
-- Names are the primary key (IDs vary across phases/locations).
--
-- To contribute: enable "Log NPC Texts" in addon settings, play through
-- voiced content, and share your VoicedNpcContributions SavedVariable.

---@type table<string, { ids: number[] }>
KnownVoicedNpcsDB = KnownVoicedNpcsDB or {
    -- The Weeping Bluffs / Midnight (11.1)
    ["Lady Liadrin"]        = { ids = { 236099 } },
    ["Lor'themar Theron"]   = { ids = { 236572 } },
    ["Halduron Brightwing"] = { ids = {} },

    -- Placeholder: add more as community reports come in.
    -- Run /cln export-voiced to dump your whitelist for submission.
}
