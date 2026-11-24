-- CollectedData.lua - Layout of the collected-text saved variables.
--
-- The NPC and unit tables hold what the player has seen in game, grouped by
-- game language first:
--
--   npcs[locale][npcId]   = { name, sex, race, zone, quests, gossipOptions, ... }
--   units[locale][unitId] = { unitName, unitType, unitTexts, quests }
--
-- The load-on-demand ChattyLittleNpc_Collector addon saves them as
-- ChattyLittleNpc_NpcInfoDB and ChattyLittleNpc_UnitInfoDB. Up to 3.7 the main
-- addon saved them as NpcInfoDB and UnitInfoDB; that data stays there until the
-- collector first loads and moves it. Read them through Npcs() and Units(),
-- which return whichever is present, or nil when neither is.
--
-- Older versions stored the id first (NpcInfoDB[npcId][locale]). Migrate()
-- moves that data into the layout above once, without losing anything:
--   * an id-first entry is moved under its locale; when the locale already has
--     an entry for that id, only fields it is missing (or has empty) are
--     filled in, so text collected in the new layout always wins
--   * the old entry is removed only after everything in it has been moved;
--     anything not recognised is left where it is
--   * an old entry with no locale level at all is filed under the client's
--     locale (it can only have been collected on this client)
--   * ids saved as strings ("123") are merged into the numeric id (123)
-- It is safe to run on every load: once nothing is left in the old layout it
-- only looks at the handful of locale keys and returns.

local CLN = _G.ChattyLittleNpc or {}
_G.ChattyLittleNpc = CLN

local CollectedData = {}
CLN.CollectedData = CollectedData

--- True for a game locale key such as "enUS" or "zhTW" (GetLocale() codes).
---@param key any
---@return boolean
function CollectedData.IsLocaleKey(key)
    return type(key) == "string" and key:match("^%l%l%u%u$") ~= nil
end

--- The id a key stands for: 123 for both 123 and "123", nil for anything else.
local function toId(key)
    if type(key) == "number" then return key end
    if type(key) == "string" and key:match("^%-?%d+$") then return tonumber(key) end
    return nil
end
CollectedData.ToId = toId

-- ============================================================================
-- Accessors
-- ============================================================================

--- The collected NPC table: the collector's when it has loaded, else the one
--- older versions saved in the main addon, else nil.
---@return table|nil
function CollectedData.Npcs()
    local db = _G.ChattyLittleNpc_NpcInfoDB
    if type(db) == "table" then return db end
    db = _G.NpcInfoDB
    return type(db) == "table" and db or nil
end

--- The collected item/game-object table; see Npcs().
---@return table|nil
function CollectedData.Units()
    local db = _G.ChattyLittleNpc_UnitInfoDB
    if type(db) == "table" then return db end
    db = _G.UnitInfoDB
    return type(db) == "table" and db or nil
end

--- The entry for one id in one locale, or nil.
---@param db table|nil NpcInfoDB or UnitInfoDB
---@param id number|string|nil
---@param locale string|nil defaults to the client's locale
---@return table|nil
function CollectedData.Get(db, id, locale)
    id = toId(id)
    locale = locale or CLN.locale
    if type(db) ~= "table" or not id or not locale then return nil end
    local bucket = db[locale]
    return type(bucket) == "table" and bucket[id] or nil
end

--- One locale's table of entries, created when missing.
---@param db table NpcInfoDB or UnitInfoDB
---@param locale string|nil defaults to the client's locale
---@return table
function CollectedData.Bucket(db, locale)
    locale = locale or CLN.locale
    local bucket = db[locale]
    if type(bucket) ~= "table" then
        bucket = {}
        db[locale] = bucket
    end
    return bucket
end

--- Calls fn(id, entry, locale) for every entry of every locale.
---@param db table|nil
---@param fn fun(id: number, entry: table, locale: string)
function CollectedData.ForEach(db, fn)
    if type(db) ~= "table" then return end
    for locale, bucket in pairs(db) do
        if CollectedData.IsLocaleKey(locale) and type(bucket) == "table" then
            for id, entry in pairs(bucket) do
                if type(entry) == "table" then fn(id, entry, locale) end
            end
        end
    end
end

-- ============================================================================
-- Migration
-- ============================================================================

--- Copies into dst whatever src has that dst lacks: missing keys, empty
--- strings, and nested tables key by key. Values dst already has are kept,
--- except a boolean flag that either side has set (hasMultipleGenders).
local function fillMissing(dst, src)
    for key, value in pairs(src) do
        local current = dst[key]
        if current == nil then
            dst[key] = value
        elseif type(current) == "table" and type(value) == "table" then
            fillMissing(current, value)
        elseif current == "" and type(value) == "string" and value ~= "" then
            dst[key] = value
        elseif type(current) == "boolean" and type(value) == "boolean" then
            dst[key] = current or value
        end
    end
end
CollectedData.FillMissing = fillMissing

--- Files one entry under bucket[id], merging when the id is already there.
local function place(bucket, id, entry)
    local existing = bucket[id]
    if existing == nil then
        bucket[id] = entry
    elseif type(existing) == "table" then
        fillMissing(existing, entry)
    end
    -- a non-table already there is left alone; the caller keeps its source
    return type(bucket[id]) == "table"
