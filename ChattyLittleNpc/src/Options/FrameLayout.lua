-- Options/FrameLayout.lua - Window position, size and Edit Mode.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local sections = CLN.OptionsDefinition.args

-- ═══════════════════════════════════════════════
-- FRAME LAYOUT — Positioning, sizing, edit mode
-- ═══════════════════════════════════════════════
sections.FrameLayout = {
    order = 30,
    type = 'group',
    name = 'Frame Layout',
    desc = 'Position, resize, and adjust the voiceover frame and play button.',
    inline = true,
    args = {
        editMode = {
            order = 1,
            type = 'toggle',
            width = 'full',
            name = 'Edit Mode',
            desc = 'Enable edit mode to move and resize the voiceover frame. Disable when done.',
            get = function(info)
                return CLN.ReplayFrame._editMode or false
            end,
            set = function(info, value)
                if value then
                    CLN.ReplayFrame:ShowForEdit()
                else
                    CLN.ReplayFrame:SetEditMode(false)
                    CLN.ReplayFrame._forceShow = false
                    CLN.ReplayFrame:UpdateDisplayFrameState()
                end
            end,
        },
        editModeGlowHints = {
            order = 2,
            type = 'toggle',
            width = 'full',
            name = 'Edit Mode Glow Hints',
            desc = 'Show a subtle glow pulse around the frame in edit mode to help you find it.',
            get = function(info) return CLN.db.profile.editModeGlowHints end,
            set = function(info, value) CLN.db.profile.editModeGlowHints = value end,
        },
        queueTextScale = {
            order = 3,
            type = 'range',
            width = 'double',
            name = 'Queue Text Size',
            desc = 'Adjust the text size of queue entries and headers in the voiceover frame.',
            min = 0.75,
            max = 1.5,
            step = 0.05,
            get = function(info)
                return CLN.db.profile.queueTextScale or 1.0
            end,
            set = function(info, value)
                CLN.db.profile.queueTextScale = value
                CLN.ReplayFrame:ApplyQueueTextScale()
            end,
        },
        frameScale = {
            order = 4,
            type = 'range',
            width = 'double',
            name = 'Frame Scale',
            desc = 'Scale the entire voiceover frame up or down. Useful for high-resolution displays.',
            min = 0.5,
            max = 2.0,
            step = 0.05,
            get = function(info)
                return CLN.db.profile.frameScale or 1.0
            end,
            set = function(info, value)
                value = math.max(0.5, math.min(2.0, value))
                CLN.db.profile.frameScale = value
                if CLN.ReplayFrame.DisplayFrame then
                    CLN.ReplayFrame.DisplayFrame:SetScale(value)
                end
            end,
        },
        npcModelFrameHeight = {
            order = 5,
            type = 'range',
            width = 'double',
            name = 'Portrait Height',
            desc = 'Height of the NPC portrait area in pixels. Larger values show more of the NPC model.',
            min = 50,
            max = 300,
            step = 5,
            get = function(info)
                return CLN.db.profile.npcModelFrameHeight or 140
            end,
            set = function(info, value)
                CLN.db.profile.npcModelFrameHeight = value
                if CLN.ReplayFrame then
                    CLN.ReplayFrame.npcModelFrameHeight = value
                    if CLN.ReplayFrame.ModelContainer then
                        CLN.ReplayFrame.ModelContainer:SetHeight(value)
                    end
                    if CLN.ReplayFrame.NpcModelFrame then
                        CLN.ReplayFrame.NpcModelFrame:SetHeight(value)
                    end
                    -- Re-dock so Above/Below pick up the new height
                    if CLN.ReplayFrame.LayoutModelArea and CLN.ReplayFrame.DisplayFrame then
                        CLN.ReplayFrame:LayoutModelArea(CLN.ReplayFrame.DisplayFrame)
                    end
                end
            end,
        },
        portraitPosition = {
            order = 5.1,
            type = 'select',
            width = 'double',
            name = 'Portrait Position',
            desc = 'Which side of the conversation window the NPC portrait is attached to.\n\nLeft and Right match the conversation window\'s height; Portrait Height applies to Above and Below.',
            values = { above = 'Above', below = 'Below', left = 'Left', right = 'Right' },
            sorting = { 'above', 'below', 'left', 'right' },
            get = function() return CLN.db.profile.portraitPosition or 'above' end,
            set = function(_, value)
                CLN.db.profile.portraitPosition = value
                local RF = CLN.ReplayFrame
                if RF and RF.LayoutModelArea and RF.DisplayFrame then
                    RF:LayoutModelArea(RF.DisplayFrame)
                    -- Re-frame for the new portrait shape
                    if RF._hasValidModel and RF.ApplyDefaultFit then RF:ApplyDefaultFit() end
                end
            end,
        },
        dockToObjectives = {
            order = 5.5,
            type = 'toggle',
            width = 'full',
            name = 'Dock Next to Objectives Tracker',
            desc = 'Keep the voiceover frame to the left of the quest objectives tracker. Moving the frame turns this off; Reset Voiceover Frame Position turns it back on.',
            get = function() return CLN.db.profile.frameAnchor == "objectives" end,
            set = function(_, value)
                if value then
                    CLN.ReplayFrame:DockToObjectives()
                else
                    -- Stay where it is, but as a free, saved position
                    CLN.ReplayFrame:UndockFrame()
                    CLN.db.profile.frameAnchor = "free"
                    if CLN.ReplayFrame.DisplayFrame then CLN.ReplayFrame:SaveFramePosition() end
                end
            end,
        },
        resetFramePos = {
            order = 6,
            type = 'execute',
            name = 'Reset Voiceover Frame Position',
            desc = 'Reset the voiceover frame to its default position on screen.',
            func = function() CLN.ReplayFrame:ResetFramePosition() end,
        },
        portraitLookHeader = {
            order = 6.1,
            type = 'header',
            name = 'Portrait Look',
        },
        openPortraitTuner = {
            order = 6.2,
            type = 'execute',
            name = 'Customize Portrait Camera',
            desc = 'Adjust how the NPC portrait is framed for each frame style (height, zoom, camera angle, facing), preview emotes, and save. Each shot can be reset to its default.',
            func = function()
                if CLN.PortraitTuner then CLN.PortraitTuner:Toggle() end
            end,
        },
        openItemPropPicker = {
            order = 6.3,
            type = 'execute',
            name = 'Customize Book & Letter Models',
            desc = 'Choose the book, letter and plaque models shown as the portrait for readable items and objects. Each one can be reset to its default.',
            func = function()
                if CLN.ItemPropPicker then CLN.ItemPropPicker:Toggle() end
            end,
        },
        playButtonSpacer = {
            order = 6.5,
            type = 'header',
            name = 'Play Button',
        },
        buttonPosX = {
            order = 7,
            type = 'range',
            width = 'double',
            name = 'Play Button X Offset',
            desc = 'Horizontal offset for the play button on quest/gossip frames.',
            min = -200,
            max = 200,
            step = 1,
            get = function(info) return CLN.db.profile.buttonPosX or 0 end,
            set = function(info, value)
                CLN.db.profile.buttonPosX = value
                CLN.PlayButton:UpdateButtonPositions()
            end,
        },
        buttonPosY = {
            order = 8,
            type = 'range',
            width = 'double',
            name = 'Play Button Y Offset',
            desc = 'Vertical offset for the play button on quest/gossip frames.',
            min = -200,
            max = 200,
            step = 1,
            get = function(info) return CLN.db.profile.buttonPosY or 0 end,
            set = function(info, value)
                CLN.db.profile.buttonPosY = value
                CLN.PlayButton:UpdateButtonPositions()
            end,
        },
        resetButtonPosition = {
            order = 9,
            type = 'execute',
            name = 'Reset Play Button Position',
            desc = 'Reset the play button to its default position on dialog frames.',
            func = function()
                CLN.db.profile.buttonPosX = -15
                CLN.db.profile.buttonPosY = -30
                CLN.PlayButton:UpdateButtonPositions()
            end,
        },
    },
}
