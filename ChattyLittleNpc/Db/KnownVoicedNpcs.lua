-- Known voiced NPCs: baked-in list of NPC names confirmed to have native
-- voice acting in WoW. Seeded from community contributions.
-- Format: { ["NPC Name"] = { ids = { id1, id2, ... } } }
-- Names are the primary key (IDs vary across phases/locations).
--
-- To contribute: enable "Log NPC Texts" in addon settings, play through
-- voiced content, and share your VoicedNpcContributions SavedVariable.

---@type table<string, { ids: number[] }>
KnownVoicedNpcsDB = KnownVoicedNpcsDB or {
    -- Midnight (11.1) — community-confirmed voiced NPCs
    ["Aksem"]                   = { ids = {} },
    ["Alleria Windrunner"]      = { ids = {} },
    ["Alonsus Faol"]            = { ids = {} },
    ["Amarakk"]                 = { ids = {} },
    ["Anduin Wrynn"]            = { ids = {} },
    ["Arator"]                  = { ids = {} },
    ["Astalor Bloodsworn"]      = { ids = {} },
    ["Byarc"]                   = { ids = {} },
    ["Danath Trollbane"]        = { ids = { 250415 } },
    ["Decimus"]                 = { ids = {} },
    ["Dundun"]                  = { ids = {} },
    ["Eitrigg"]                 = { ids = {} },
    ["Eonka"]                   = { ids = {} },
    ["General Amias Bellamy"]   = { ids = {} },
    ["Grand Magister Rommath"]  = { ids = {} },
    ["Hagar"]                   = { ids = {} },
    ["Halduron Brightwing"]     = { ids = {} },
    ["Han'wa"]                  = { ids = {} },
    ["Hannan"]                  = { ids = {} },
    ["High Exarch Turalyon"]    = { ids = {} },
    ["Ku'paal"]                 = { ids = {} },
    ["Kurdran Wildhammer"]      = { ids = {} },
    ["Lady Liadrin"]            = { ids = { 236099 } },
    ["Lor'themar Theron"]       = { ids = { 236572 } },
    ["Lord Maxwell Tyrosus"]    = { ids = {} },
    ["Lord Saltheril"]          = { ids = {} },
    ["Lothraxion"]              = { ids = {} },
    ["Magister Umbric"]         = { ids = {} },
    ["Orweyna"]                 = { ids = {} },
    ["Powdercap"]               = { ids = {} },
    ["Riftblade Maella"]        = { ids = {} },
    ["Riftwalker Hieron"]       = { ids = {} },
    ["Riftwalker Malloril"]     = { ids = {} },
    ["Ruia"]                    = { ids = {} },
    ["Scout Adaephus"]          = { ids = {} },
    ["Sunwalker Dezco"]         = { ids = {} },
    ["T'era"]                   = { ids = {} },
    ["Tarenar Sunstrike"]       = { ids = {} },
    ["Valeera Sanguinar"]       = { ids = {} },
    ["Voidlight Everdawn"]      = { ids = {} },
    ["War Chaplain Senn"]       = { ids = {} },
    ["Zur'ashar Kassameh"]      = { ids = {} },
}
