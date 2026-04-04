-- Events.lua - Event handling system
-- Provides RegisterEvent, UnregisterEvent, and a message bus for custom events (SendMessage/RegisterMessage)

---@class EventSystem
local EventSystem = {}
EventSystem.__index = EventSystem

-- Create a new event system instance
---@return EventSystem
function EventSystem:New()
    local instance = setmetatable({}, EventSystem)
    instance.frame = CreateFrame("Frame")
    instance.events = {} -- event_name = { callback1, callback2, ... }
    instance.messages = {} -- message_name = { callback1, callback2, ... }
    
    -- Main event dispatcher
    instance.frame:SetScript("OnEvent", function(frame, event, ...)
        instance:DispatchEvent(event, ...)
    end)
    
    return instance
end

-- Register a game event
---@param event string Event name
---@param callback function Callback function
function EventSystem:RegisterEvent(event, callback)
    if not self.events[event] then
        self.events[event] = {}
        local ok = pcall(self.frame.RegisterEvent, self.frame, event)
        if not ok then
            self.events[event] = nil
            return
        end
    end
    table.insert(self.events[event], callback)
end

-- Unregister a game event callback
---@param event string Event name
---@param callback function|nil Specific callback to remove, or nil to remove all
function EventSystem:UnregisterEvent(event, callback)
    if not self.events[event] then return end
    
    if callback then
        -- Remove specific callback
        for i, cb in ipairs(self.events[event]) do
            if cb == callback then
                table.remove(self.events[event], i)
                break
            end
        end
        -- If no more callbacks, unregister the event
        if #self.events[event] == 0 then
            self.frame:UnregisterEvent(event)
            self.events[event] = nil
        end
    else
        -- Remove all callbacks for this event
        self.frame:UnregisterEvent(event)
        self.events[event] = nil
    end
end

-- Dispatch an event to all registered callbacks
---@param event string Event name
---@param ... any Event arguments
function EventSystem:DispatchEvent(event, ...)
    local cbs = self.events[event]
    if not cbs then return end
    
    -- Fast path: single callback (common case) avoids snapshot allocation
    if #cbs == 1 then
        local ok, err = pcall(cbs[1], event, ...)
        if not ok and _G.ChattyLittleNpc and _G.ChattyLittleNpc.Logger then
            _G.ChattyLittleNpc.Logger:error("Event callback error [" .. tostring(event) .. "]: " .. tostring(err))
        end
        return
    end
    
    -- Snapshot the callback list so unregisters during dispatch don't skip entries
    local snapshot = {unpack(cbs)}
    for _, callback in ipairs(snapshot) do
        local ok, err = pcall(callback, event, ...)
        if not ok and _G.ChattyLittleNpc and _G.ChattyLittleNpc.Logger then
            _G.ChattyLittleNpc.Logger:error("Event callback error [" .. tostring(event) .. "]: " .. tostring(err))
        end
    end
end

-- Register a custom message (addon-internal communication)
---@param message string Message name
---@param callback function Callback function
function EventSystem:RegisterMessage(message, callback)
    if not self.messages[message] then
        self.messages[message] = {}
    end
    table.insert(self.messages[message], callback)
end

-- Unregister a custom message callback
---@param message string Message name
---@param callback function|nil Specific callback to remove, or nil to remove all
function EventSystem:UnregisterMessage(message, callback)
    if not self.messages[message] then return end
    
    if callback then
        for i, cb in ipairs(self.messages[message]) do
            if cb == callback then
                table.remove(self.messages[message], i)
                break
            end
        end
        if #self.messages[message] == 0 then
            self.messages[message] = nil
        end
    else
        self.messages[message] = nil
    end
end

-- Send a custom message to all registered callbacks
---@param message string Message name
---@param ... any Message arguments
function EventSystem:SendMessage(message, ...)
    local cbs = self.messages[message]
    if not cbs then return end
    
    -- Fast path: single callback (common case) avoids snapshot allocation
    if #cbs == 1 then
        local ok, err = pcall(cbs[1], message, ...)
        if not ok and _G.ChattyLittleNpc and _G.ChattyLittleNpc.Logger then
            _G.ChattyLittleNpc.Logger:error("Message callback error [" .. tostring(message) .. "]: " .. tostring(err))
        end
        return
    end
    
    -- Snapshot the callback list so unregisters during dispatch don't skip entries
    local snapshot = {unpack(cbs)}
    for _, callback in ipairs(snapshot) do
        local ok, err = pcall(callback, message, ...)
        if not ok and _G.ChattyLittleNpc and _G.ChattyLittleNpc.Logger then
            _G.ChattyLittleNpc.Logger:error("Message callback error [" .. tostring(message) .. "]: " .. tostring(err))
        end
    end
end

-- Export globally for the addon
_G.ChattyLittleNpc = _G.ChattyLittleNpc or {}
_G.ChattyLittleNpc.EventSystem = EventSystem

return EventSystem
