-- Self-managed voiceover hotkey.
-- The bound key is stored in db.profile.playVoiceoverKey (SavedVariables).
-- This intentionally does NOT register with WoW's Key Bindings UI.

local keyListener = CreateFrame("Frame")
keyListener:SetSize(1, 1)
keyListener:SetPoint("CENTER")
keyListener:EnableKeyboard(true)
keyListener:SetPropagateKeyboardInput(true) -- pass all keys through by default
keyListener:Show()

keyListener:SetScript("OnKeyDown", function(self, key)
    local CLN = _G.ChattyLittleNpc
    if not CLN or not CLN.db then return end

    local boundKey = CLN.db.profile and CLN.db.profile.playVoiceoverKey
    if not boundKey or boundKey == "" or key ~= boundKey then return end

    -- Our key — consume it so the game doesn't also react
    self:SetPropagateKeyboardInput(false)

    if CLN.VoiceoverPlayer and CLN.VoiceoverPlayer:IsEffectivelyPlaying() then
        CLN.VoiceoverPlayer:ForceStopCurrentSound(false, true)
    elseif CLN.PlayButton and CLN.PlayButton._currentPlayCallback then
        CLN.PlayButton._currentPlayCallback()
    end
end)

keyListener:SetScript("OnKeyUp", function(self)
    -- Restore propagation after each key-up so future non-matching keys pass through
    self:SetPropagateKeyboardInput(true)
end)
