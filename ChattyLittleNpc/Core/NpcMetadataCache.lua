-- NpcMetadataCache.lua - Persistent NPC metadata cache
-- Automatically captures NPC display info during dialog events and
-- provides fallback lookups for queue/replay when the live unit is gone.
-- Data persists in the NpcMetadataCache SavedVariable with 30-day expiry.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class NpcMetadataCache
local NpcMetadataCache = {}
CLN.NpcMetadataCache = NpcMetadataCache

local DEFAULT_TTL_DAYS = 30
local MAX_ENTRIES = 5000

-- Initialize the SavedVariable table (called on ADDON_LOADED)
function NpcMetadataCache:Initialize()
    if not _G.NpcMetadataCache then
        _G.NpcMetadataCache = {}
    end
    self.db = _G.NpcMetadataCache
end

--- Store metadata for an NPC. Merges with existing data (never overwrites
--- a valid field with nil). Updates lastSeen on every call.
---@param npcId number
---@param data table { displayID, creatureType, gender, name, race }
function NpcMetadataCache:Store(npcId, data)
    if not npcId or not data then return end
    npcId = tonumber(npcId)
    if not npcId or npcId <= 0 then return end

    self:Initialize()
    local existing = self.db[npcId]
    if not existing then
        existing = {}
        self.db[npcId] = existing
    end

    -- Merge fields: only overwrite with non-nil values
    if data.displayID and type(data.displayID) == "number" then existing.displayID = data.displayID end
    if data.creatureType and data.creatureType ~= "" then existing.creatureType = data.creatureType end
    if data.gender and data.gender ~= "" then existing.gender = data.gender end
    if data.name and data.name ~= "" then existing.name = data.name end
    if data.race and data.race ~= "" then existing.race = data.race end

    -- Always update lastSeen (server time for cross-session expiry)
    existing.lastSeen = time()
end

--- Capture all available metadata from the current "npc" unit token and store it.
--- Safe to call at any time; does nothing if the unit is unavailable.
function NpcMetadataCache:CaptureFromUnit()
    if not (UnitExists and UnitExists("npc")) then return nil end

    local unitName, gender, race, unitGuid, unitType, npcId, creatureType
    if CLN.GetUnitInfo then
        unitName, gender, race, unitGuid, unitType, npcId, creatureType = CLN:GetUnitInfo("npc")
    end
    if not npcId then return nil end

    local displayID = (UnitCreatureDisplayID and UnitCreatureDisplayID("npc")) or nil

    self:Store(npcId, {
        displayID = displayID,
        creatureType = creatureType,
        gender = gender,
        name = unitName,
        race = race,
    })

    return npcId
end

--- Look up cached metadata for an NPC.
---@param npcId number
---@return table|nil { displayID, creatureType, gender, name, race, lastSeen }
function NpcMetadataCache:Lookup(npcId)
    if not npcId then return nil end
    npcId = tonumber(npcId)
    if not npcId then return nil end
    self:Initialize()
    return self.db[npcId]
end

--- Enrich a table (queue entry, currentlyPlaying, history record) by filling
--- nil fields from the metadata cache. Does not overwrite existing values.
---@param entry table The entry to enrich (modified in place)
---@return table The same entry, enriched
function NpcMetadataCache:Enrich(entry)
    if not entry or not entry.npcId then return entry end
    local cached = self:Lookup(entry.npcId)
    if not cached then return entry end

    if not entry.displayID then entry.displayID = cached.displayID end
    if not entry.creatureType or entry.creatureType == "" then entry.creatureType = cached.creatureType end
    if not entry.gender or entry.gender == "" then entry.gender = cached.gender end
    if not entry.name or entry.name == "" then entry.name = cached.name end

    return entry
end

--- Prune entries older than maxAgeDays. Called on addon load.
---@param maxAgeDays number|nil Defaults to 30
function NpcMetadataCache:Prune(maxAgeDays)
    self:Initialize()
    local ttl = (maxAgeDays or DEFAULT_TTL_DAYS) * 86400 -- days → seconds
    local now = time()
    local pruned = 0

    for npcId, data in pairs(self.db) do
        if not data.lastSeen or (now - data.lastSeen) > ttl then
            self.db[npcId] = nil
            pruned = pruned + 1
        end
    end

    -- Safety cap: if still over MAX_ENTRIES, remove oldest
    local count = 0
    for _ in pairs(self.db) do count = count + 1 end
    if count > MAX_ENTRIES then
        local entries = {}
        for npcId, data in pairs(self.db) do
            table.insert(entries, { id = npcId, lastSeen = data.lastSeen or 0 })
        end
        table.sort(entries, function(a, b) return a.lastSeen < b.lastSeen end)
        local toRemove = count - MAX_ENTRIES
        for i = 1, toRemove do
            self.db[entries[i].id] = nil
            pruned = pruned + 1
        end
    end

    if pruned > 0 and CLN and CLN.Logger then
        CLN.Logger:debug("NpcMetadataCache: pruned " .. pruned .. " stale entries", false,
            (CLN.Utils and CLN.Utils.LogCategories and CLN.Utils.LogCategories.misc) or "misc")
    end
end

--- Get the total number of cached entries (for debug/stats display).
---@return number
function NpcMetadataCache:GetCount()
    self:Initialize()
    local count = 0
    for _ in pairs(self.db) do count = count + 1 end
    return count
end
