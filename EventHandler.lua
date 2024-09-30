---@class EventHandler
local EventHandler = LibStub("AceAddon-3.0"):NewAddon("EventHandler", "AceEvent-3.0")

local ChattyLittleNpc

-- Set the reference to ChattyLittleNpc
function EventHandler:SetChattyLittleNpcReference(reference)
    ChattyLittleNpc = reference
end

-- Initialize the EventHandler module
function EventHandler:OnInitialize()

end

-- Method to register a custom event
function EventHandler:RegisterCustomEvent(eventName, handler)
    -- Register a custom event with a specific handler
    self:RegisterMessage(eventName, handler)
end

-- Method to trigger a custom event
function EventHandler:TriggerCustomEvent(eventName, ...)
    -- Trigger the custom event with additional arguments
    self:SendMessage(eventName, ...)
end

-- Watcher function to monitor the sound handle
function EventHandler:StartWatcher()
    C_Timer.NewTicker(0.5, function()
        local currentlyPlaying = ChattyLittleNpc.Voiceovers.currentlyPlaying
        if currentlyPlaying and not currentlyPlaying.isPlaying then
            self:SendMessage("VOICEOVER_STOP", currentlyPlaying)
            return
        end

        if currentlyPlaying and currentlyPlaying.soundHandle and currentlyPlaying.isPlaying then
            if not C_Sound.IsPlaying(currentlyPlaying.soundHandle) then
                currentlyPlaying.isPlaying = false
                self:SendMessage("VOICEOVER_STOP", currentlyPlaying)
                return
            end
        end
    end)
end

-- Initialize the EventHandler module
EventHandler:OnInitialize()

-- Start the watcher
EventHandler:StartWatcher()