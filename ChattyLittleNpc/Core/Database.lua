-- Database.lua - Saved variables system
-- Provides profile management and change callbacks

---@class Database
local Database = {}
Database.__index = Database

-- Create a new database instance
---@param savedVarName string Name of the saved variable
---@param defaults table Default values
---@param defaultProfile boolean|nil Use default profile
---@return Database
function Database:New(savedVarName, defaults, defaultProfile, charSavedVarName)
    local instance = setmetatable({}, Database)
    
    instance.savedVarName = savedVarName
    instance.defaults = defaults or {}
    instance.callbacks = {} -- event_name = { callback1, callback2, ... }
    
    -- Initialize saved variable
    if not _G[savedVarName] then
        _G[savedVarName] = {}
    end
    instance.sv = _G[savedVarName]
    
    -- Initialize per-character saved variable (optional)
    -- Used to remember which profile each character last used.
    if charSavedVarName then
        if not _G[charSavedVarName] then
            _G[charSavedVarName] = {}
        end
        instance.charSv = _G[charSavedVarName]
    end

    -- Initialize profiles
    if not instance.sv.profiles then
        instance.sv.profiles = {}
    end
    
    -- Determine the profile to activate:
    --   1. Per-character preference (charSv.activeProfile) if the profile still exists
    --   2. Account-wide currentProfile (backward compat for existing saves)
    --   3. Default name
    local function resolveProfile()
        if instance.charSv and instance.charSv.activeProfile then
            if instance.sv.profiles[instance.charSv.activeProfile] then
                return instance.charSv.activeProfile
            end
        end
        if instance.sv.currentProfile then
            return instance.sv.currentProfile
        end
        return defaultProfile and "Default" or (UnitName("player") .. " - " .. GetRealmName())
    end

    local resolved = resolveProfile()
    instance.sv.currentProfile = resolved
    if instance.charSv then
        instance.charSv.activeProfile = resolved
    end

    -- Initialize current profile data
    if not instance.sv.profiles[instance.sv.currentProfile] then
        instance.sv.profiles[instance.sv.currentProfile] = {}
    end
    
    -- Create profile accessor
    instance.profile = setmetatable({}, {
        __index = function(t, key)
            local profiles = instance.sv and instance.sv.profiles
            local profileData = profiles and profiles[instance.sv.currentProfile]
            if type(profileData) ~= "table" then
                return instance.defaults.profile and instance.defaults.profile[key]
            end
            if profileData[key] ~= nil then
                return profileData[key]
            end
            -- Return default value
            return instance.defaults.profile and instance.defaults.profile[key]
        end,
        __newindex = function(t, key, value)
            local profiles = instance.sv and instance.sv.profiles
            if not profiles then return end
            if not profiles[instance.sv.currentProfile] then
                profiles[instance.sv.currentProfile] = {}
            end
            profiles[instance.sv.currentProfile][key] = value
        end
    })
    
    -- Apply defaults
    instance:ApplyDefaults()
    
    return instance
end

-- Recursively merge defaults into target, filling only missing keys
---@param target table
---@param defaults table
function Database:MergeDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = self:DeepCopy(value)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            self:MergeDefaults(target[key], value)
        end
    end
end

-- Apply default values to current profile
function Database:ApplyDefaults()
    if not self.defaults.profile then return end
    
    local profileData = self.sv.profiles[self.sv.currentProfile]
    self:MergeDefaults(profileData, self.defaults.profile)
end

-- Deep copy a table
---@param orig table Original table
---@return table
function Database:DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = self:DeepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

-- Register a callback for database events
---@param event string Event name ("OnProfileChanged", "OnProfileCopied", "OnProfileReset")
---@param callback function Callback function
function Database:RegisterCallback(event, callback)
    if not self.callbacks[event] then
        self.callbacks[event] = {}
    end
    table.insert(self.callbacks[event], callback)
end

-- Fire a callback event
---@param event string Event name
function Database:FireCallback(event)
    if not self.callbacks[event] then return end
    
    for _, callback in ipairs(self.callbacks[event]) do
        callback()
    end
end

-- Set the current profile
---@param profileName string Profile name
function Database:SetProfile(profileName)
    if not profileName or profileName == self.sv.currentProfile then return end
    
    -- Create profile if it doesn't exist
    if not self.sv.profiles[profileName] then
        self.sv.profiles[profileName] = {}
    end
    
    self.sv.currentProfile = profileName
    -- Remember this choice for the current character
    if self.charSv then
        self.charSv.activeProfile = profileName
    end
    self:ApplyDefaults()
    self:FireCallback("OnProfileChanged")
end

-- Copy another profile to the current profile
---@param sourceProfile string Source profile name
function Database:CopyProfile(sourceProfile)
    if not self.sv.profiles[sourceProfile] then return end
    
    local currentProfile = self.sv.currentProfile
    self.sv.profiles[currentProfile] = self:DeepCopy(self.sv.profiles[sourceProfile])
    self:FireCallback("OnProfileCopied")
end

-- Reset the current profile to defaults
function Database:ResetProfile()
    local currentProfile = self.sv.currentProfile
    self.sv.profiles[currentProfile] = {}
    self:ApplyDefaults()
    self:FireCallback("OnProfileReset")
end

-- Get a list of all profiles
---@return table
function Database:GetProfiles()
    local profiles = {}
    for name, _ in pairs(self.sv.profiles) do
        table.insert(profiles, name)
    end
    return profiles
end

-- Delete a profile
---@param profileName string Profile name to delete
function Database:DeleteProfile(profileName)
    if profileName == self.sv.currentProfile then
        -- Can't delete active profile
        return false
    end
    
    if self.sv.profiles[profileName] then
        self.sv.profiles[profileName] = nil
        return true
    end
    
    return false
end

-- Export globally for the addon
_G.ChattyLittleNpc = _G.ChattyLittleNpc or {}
_G.ChattyLittleNpc.Database = Database

return Database
