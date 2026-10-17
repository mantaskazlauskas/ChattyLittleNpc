---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

-- ============================================================================
-- Voiceover pack discovery and language selection.
--
-- Pack addon folder naming:
--   ChattyLittleNpc_<Expansion>_voiceovers           -> English (enUS, legacy)
--   ChattyLittleNpc_<Expansion>_<locale>_voiceovers  -> that locale, e.g. deDE
--
-- CLN.VoiceoverPacks holds every loaded pack (any language). Playback code
-- must walk packs through CLN:IterateVoiceoverPacks(), which yields only the
-- packs for the selected language, followed by English when fallback is on.
-- ============================================================================

CLN.DEFAULT_VOICEOVER_LOCALE = "enUS"

-- WoW client locale codes a pack suffix may use, with display names.
CLN.VoiceoverLocales = {
    enUS = "English",
    deDE = "German",
    frFR = "French",
    esES = "Spanish (EU)",
    esMX = "Spanish (Latin America)",
    ptBR = "Portuguese",
    itIT = "Italian",
    ruRU = "Russian",
    koKR = "Korean",
    zhCN = "Chinese (Simplified)",
    zhTW = "Chinese (Traditional)",
}

-- Release order, so the pack list reads chronologically. Unknown expansions sort last.
local EXPANSION_ORDER = {
    Vanilla = 1, The_Burning_Crusade = 2, Wrath_of_the_Lich_King = 3, Cataclysm = 4,
    Mists_of_Pandaria = 5, Warlords_of_Draenor = 6, Legion = 7, Battle_for_Azeroth = 8,
    Shadowlands = 9, Dragonflight = 10, The_War_Within = 11, Midnight = 12,
}
CLN.VoiceoverExpansionOrder = EXPANSION_ORDER

--- Display name for a locale code, e.g. "German (deDE)".
---@param locale string
---@return string
function CLN:GetVoiceoverLocaleName(locale)
    local name = self.VoiceoverLocales[locale]
    return name and (name .. " (" .. locale .. ")") or tostring(locale)
end

--- Split a pack addon name into expansion and locale.
---@param addonName string
---@return string|nil expansion  e.g. "Battle_for_Azeroth"; nil when not a voiceover pack
---@return string|nil locale     e.g. "deDE"; "enUS" for packs without a suffix
function CLN:ParseVoiceoverPackName(addonName)
    if type(addonName) ~= "string" then return nil, nil end
    local middle = addonName:match("^ChattyLittleNpc_(.+)_voiceovers$")
    if not middle then return nil, nil end
    local expansion, suffix = middle:match("^(.+)_(%a%a%a%a)$")
    if expansion and self.VoiceoverLocales[suffix] then
        return expansion, suffix
    end
    return middle, self.DEFAULT_VOICEOVER_LOCALE
end

--- Add a loaded pack to CLN.VoiceoverPacks and build its filename index.
---@param addonName string
---@return boolean registered
function CLN:RegisterVoiceoverPack(addonName)
    local addon = _G[addonName]
    if not addon or not self:ParseVoiceoverPackName(addonName) then return false end
    self.VoiceoverPacks[addonName] = addon
    if addon.Voiceovers and not addon._voiceoverIndex then
        addon._voiceoverIndex = {}
        for _, name in ipairs(addon.Voiceovers) do
            addon._voiceoverIndex[name] = true
        end
    end
    self._activePacksKey = nil
    return true
end

--- Every voiceover pack in the client's AddOns folder, loaded or not.
---@return table[] packs  { name, title, expansion, locale, loaded, loadable, reason, version, fileCount }
function CLN:GetInstalledVoiceoverPacks()
    local packs = {}
    for i = 1, C_AddOns.GetNumAddOns() do
        local name, title, _, loadable, reason = C_AddOns.GetAddOnInfo(i)
        local expansion, locale = self:ParseVoiceoverPackName(name)
        if expansion then
            local data = self.VoiceoverPacks[name]
            packs[#packs + 1] = {
                name      = name,
                title     = title,
                expansion = expansion,
                locale    = locale,
                loaded    = C_AddOns.IsAddOnLoaded(name) and true or false,
                loadable  = loadable,
                reason    = reason,
                version   = C_AddOns.GetAddOnMetadata(name, "Version"),
                fileCount = data and data.Voiceovers and #data.Voiceovers or nil,
            }
        end
    end
    table.sort(packs, function(a, b)
        if a.locale ~= b.locale then return a.locale < b.locale end
        local oa, ob = EXPANSION_ORDER[a.expansion] or 99, EXPANSION_ORDER[b.expansion] or 99
        if oa ~= ob then return oa < ob end
        return a.expansion < b.expansion
    end)
    return packs
end

--- Set of locales that have at least one loaded pack.
---@return table<string, boolean>
function CLN:GetLoadedVoiceoverLocales()
    local locales = {}
    for name in pairs(self.VoiceoverPacks) do
        local _, locale = self:ParseVoiceoverPackName(name)
        if locale then locales[locale] = true end
    end
    return locales
end

--- The game client's locale, mapped to a pack locale (enGB clients use enUS packs).
---@return string
function CLN:GetClientVoiceoverLocale()
    local locale = GetLocale()
    if locale == "enGB" then return "enUS" end
    return locale
end

--- The language voiceovers are played in, with "auto" resolved.
---@return string locale
function CLN:GetVoiceoverLanguage()
    local setting = self.db and self.db.profile and self.db.profile.voiceoverLanguage or "auto"
    if setting ~= "auto" then return setting end
    local client = self:GetClientVoiceoverLocale()
    if self:GetLoadedVoiceoverLocales()[client] then return client end
    return self.DEFAULT_VOICEOVER_LOCALE
