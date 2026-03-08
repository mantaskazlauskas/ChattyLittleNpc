# Widget Script Handlers (Patch 12.0.1)

> Script handlers respond to user interaction and widget lifecycle events.
> Full reference: https://warcraft.wiki.gg/wiki/Widget_script_handlers

## Setting Script Handlers

```lua
-- Set a handler
frame:SetScript("OnEvent", function(self, event, ...)
    -- handle event
end)

-- Post-hook a handler (doesn't replace existing)
frame:HookScript("OnShow", function(self)
    -- runs AFTER existing OnShow
end)

-- Remove a handler
frame:SetScript("OnEvent", nil)

-- Check if handler exists
if frame:HasScript("OnClick") then ... end
```

## ScriptRegion Scripts (All visible widgets)

| Script | Signature | Description |
|--------|-----------|-------------|
| `OnLoad` | (self) | Widget created (from XML template) |
| `OnShow` | (self) | Widget shown |
| `OnHide` | (self) | Widget hidden |
| `OnEnter` | (self, motion) | Cursor enters widget area |
| `OnLeave` | (self, motion) | Cursor leaves widget area |
| `OnMouseDown` | (self, button) | Mouse button pressed over widget |
| `OnMouseUp` | (self, button, upInside) | Mouse button released |
| `OnMouseWheel` | (self, delta) | Mouse wheel scrolled (+1/-1) |

## Frame Scripts

| Script | Signature | Description |
|--------|-----------|-------------|
| `OnEvent` | (self, event, ...) | Registered event fired |
| `OnUpdate` | (self, elapsed) | Every frame render (use sparingly!) |
| `OnSizeChanged` | (self, width, height) | Frame resized |
| `OnChar` | (self, text) | Text character typed |
| `OnKeyDown` | (self, key) | Keyboard key pressed |
| `OnKeyUp` | (self, key) | Keyboard key released |
| `OnDragStart` | (self, button) | Mouse drag started |
| `OnDragStop` | (self) | Mouse drag stopped |
| `OnReceiveDrag` | (self) | Drag released into frame |
| `OnAttributeChanged` | (self, key, value) | Secure attribute changed |
| `OnEnable` | (self) | Frame enabled |
| `OnDisable` | (self) | Frame disabled |
| `OnHyperlinkClick` | (self, link, text, button, ...) | Hyperlink clicked |
| `OnHyperlinkEnter` | (self, link, text, ...) | Hyperlink mouse enter |
| `OnHyperlinkLeave` | (self) | Hyperlink mouse leave |
| `OnGamePadButtonDown` | (self, button) | Gamepad button pressed |
| `OnGamePadButtonUp` | (self, button) | Gamepad button released |
| `OnGamePadStick` | (self, stick, x, y, len) | Gamepad stick moved |

## Button Scripts

| Script | Signature | Description |
|--------|-----------|-------------|
| `OnClick` | (self, button, down) | Button clicked |
| `OnDoubleClick` | (self, button) | Button double-clicked |
| `PreClick` | (self, button, down) | Before OnClick |
| `PostClick` | (self, button, down) | After OnClick |

## EditBox Scripts

| Script | Signature | Description |
|--------|-----------|-------------|
| `OnEnterPressed` | (self) | Enter pressed |
| `OnEscapePressed` | (self) | Escape pressed |
| `OnTabPressed` | (self) | Tab pressed |
| `OnSpacePressed` | (self) | Space pressed |
| `OnTextChanged` | (self, userInput) | Text value changed |
| `OnTextSet` | (self) | Text set programmatically |
| `OnCursorChanged` | (self, x, y, w, h) | Cursor position changed |
| `OnEditFocusGained` | (self) | Got focus |
| `OnEditFocusLost` | (self) | Lost focus |
| `OnCharComposition` | (self, text) | IME composition |
| `OnInputLanguageChanged` | (self, language) | Input language changed |

## Slider / StatusBar Scripts

| Script | Signature | Description |
|--------|-----------|-------------|
| `OnValueChanged` | (self, value [, userInput]) | Value changed |
| `OnMinMaxChanged` | (self, min, max) | Min/max changed |

## ScrollFrame Scripts

| Script | Signature | Description |
|--------|-----------|-------------|
| `OnVerticalScroll` | (self, offset) | Vertical scroll changed |
| `OnHorizontalScroll` | (self, offset) | Horizontal scroll changed |
| `OnScrollRangeChanged` | (self, xrange, yrange) | Scroll range changed |

## Model Scripts

| Script | Signature | Description |
|--------|-----------|-------------|
| `OnModelLoaded` | (self) | Model loaded |
| `OnAnimFinished` | (self) | Animation finished |
| `OnAnimStarted` | (self) | Animation started |

## Cooldown Scripts

| Script | Signature | Description |
|--------|-----------|-------------|
| `OnCooldownDone` | (self) | Cooldown finished |

## AnimationGroup Scripts

| Script | Signature | Description |
|--------|-----------|-------------|
| `OnPlay` | (self) | Animation started playing |
| `OnPause` | (self) | Animation paused |
| `OnStop` | (self, requested) | Animation stopped |
| `OnFinished` | (self, requested) | Animation finished |
| `OnLoop` | (self, loopState) | Animation loop state changed |
| `OnUpdate` | (self, elapsed) | Every frame while playing |

## GameTooltip Scripts

| Script | Signature | Description |
|--------|-----------|-------------|
| `OnTooltipCleared` | (self) | Tooltip hidden or cleared |
| `OnTooltipSetDefaultAnchor` | (self) | Tooltip repositioned to default |

## DressUpModel Scripts

| Script | Signature | Description |
|--------|-----------|-------------|
| `OnDressModel` | (self, itemModifiedAppearanceID, invSlot, removed) | Dressup model updated |

## MovieFrame Scripts

| Script | Signature | Description |
|--------|-----------|-------------|
| `OnMovieFinished` | (self) | Movie ended |

## Performance Note on OnUpdate

`OnUpdate` fires every frame (typically 60+ times per second). Avoid heavy work:

```lua
-- BAD: Heavy work every frame
frame:SetScript("OnUpdate", function(self, elapsed)
    DoExpensiveWork()
end)

-- GOOD: Throttle with elapsed time
local timer = 0
frame:SetScript("OnUpdate", function(self, elapsed)
    timer = timer + elapsed
    if timer >= 0.5 then  -- Every 0.5 seconds
        timer = 0
        DoExpensiveWork()
    end
end)

-- BETTER: Use C_Timer instead of OnUpdate when possible
C_Timer.NewTicker(0.5, function()
    DoExpensiveWork()
end)
```
