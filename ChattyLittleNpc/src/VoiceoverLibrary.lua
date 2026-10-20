---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

-- ============================================================================
-- Voiceover Library
-- Browse, filter and play every voiceover file in the loaded packs. Rendered
-- as the "Library" tab of the settings window.
--
-- Pack file names:
--   <questId>_<Desc|Prog|Comp>.ogg
--   <npcId>_QuestGreeting.ogg
--   <id>_<Gossip|GameObject|Item>_<hash>[_<Male|Female|Neutral>].ogg
-- ============================================================================

---@class VoiceoverLibrary
local Library = {}
CLN.VoiceoverLibrary = Library

-- Kind codes stored in the compact index.
local KIND = { Desc = 1, Prog = 2, Comp = 3, Gossip = 4, QuestGreeting = 5, GameObject = 6, Item = 7 }
local KIND_OTHER = 8
Library.KIND = KIND

local KIND_LABEL = {
    [1] = "Quest: Accept", [2] = "Quest: Progress", [3] = "Quest: Complete",
    [4] = "Gossip", [5] = "Greeting", [6] = "Object", [7] = "Item", [8] = "Other",
}
local PHASE_BY_KIND = { [1] = "Desc", [2] = "Prog", [3] = "Comp" }
local ENTRY_TYPE_BY_KIND = { [4] = "Gossip", [5] = "QuestGreeting", [6] = "GameObject", [7] = "Item" }

-- Type filter values -> kind codes they include.
local TYPE_FILTERS = {
    all    = nil,
    quest  = { [1] = true, [2] = true, [3] = true },
    gossip = { [4] = true },
    greeting = { [5] = true },
    object = { [6] = true },
    item   = { [7] = true },
}

-- Filter state (shared by the UI and Filter()).
Library.state = { query = "", type = "all", expansion = "all", locale = "all" }

-- ─────────────────────────────────────────────────────────────────────────────
-- Index
-- ─────────────────────────────────────────────────────────────────────────────

--- Parse a pack file name into kind code and numeric ID.
---@param fileName string
---@return number kind
---@return number|nil id
function Library:ParseFile(fileName)
    local id, kindName = fileName:match("^(%d+)_(%a+)")
    return KIND[kindName] or KIND_OTHER, tonumber(id)
end

--- Build (or reuse) the compact per-pack index: ordered pack list with
--- parallel `kinds` / `ids` number arrays. Rebuilt when packs are added.
---@return table[] packs  { name, locale, expansion, data, kinds, ids }
function Library:GetIndex()
    local count = 0
    for _ in pairs(CLN.VoiceoverPacks) do count = count + 1 end
    if self._index and self._indexPackCount == count then return self._index end

    local packs = {}
    for name, data in pairs(CLN.VoiceoverPacks) do
        local expansion, locale = CLN:ParseVoiceoverPackName(name)
        if expansion and type(data.Voiceovers) == "table" then
            local kinds, ids = {}, {}
            for i, fileName in ipairs(data.Voiceovers) do
                kinds[i], ids[i] = self:ParseFile(fileName)
            end
            packs[#packs + 1] = {
                name = name, locale = locale, expansion = expansion,
                data = data, kinds = kinds, ids = ids,
            }
        end
    end
    local order = CLN.VoiceoverExpansionOrder or {}
    table.sort(packs, function(a, b)
        local oa, ob = order[a.expansion] or 99, order[b.expansion] or 99
        if oa ~= ob then return oa < ob end
        if a.expansion ~= b.expansion then return a.expansion < b.expansion end
        -- English first, then other languages alphabetically.
        local ea, eb = a.locale == CLN.DEFAULT_VOICEOVER_LOCALE, b.locale == CLN.DEFAULT_VOICEOVER_LOCALE
        if ea ~= eb then return ea end
        return a.locale < b.locale
    end)
    self._index = packs
    self._indexPackCount = count
    return packs
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Names
-- ─────────────────────────────────────────────────────────────────────────────

Library._titles = {}        -- questId -> title | false (requested, unknown)
Library._requested = {}     -- questId -> true once a server load was requested

--- Quest title from the client cache (no server request; see RequestTitles).
---@param questId number
---@return string|nil
function Library:GetQuestTitle(questId)
    local cached = self._titles[questId]
    if cached then return cached end
    local title
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        title = C_QuestLog.GetTitleForQuestID(questId)
    end
    if (not title or title == "") and QuestUtils_GetQuestName then
        title = QuestUtils_GetQuestName(questId)
    end
    if title and title ~= "" then
        self._titles[questId] = title
        return title
    end
    return nil
