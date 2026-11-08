-- Options/Advanced.lua - Accessibility and advanced rendering.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local sections = CLN.OptionsDefinition.args

-- ═══════════════════════════════════════════════
-- ACCESSIBILITY — High-contrast and keyboard nav
-- ═══════════════════════════════════════════════
sections.Accessibility = {
    order = 35,
    type = 'group',
    name = 'Accessibility',
    desc = 'High-contrast mode and keyboard navigation settings.',
    inline = true,
    args = {
        highContrastMode = {
            order = 1,
            type = 'toggle',
            name = 'High-Contrast Mode',
            desc = 'Brighten colors and add text type badges ([Q] Quest, [G] Gossip, [I] Item) for colorblind users. Also activates when WoW\'s colorblind mode is enabled.',
            width = 'full',
            get = function(info) return CLN.db.profile.highContrastMode end,
            set = function(info, value)
                CLN.db.profile.highContrastMode = value
                CLN.ReplayFrame:MarkQueueDirty()
            end,
        },
        keyboardNavHint = {
            order = 2,
            type = 'description',
            name = '\n|cFFFFD100Keyboard Navigation:|r  Tab into queue list, Up/Down arrows to navigate, Enter/Space to activate, Escape to deselect, Home/End to jump.',
            fontSize = 'medium',
        },
    },
}

-- ═══════════════════════════════════════════════
-- ADVANCED — NPC model rendering settings
-- ═══════════════════════════════════════════════
sections.Advanced = {
    order = 40,
    type = 'group',
    name = 'Advanced',
    desc = 'NPC portrait rendering and camera behavior.',
    inline = true,
    args = {
        renderBackend = {
            order = 1,
            type = 'select',
            width = 'double',
            name = 'NPC Model Renderer',
            desc = 'Which renderer draws the NPC portrait.\n\n• Auto — uses the best option for your game version\n• ModelScene — modern renderer (Retail)\n• PlayerModel — classic/legacy renderer',
            values = function()
                return {
                    auto = 'Auto (recommended)',
                    scene = 'ModelScene (modern)',
                    player = 'PlayerModel (legacy)',
                }
            end,
            hidden = function()
                return not CLN.ReplayFrame:IsModelSceneAvailable()
            end,
            get = function(info)
                return CLN.db.profile.renderBackend or 'auto'
            end,
            set = function(info, value)
                CLN.db.profile.renderBackend = value
                CLN.ReplayFrame:RebuildModelHost()
                CLN.ReplayFrame:UpdateDisplayFrameState()
            end,
        },
        advancedCameraFitting = {
            order = 2,
            type = 'toggle',
            width = 'full',
            name = 'Enhanced Portrait Framing',
            desc = 'Use improved camera positioning for better NPC portrait framing. Disable if you see visual jitter.',
            get = function(info)
                return CLN.db.profile.advancedCameraFitting
            end,
            set = function(info, value)
                CLN.db.profile.advancedCameraFitting = value
                CLN.ReplayFrame:RebuildModelHost()
                local cur = CLN.VoiceoverPlayer.currentlyPlaying
                if cur and (CLN.ReplayFrame.NpcModelFrame and CLN.ReplayFrame.NpcModelFrame.IsShown and CLN.ReplayFrame.NpcModelFrame:IsShown()) then
                    CLN.ReplayFrame:ApplyDefaultFit(cur.displayID)
                end
            end,
        },
        disableCameraAnimations = {
            order = 3,
            type = 'toggle',
            width = 'full',
            name = 'Disable Portrait Animations',
            desc = 'Stop camera zoom and pan effects on the NPC portrait. The NPC model still animates normally.',
            get = function(info)
                return CLN.db.profile.disableCameraAnimations
            end,
            set = function(info, value)
                CLN.db.profile.disableCameraAnimations = value
                if CLN.ReplayFrame then
                    if CLN.ReplayFrame.AnimStop then
                        CLN.ReplayFrame:AnimStop('zoom')
                        CLN.ReplayFrame:AnimStop('pan')
                    end
                    if CLN.ReplayFrame._UpdateModelOnUpdateHook then
                        CLN.ReplayFrame:_UpdateModelOnUpdateHook()
                    end
                end
            end,
        },
    },
}
