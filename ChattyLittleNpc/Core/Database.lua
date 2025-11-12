-- Database.lua - Saved variables system to replace AceDB-3.0
-- Provides profile management and change callbacks

---@class Database
local Database = {}
Database.__index = Database

-- Create a new database instance
---@param savedVarName string Name of the saved variable
---@param defaults table Default values
---@param defaultProfile boolean|nil Use default profile
---@return Database
function Database:New(savedVarName, defaults, defaultProfile)
    local instance = setmetatable({}, Database)
    
    instance.savedVarName = savedVarName
    instance.defaults = defaults or {}
    instance.callbacks = {} -- event_name = { callback1, callback2, ... }
    
    -- Initialize saved variable
    if not _G[savedVarName] then
        _G[savedVarName] = {}
    end
    instance.sv = _G[savedVarName]
    
    -- Initialize profiles
    if not instance.sv.profiles then
        instance.sv.profiles = {}
    end
    
    -- Set current profile
    if not instance.sv.currentProfile then
        instance.sv.currentProfile = defaultProfile and "Default" or (UnitName("player") .. " - " .. GetRealmName())
    end
    
    -- Initialize current profile data
    if not instance.sv.profiles[instance.sv.currentProfile] then
        instance.sv.profiles[instance.sv.currentProfile] = {}
    end
    
    -- Create profile accessor
    instance.profile = setmetatable({}, {
        __index = function(t, key)
            local profileData = instance.sv.profiles[instance.sv.currentProfile]
            if profileData[key] ~= nil then
                return profileData[key]
            end
            -- Return default value
            return instance.defaults.profile and instance.defaults.profile[key]
        end,
        __newindex = function(t, key, value)
            instance.sv.profiles[instance.sv.currentProfile][key] = value
        end
    })
    
    -- Apply defaults
    instance:ApplyDefaults()
    
    return instance
end

-- Apply default values to current profile
function Database:ApplyDefaults()
    if not self.defaults.profile then return end
    
    local profileData = self.sv.profiles[self.sv.currentProfile]
    for key, value in pairs(self.defaults.profile) do
        if profileData[key] == nil then
            if type(value) == "table" then
                profileData[key] = self:DeepCopy(value)
            else
                profileData[key] = value
            end
        end
    end
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