end

--- Ask the server for quest titles the client hasn't cached yet. Called once
--- scrolling settles, for visible rows only (QUEST_DATA_LOAD_RESULT redraws).
---@param questIds number[]
function Library:RequestTitles(questIds)
    if not (C_QuestLog and C_QuestLog.RequestLoadQuestByID) then return end
    for _, questId in ipairs(questIds) do
        if not self._requested[questId] then
            self._requested[questId] = true
            C_QuestLog.RequestLoadQuestByID(questId)
        end
    end
end

--- Fill the title cache once from the client's quest cache so text search
--- finds every quest the game already knows, not just rows drawn so far.
function Library:PrefillTitles()
    if self._titlesPrefilled then return end
    self._titlesPrefilled = true
    for _, pack in ipairs(self:GetIndex()) do
        local kinds, ids = pack.kinds, pack.ids
        for i = 1, #kinds do
            local id = ids[i]
            if kinds[i] <= 3 and id and self._titles[id] == nil then
                self:GetQuestTitle(id)
            end
        end
    end
end

--- NPC name from collected NPC data or the metadata cache.
---@param npcId number
---@return string|nil
function Library:GetNpcName(npcId)
    local info = type(NpcInfoDB) == "table" and NpcInfoDB[npcId]
    if info then
        local own = info[CLN.locale or "enUS"]
        if own and own.name and own.name ~= "" then return own.name end
        for _, byLocale in pairs(info) do
            if type(byLocale) == "table" and byLocale.name and byLocale.name ~= "" then return byLocale.name end
        end
    end
    local cached = CLN.NpcMetadataCache and CLN.NpcMetadataCache.Lookup and CLN.NpcMetadataCache:Lookup(npcId)
    if cached and cached.name and cached.name ~= "" then return cached.name end
    return nil
end

--- Display name for an index entry, with a readable fallback.
---@param kind number
---@param id number|nil
---@return string name
---@return boolean known  false when only the fallback is available
function Library:GetEntryName(kind, id)
    if not id then return "?", false end
    local name
    if kind <= 3 then
        name = self:GetQuestTitle(id)
        return name or ("Quest " .. id), name ~= nil
    elseif kind == 7 then
        if C_Item and C_Item.GetItemNameByID then
            name = C_Item.GetItemNameByID(id)
        elseif GetItemInfo then
            name = GetItemInfo(id)
        end
        return name or ("Item " .. id), name ~= nil
    elseif kind == 6 then
        return "Object " .. id, false
    end
    name = self:GetNpcName(id)
    return name or ("NPC " .. id), name ~= nil
end

--- Sets of quest / NPC IDs whose known name contains `query` (lowercase).
local function idsMatchingName(self, query)
    local quests, npcs = {}, {}
    for questId, title in pairs(self._titles) do
        if title and title:lower():find(query, 1, true) then quests[questId] = true end
    end
    if type(NpcInfoDB) == "table" then
        for npcId, info in pairs(NpcInfoDB) do
            if type(info) == "table" then
                for _, byLocale in pairs(info) do
                    if type(byLocale) == "table" and type(byLocale.name) == "string"
                        and byLocale.name:lower():find(query, 1, true) then
                        npcs[npcId] = true
                        break
                    end
                end
            end
        end
    end
    local meta = CLN.NpcMetadataCache and CLN.NpcMetadataCache.db
    if type(meta) == "table" then
        for npcId, entry in pairs(meta) do
            if type(entry) == "table" and type(entry.name) == "string" and entry.name:lower():find(query, 1, true) then
                npcs[tonumber(npcId) or npcId] = true
            end
        end
    end
    return quests, npcs
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Filtering
-- ─────────────────────────────────────────────────────────────────────────────