end

--- An id-first entry with no locale level: its fields sit directly under the id.
local function isFlatEntry(entry)
    for key in pairs(entry) do
        if CollectedData.IsLocaleKey(key) then return false end
    end
    return next(entry) ~= nil
end

--- Moves one saved table into the locale-first layout. Returns how many
--- entries were moved and how many old-layout keys were left in place.
---@param db table
---@param clientLocale string locale for old entries that have none
---@return integer moved
---@return integer kept
function CollectedData.MigrateTable(db, clientLocale)
    if type(db) ~= "table" then return 0, 0 end

    -- Collect first: adding keys to a table while pairs() walks it is undefined.
    local oldKeys, stringLocaleIds = {}, {}
    for key, value in pairs(db) do
        if CollectedData.IsLocaleKey(key) then
            if type(value) == "table" then stringLocaleIds[#stringLocaleIds + 1] = key end
        elseif toId(key) and type(value) == "table" then
            oldKeys[#oldKeys + 1] = key
        end
    end

    -- Numeric keys first, so where an id was saved both as 123 and "123" the
    -- numeric copy (the key used from now on) is placed first and wins on a
    -- conflicting field. On real data the two only differed in line breaks.
    table.sort(oldKeys, function(a, b)
        local an, bn = type(a) == "number", type(b) == "number"
        if an ~= bn then return an end
        return toId(a) < toId(b)
    end)

    -- Within the new layout, fold string ids ("123") into numeric ones (123).
    -- Done before the old layout is moved in, so new-layout data is in place
    -- first and wins over old-layout data for the same id.
    for _, locale in ipairs(stringLocaleIds) do
        local bucket = db[locale]
        local stringIds = {}
        for key, value in pairs(bucket) do
            if type(key) == "string" and toId(key) and type(value) == "table" then
                stringIds[#stringIds + 1] = key
            end
        end
        for _, key in ipairs(stringIds) do
            if place(bucket, toId(key), bucket[key]) then
                bucket[key] = nil
            end
        end
    end

    -- The locale's table to move entries into, or nil when there is no locale or
    -- something other than a table is stored under it (that is left untouched).
    local function target(locale)
        if not locale then return nil end
        local existing = db[locale]
        if existing ~= nil and type(existing) ~= "table" then return nil end
        return CollectedData.Bucket(db, locale)
    end

    local moved, kept = 0, 0

    for _, key in ipairs(oldKeys) do
        local id, entry = toId(key), db[key]

        if isFlatEntry(entry) then
            local bucket = target(clientLocale)
            if bucket and place(bucket, id, entry) then
                moved = moved + 1
                entry = {}
            end
        else
            -- Each locale leaves the old entry as soon as it has been placed, so a
            -- table is never saved twice and only unrecognised keys stay behind.
            -- (Clearing a field during pairs() is allowed; adding one is not.)
            for locale, fields in pairs(entry) do
                local bucket = CollectedData.IsLocaleKey(locale) and type(fields) == "table" and target(locale)
                if bucket and place(bucket, id, fields) then
                    moved = moved + 1
                    entry[locale] = nil
                end
            end
        end

        if next(entry) == nil then
            db[key] = nil
        else
            kept = kept + 1
        end
    end

    return moved, kept
end

--- Moves everything in src into dst (both locale-first collected tables) and
--- leaves src empty. src is brought into the locale-first layout first. Where
--- both have a value, dst keeps its own (see FillMissing).
---@param dst table
---@param src table
---@param clientLocale string locale for old entries that have none
---@return integer moved  how many of src's top-level keys were copied
function CollectedData.MoveInto(dst, src, clientLocale)
    CollectedData.MigrateTable(src, clientLocale)
    local moved = 0
    for key, value in pairs(src) do
        local current = dst[key]
        if current == nil then
            dst[key] = value
        elseif type(current) == "table" and type(value) == "table" then
            fillMissing(current, value)
        end
        moved = moved + 1
    end
    -- Clearing fields during pairs() is allowed; adding them is not.
    for key in pairs(src) do src[key] = nil end
    return moved
end

--- Brings the NpcInfoDB and UnitInfoDB the main addon still saves (versions up
--- to 3.7) into the locale-first layout. Call once the saved variables are
--- loaded (OnInitialize) and before anything reads them. Tables that are not
--- there are left alone, so the main addon stops saving empty ones once the
--- collector has moved the data out.
---@param clientLocale string GetLocale()
function CollectedData:Migrate(clientLocale)
    local npcMoved, npcKept = self.MigrateTable(NpcInfoDB, clientLocale)
    local unitMoved, unitKept = self.MigrateTable(UnitInfoDB, clientLocale)

    if (npcMoved + unitMoved + npcKept + unitKept) > 0 and CLN.Logger and CLN.Utils and CLN.Utils.LogCategories then
        CLN.Logger:info(string.format(
            "Collected text moved to the per-language layout: %d NPC and %d object/item entries%s",
            npcMoved, unitMoved,
            (npcKept + unitKept) > 0
                and string.format(" (%d entries left in the old layout: not recognised)", npcKept + unitKept)
                or ""),
            false, CLN.Utils.LogCategories.misc)
    end
end

return CollectedData