end

--- Rebuild the ordered list of packs used for playback lookups.
local function rebuildActivePacks(self, language, fallback)
    local primary, secondary = {}, {}
    for name, data in pairs(self.VoiceoverPacks) do
        local _, locale = self:ParseVoiceoverPackName(name)
        if locale == language then
            primary[#primary + 1] = { name = name, data = data }
        elseif fallback and locale == self.DEFAULT_VOICEOVER_LOCALE then
            secondary[#secondary + 1] = { name = name, data = data }
        end
    end
    -- Sort by name so lookups are deterministic across sessions.
    local byName = function(a, b) return a.name < b.name end
    table.sort(primary, byName)
    table.sort(secondary, byName)
    for _, entry in ipairs(secondary) do primary[#primary + 1] = entry end
    self._activePacks = primary
end

--- Iterate (packName, packData) over the packs for the selected language,
--- then English packs when fallback is enabled.
function CLN:IterateVoiceoverPacks()
    local language = self:GetVoiceoverLanguage()
    local fallback = language ~= self.DEFAULT_VOICEOVER_LOCALE
        and not (self.db and self.db.profile and self.db.profile.voiceoverLanguageFallback == false)
    local key = language .. (fallback and "+fallback" or "")
    if self._activePacksKey ~= key or not self._activePacks then
        rebuildActivePacks(self, language, fallback)
        self._activePacksKey = key
    end
    local list, i = self._activePacks, 0
    return function()
        i = i + 1
        local entry = list[i]
        if entry then return entry.name, entry.data end
    end
end

--- Register every voiceover pack that is already loaded.
function CLN:GetLoadedExpansionVoiceoverPacks()
    for _, pack in ipairs(self:GetInstalledVoiceoverPacks()) do
        if pack.loaded and self:RegisterVoiceoverPack(pack.name) and self.db.profile.debugMode and self.Logger then
            local C = self.Utils and self.Utils.LogCategories or { loader = 'loader' }
            self.Logger:debug("Loaded voiceover pack: " .. tostring(pack.name), false, C.loader or 'misc')
        end
    end

    if (self.db.profile.debugMode and self.Logger) then self:PrintLoadedVoiceoverPacks() end
end

function CLN:PrintLoadedVoiceoverPacks()
    for packName, packData in pairs(self.VoiceoverPacks) do
        if packData.Metadata then
            if self.Logger then self.Logger:info("Metadata for " .. tostring(packName), false, (self.Utils and self.Utils.LogCategories.loader) or 'misc') end
            self.Utils:PrintTable(packData.Metadata)
        end
        if packData.Voiceovers then
            if self.Logger then self.Logger:info("VO count for " .. tostring(packName) .. ": " .. tostring(#packData.Voiceovers), false, (self.Utils and self.Utils.LogCategories.loader) or 'misc') end
        end
    end
end

-- Diagnostic function to check voiceover pack status
function CLN:CheckVoiceoverPacks()
    if not self.Logger then return end
    self.Logger:info("Checking for voiceover packs...")
    local foundCount = 0
    for _, pack in ipairs(self:GetInstalledVoiceoverPacks()) do
        if pack.loaded then
            foundCount = foundCount + 1
            self.Logger:info("|cff00ff00Loaded|r " .. pack.name .. " - " .. tostring(pack.fileCount or 0) .. " voiceovers")
        else
            self.Logger:info("|cffff0000Not loaded|r " .. pack.name)
        end
    end
    if foundCount == 0 then
        self.Logger:warn("No voiceover packs found!")
        self.Logger:info("You need to install voiceover pack addons separately.")
    else
        self.Logger:info("|cff00ff00Found " .. foundCount .. " voiceover pack(s)|r")
    end
end

--- Multi-line, colour-coded list of installed packs grouped by language.
---@return string
function CLN:GetVoiceoverPackListText()
    local packs = self:GetInstalledVoiceoverPacks()
    if #packs == 0 then
        return "No voiceover packs found in your AddOns folder. Install packs separately, e.g. from CurseForge."
    end
    local active = self:GetVoiceoverLanguage()
    local fallback = active ~= self.DEFAULT_VOICEOVER_LOCALE and self.db.profile.voiceoverLanguageFallback ~= false
    local lines, currentLocale = {}, nil
    for _, pack in ipairs(packs) do
        if pack.locale ~= currentLocale then
            currentLocale = pack.locale
            if #lines > 0 then lines[#lines + 1] = " " end
            lines[#lines + 1] = "|cffffd100" .. self:GetVoiceoverLocaleName(pack.locale) .. "|r"
        end
        local status
        if not pack.loaded then
            local reasonText = pack.reason and _G["ADDON_" .. pack.reason] or pack.reason or "Not loaded"
            status = "|cff808080" .. reasonText .. "|r"
        elseif pack.locale == active then
            status = "|cff00ff00In use|r"
        elseif fallback and pack.locale == self.DEFAULT_VOICEOVER_LOCALE then
            status = "|cff66ccffFallback|r"
        else
            status = "|cffaaaaaaLoaded, not used|r"
        end
        local details = {}
        if pack.fileCount then details[#details + 1] = pack.fileCount .. " files" end
        if pack.version then details[#details + 1] = "v" .. pack.version end
        local detailText = #details > 0 and ("  |cff999999(" .. table.concat(details, ", ") .. ")|r") or ""
        lines[#lines + 1] = "    " .. pack.expansion:gsub("_", " ") .. "  -  " .. status .. detailText
    end
    return table.concat(lines, "\n")
end