--- Apply a filter state to the index.
--- A numeric query matches IDs starting with it; text matches known quest
--- titles and NPC names.
---@param state table { query, type, expansion, locale }
---@return number[] packIdx  index into GetIndex()
---@return number[] fileIdx  index into that pack's Voiceovers
function Library:Filter(state)
    local packs = self:GetIndex()
    local typeSet = TYPE_FILTERS[state.type or "all"]
    local query = (state.query or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    local numeric = query ~= "" and query:match("^%d+$") ~= nil
    local questSet, npcSet
    if query ~= "" and not numeric then
        self:PrefillTitles()
        questSet, npcSet = idsMatchingName(self, query)
    end

    local packIdx, fileIdx = {}, {}
    local n = 0
    for p, pack in ipairs(packs) do
        if (state.expansion == "all" or state.expansion == pack.expansion)
            and (state.locale == "all" or state.locale == pack.locale) then
            local files, kinds, ids = pack.data.Voiceovers, pack.kinds, pack.ids
            for i = 1, #kinds do
                local kind = kinds[i]
                if not typeSet or typeSet[kind] then
                    local ok = true
                    if numeric then
                        ok = files[i]:sub(1, #query) == query
                    elseif questSet then
                        local id = ids[i]
                        if kind <= 3 then ok = questSet[id] == true
                        elseif kind == 6 or kind == 7 then ok = false
                        else ok = npcSet[id] == true end
                    end
                    if ok then
                        n = n + 1
                        packIdx[n], fileIdx[n] = p, i
                    end
                end
            end
        end
    end
    return packIdx, fileIdx
end

--- Everything needed to play or show one result.
---@param pack table  entry from GetIndex()
---@param i number    file index in the pack
---@return table
function Library:GetEntry(pack, i)
    local fileName = pack.data.Voiceovers[i]
    local kind, id = pack.kinds[i], pack.ids[i]
    local name, nameKnown = self:GetEntryName(kind, id)
    local durations = pack.data.VoiceoverDurations
    return {
        fileName = fileName,
        path = "Interface\\AddOns\\" .. pack.name .. "\\voiceovers\\" .. fileName,
        pack = pack,
        kind = kind,
        id = id,
        name = name,
        nameKnown = nameKnown,
        phase = PHASE_BY_KIND[kind],
        entryType = ENTRY_TYPE_BY_KIND[kind],
        gender = fileName:match("_%x+_(%a+)%.ogg$"),
        duration = durations and durations[fileName],
    }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- UI
-- ─────────────────────────────────────────────────────────────────────────────

local ROW_H = 20
local SCROLLBAR_W = 24
local LIST_TOP = -100   -- first row; column headers sit in the 14px above it

local function formatDuration(sec)
    if not sec then return "" end
    sec = math.floor(sec + 0.5)
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function formatCount(n)
    local s = tostring(n)
    while true do
        local r, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        s = r
        if k == 0 then return s end
    end
end

--- Re-run the filter and redraw.
function Library:Refresh()
    if not self._ui then return end
    self._packIdx, self._fileIdx = self:Filter(self.state)
    local total = #self._packIdx
    local ui = self._ui
    if next(CLN.VoiceoverPacks) == nil then
        ui.count:SetText("No voiceover packs are loaded. Install packs and /reload.")
    else
        ui.count:SetText(formatCount(total) .. (total == 1 and " voiceover" or " voiceovers"))
    end
    local q = self.state.query or ""
    ui.hint:SetShown(q ~= "" and not q:match("^%s*%d+%s*$") and total == 0)
    FauxScrollFrame_SetOffset(ui.scroll, 0)
    ui.scroll:SetVerticalScroll(0)
    self:UpdateRows()
end

--- Redraw visible rows only (cheap; called on scroll and when names load).
function Library:UpdateRows()
    local ui = self._ui
    if not ui then return end
    local packs = self:GetIndex()
    local total = self._packIdx and #self._packIdx or 0
    FauxScrollFrame_Update(ui.scroll, total, #ui.rows, ROW_H)
    local offset = FauxScrollFrame_GetOffset(ui.scroll)
    local cp = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    local playingPath = cp and cp._libraryPath
    local missingTitles = {}
    for r, row in ipairs(ui.rows) do
        local n = offset + r
        if n <= total then
            local entry = self:GetEntry(packs[self._packIdx[n]], self._fileIdx[n])
            if entry.phase and not entry.nameKnown then missingTitles[#missingTitles + 1] = entry.id end
            row.entry = entry
            row.kind:SetText(KIND_LABEL[entry.kind])
            row.id:SetText(entry.id or "")
            local label = entry.name
            if entry.gender and entry.kind == 4 then label = label .. "  |cff888888(" .. entry.gender .. ")|r" end
            row.name:SetText(label)
            local packLabel = entry.pack.expansion:gsub("_", " ")
            if entry.pack.locale ~= CLN.DEFAULT_VOICEOVER_LOCALE then
                packLabel = packLabel .. " |cff66ccff" .. entry.pack.locale .. "|r"
            end
            row.pack:SetText(packLabel)
            row.dur:SetText(formatDuration(entry.duration))
            row.playing:SetShown(playingPath ~= nil and playingPath == entry.path)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end

    -- Request unknown titles only once scrolling settles, so dragging through
    -- thousands of rows doesn't flood the server.
    if #missingTitles > 0 and C_Timer and C_Timer.After then
        self._requestGen = (self._requestGen or 0) + 1
        local gen = self._requestGen
        C_Timer.After(0.4, function()
            if gen == self._requestGen then self:RequestTitles(missingTitles) end
        end)
    end
end

--- Coalesce refreshes triggered by async name loads.
function Library:QueueRowUpdate()
    if self._rowUpdatePending or not (C_Timer and C_Timer.After) then return end
    self._rowUpdatePending = true
    C_Timer.After(0.2, function()
        self._rowUpdatePending = false
        if self._ui and self._ui.frame:IsVisible() then self:UpdateRows() end
    end)
end

local function createDropdown(parent, label, width, values, sorting, key, x)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -8)
    fs:SetText(label)
    local dd = CLN.Widgets.CreateDropdown(parent, width, {
        values = values,
        sorting = sorting,
        get = function() return Library.state[key] end,
        set = function(value)
            Library.state[key] = value
            Library:Refresh()
        end,
    })
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -22)
    dd:Refresh()
    return dd
end

local function createRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, LIST_TOP - (i - 1) * ROW_H)
    row:SetPoint("RIGHT", parent, "RIGHT", -SCROLLBAR_W, 0)
    row:RegisterForClicks("LeftButtonUp")

    if i % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, 0.03)
    end
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.12)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 4, 0)
    icon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    icon:SetTexCoord(0.2, 0.8, 0.2, 0.8)

    -- Shown on the row whose file is playing now.
    local playing = row:CreateTexture(nil, "BORDER")
    playing:SetAllPoints()
    playing:SetColorTexture(0.2, 0.8, 0.2, 0.15)
    playing:Hide()
    row.playing = playing

    local function col(x, w, justify, font)
        local fs = row:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
        fs:SetPoint("LEFT", row, "LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetJustifyH(justify or "LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    row.kind = col(22, 92)
    row.id   = col(116, 56, "LEFT", "GameFontDisableSmall")
    row.name = col(176, 236)
    row.pack = col(416, 128, "LEFT", "GameFontDisableSmall")
    row.dur  = col(548, 40, "RIGHT", "GameFontDisableSmall")

    row:SetScript("OnClick", function(self)
        if self.entry and CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.PlayLibraryFile then
            CLN.VoiceoverPlayer:PlayLibraryFile(self.entry)
            Library:UpdateRows()
        end
    end)
    row:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.entry.name, 1, 1, 1)
        GameTooltip:AddLine(KIND_LABEL[self.entry.kind] .. "  ·  ID " .. tostring(self.entry.id), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(self.entry.fileName, 0.6, 0.6, 0.6)
        GameTooltip:AddLine(CLN:GetVoiceoverLocaleName(self.entry.pack.locale) .. "  ·  " .. self.entry.pack.name, 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Click to play", 0.4, 1, 0.4)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

--- Build the library UI into a settings-window tab frame.
---@param parent Frame
function Library:Build(parent)
    if self._ui then return end
    local ui = { frame = parent, rows = {} }
    self._ui = ui

    -- Search box
    local searchLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -8)
    searchLabel:SetText("Search")
    local search = CLN.Widgets.CreateEditBox(parent, 156, 24)
    search:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -22)
    local searchGen = 0
    search:SetScript("OnTextChanged", function(selfBox, userInput)
        if not userInput then return end
        Library.state.query = selfBox:GetText() or ""
        searchGen = searchGen + 1
        local gen = searchGen
        C_Timer.After(0.25, function()
            if gen == searchGen then Library:Refresh() end
        end)
    end)
    search:HookScript("OnEnter", function(selfBox)
        GameTooltip:SetOwner(selfBox, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Search", 1, 1, 1)
        GameTooltip:AddLine("Type a quest, NPC or item ID, or part of a quest title or NPC name.", nil, nil, nil, true)
        GameTooltip:AddLine("Names are only known for quests and NPCs your game has already seen.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    search:HookScript("OnLeave", function() GameTooltip:Hide() end)
    ui.search = search

    -- Filters
    createDropdown(parent, "Type", 110, {
        all = "All types", quest = "Quests", gossip = "Gossip", greeting = "Greetings", object = "Objects", item = "Items",
    }, { "all", "quest", "gossip", "greeting", "object", "item" }, "type", 176)

    local expansionValues, expansionSort = { all = "All expansions" }, { "all" }
    local localeValues, localeSort = { all = "All languages" }, { "all" }
    for _, pack in ipairs(self:GetIndex()) do
        if not expansionValues[pack.expansion] then
            expansionValues[pack.expansion] = pack.expansion:gsub("_", " ")
            expansionSort[#expansionSort + 1] = pack.expansion
        end
        if not localeValues[pack.locale] then
            localeValues[pack.locale] = CLN:GetVoiceoverLocaleName(pack.locale)
            localeSort[#localeSort + 1] = pack.locale
        end
    end
    createDropdown(parent, "Expansion", 150, expansionValues, expansionSort, "expansion", 298)
    createDropdown(parent, "Language", 130, localeValues, localeSort, "locale", 460)

    -- Count + stop
    local count = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    count:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -60)
    ui.count = count

    local stop = CLN.Widgets.CreateButton(parent, "Stop", 80, 22)
    stop:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -SCROLLBAR_W, -56)
    stop:SetScript("OnClick", function()
        if CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.ForceStopCurrentSound then
            CLN.VoiceoverPlayer:ForceStopCurrentSound(false, true)
        end
        Library:UpdateRows()
    end)

    -- Column headers
    local function header(text, x, w, justify)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", x, LIST_TOP + 2)
        fs:SetWidth(w)
        fs:SetJustifyH(justify or "LEFT")
        fs:SetText(text)
    end
    header("Type", 22, 92); header("ID", 116, 56); header("Name", 176, 236)
    header("Pack", 416, 128); header("Length", 548, 40, "RIGHT")

    -- Virtual list
    local scroll = CreateFrame("ScrollFrame", "CLNVoiceoverLibraryScroll", parent, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, LIST_TOP)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -SCROLLBAR_W, 0)
    scroll:SetScript("OnVerticalScroll", function(selfScroll, offset)
        FauxScrollFrame_OnVerticalScroll(selfScroll, offset, ROW_H, function() Library:UpdateRows() end)
    end)
    ui.scroll = scroll

    local parentH = parent:GetHeight() or 0
    if parentH < 100 then parentH = 444 end   -- not laid out yet; settings tab height
    local listH = parentH + LIST_TOP
    local visible = math.max(5, math.floor(listH / ROW_H))
    for i = 1, visible do ui.rows[i] = createRow(parent, i) end

    -- Shown when a text search finds nothing (names may simply be unknown yet).
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    hint:SetPoint("TOP", parent, "TOP", -SCROLLBAR_W / 2, LIST_TOP - 30)
    hint:SetWidth(420)
    hint:SetText("No matches. Names are only known for quests and NPCs your game has already seen; try searching by ID.")
    hint:Hide()
    ui.hint = hint

    -- Quest titles arrive asynchronously after RequestLoadQuestByID.
    if C_QuestLog and C_QuestLog.RequestLoadQuestByID then
        local events = CreateFrame("Frame", nil, parent)
        events:RegisterEvent("QUEST_DATA_LOAD_RESULT")
        events:SetScript("OnEvent", function(_, _, questId, ok)
            if ok and Library._requested[questId] then Library:QueueRowUpdate() end
        end)
    end

    -- Keep the "playing" highlight in step with playback started or ended elsewhere.
    if CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.NotifyDisplayDirty and hooksecurefunc then
        hooksecurefunc(CLN.VoiceoverPlayer, "NotifyDisplayDirty", function()
            if parent:IsVisible() then Library:QueueRowUpdate() end
        end)
    end

    -- Redraw (not re-filter) on show so switching tabs keeps the scroll position.
    parent:HookScript("OnShow", function() Library:UpdateRows() end)
    self:Refresh()
end

SLASH_CLNLIBRARY1 = "/clnlibrary"
SlashCmdList["CLNLIBRARY"] = function()
    if CLN.SettingsWindow and CLN.SettingsWindow.OpenTab then CLN.SettingsWindow:OpenTab("library") end
end
