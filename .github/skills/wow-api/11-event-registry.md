# EventRegistry Callback System

> Modern alternative to frame:RegisterEvent() for handling events.
> Source: SharedXML/GlobalCallbackRegistry.lua
> Full reference: https://warcraft.wiki.gg/wiki/EventRegistry

## Overview

EventRegistry is a FrameXML utility for callback-based event handling. It works with both WoW frame events (PLAYER_LOGIN, etc.) and custom Blizzard callback events (MountJournal.OnShow, etc.).

**Advantages over frame:RegisterEvent():**
- No need to create a frame just for events
- Clean callback registration/unregistration by owner
- Works with Blizzard's custom callback events
- Shown in Event Trace panel (/etrace)

**Caveat**: If a callback takes too long (script timeout), other callbacks for the same event may not execute.

## Frame Event Registration

```lua
-- Register for a standard WoW event (no frame needed!)
EventRegistry:RegisterFrameEventAndCallback("PLAYER_ENTERING_WORLD", function(ownerID, ...)
    local isInitialLogin, isReloadingUi = ...
    print("Entering world:", isInitialLogin, isReloadingUi)
end)

-- With extra static arguments
EventRegistry:RegisterFrameEventAndCallback("PLAYER_ENTERING_WORLD", function(ownerID, ...)
    print("Extra args:", ...)
end, nil, "extraArg1", "extraArg2")
-- Output: "Extra args: extraArg1, extraArg2, true, false"

-- Unregister
local owner = EventRegistry:RegisterFrameEventAndCallback("CHAT_MSG_SAY", myHandler)
-- Later:
EventRegistry:UnregisterFrameEventAndCallback("CHAT_MSG_SAY", owner)
```

## Custom Callback Events

```lua
-- Register for Blizzard callback events
EventRegistry:RegisterCallback("MountJournal.OnShow", function(ownerID)
    print("Mount journal opened!")
end)

EventRegistry:RegisterCallback("CollectionsJournal.TabSet", function(ownerID, journal, tabID)
    print("Switched to tab:", tabID)
end)
```

## Owner-Based Registration

Callbacks are unregistered by their owner handle. The owner can be:
- A table
- A function
- A string
- Auto-assigned (internal number) if omitted

```lua
-- Explicit owner (a table)
local myAddon = {}
EventRegistry:RegisterCallback("SomeEvent", handler, myAddon)
EventRegistry:UnregisterCallback("SomeEvent", myAddon)

-- Explicit owner (a string)
EventRegistry:RegisterCallback("SomeEvent", handler, "MyAddon_SomeHandler")
EventRegistry:UnregisterCallback("SomeEvent", "MyAddon_SomeHandler")

-- Auto-assigned owner (returned)
local owner = EventRegistry:RegisterCallback("SomeEvent", handler)
EventRegistry:UnregisterCallback("SomeEvent", owner)
```

## Triggering Custom Events

```lua
-- Fire a custom event
EventRegistry:TriggerEvent("MyAddon.SomethingHappened", arg1, arg2)

-- Register handlers
EventRegistry:RegisterCallback("MyAddon.SomethingHappened", function(ownerID, a1, a2)
    print("Received:", a1, a2)
end)
```

## Multiple Callbacks

```lua
local function onShow(ownerID, ...)
    print("Handler A")
end

local function onShowB(ownerID, ...)
    print("Handler B")
end

-- Both fire when event triggers
EventRegistry:RegisterCallback("MyEvent", onShow)
EventRegistry:RegisterCallback("MyEvent", onShowB)

EventRegistry:TriggerEvent("MyEvent")
-- Output: "Handler A" then "Handler B"
```

## Private CallbackRegistry

Create your own isolated callback registry:

```lua
local myRegistry = CreateFromMixins(CallbackRegistryMixin)
myRegistry:OnLoad()
myRegistry:SetUndefinedEventsAllowed(true)

-- Register
myRegistry:RegisterCallback("CustomEvent", function(ownerID, data)
    print("Received:", data)
end)

-- Trigger
myRegistry:TriggerEvent("CustomEvent", "hello world")
```

## CallbackRegistryMixin Methods

```lua
registry:RegisterCallback(event, func [, owner], ...)  : owner
registry:UnregisterCallback(event, owner)
registry:TriggerEvent(event, ...)
registry:SetUndefinedEventsAllowed(allowed)
registry:GenerateCallbackEvents(events)  -- Pre-define allowed events
```

## Common Blizzard Callback Events

These are triggered by Blizzard FrameXML code:

| Event | Fired When |
|-------|-----------|
| `MountJournal.OnShow` | Mount collection opens |
| `MountJournal.OnHide` | Mount collection closes |
| `CollectionsJournal.TabSet` | Collections tab switched |
| `EditMode.Enter` | Edit mode entered |
| `EditMode.Exit` | Edit mode exited |
| `ItemButton.OnEnter` | Mouse enters an item button |
| `ItemButton.OnLeave` | Mouse leaves an item button |
| `Settings.OpenToCategory` | Settings panel opens to category |

> Use `/etrace` to discover callback events as they fire in real-time.

## Comparison: Frame Events vs EventRegistry

```lua
-- Traditional approach (requires a frame)
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        print("Logged in!")
    end
end)

-- EventRegistry approach (no frame needed)
EventRegistry:RegisterFrameEventAndCallback("PLAYER_LOGIN", function(ownerID)
    print("Logged in!")
end)
```
