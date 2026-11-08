-- Messages.lua - Names of the addon-internal messages sent on the shared bus
-- (CLN:SendMessage / CLN:RegisterMessage, see Core/Events.lua and Main.lua).
--
-- The playback core (VoiceoverPlayer, EventHandler) announces what changed;
-- UI modules subscribe instead of being called directly. Messages are
-- delivered synchronously, in registration order, each handler in a pcall.
--
-- Handlers receive the message name first, then the payload:
--   CLN:RegisterMessage(CLN.Messages.QUEUE_CHANGED, function(msg, reason) ... end)

local CLN = _G.ChattyLittleNpc or {}
_G.ChattyLittleNpc = CLN

CLN.Messages = {
    --- The queue's contents changed.
    --- Payload: reason (string|nil) — "cleared" when the whole queue was dropped.
    QUEUE_CHANGED = "CLN_QUEUE_CHANGED",

    --- The current playback state may have changed (started, paused, resumed,
    --- stopped, finished, or an attempt failed). Sent whenever the display
    --- should refresh, so handlers must tolerate repeats with the same state.
    --- Payload: state (VoiceoverPlayer.State value), record (currentlyPlaying, may be an empty record).
    PLAYBACK_STATE_CHANGED = "CLN_PLAYBACK_STATE_CHANGED",

    --- A finished, skipped or dropped line was added to the replay history.
    --- Payload: entry (table: title, npcId, questId, phase, entryType, state,
    --- gender, displayID, libraryEntry, completedAt, plus cached NPC metadata).
    HISTORY_ADDED = "CLN_HISTORY_ADDED",

    --- Playback stopped with nothing left to play (natural end or forced stop).
    --- Payload: lastText (string|nil) — title of the line that was playing, if known.
    CONVERSATION_ENDED = "CLN_CONVERSATION_ENDED",

    --- Text continuation was stopped or paused: drop any subtitles on screen
    --- and cancel their timers. No payload.
    SUBTITLES_CANCELLED = "CLN_SUBTITLES_CANCELLED",

    --- A line is about to start or was restored: forget the portrait's
    --- animation state left over from the previous one. No payload.
    ANIMATION_RESET = "CLN_ANIMATION_RESET",

    --- A non-quest or library line started: animate the portrait now. Quest
    --- lines don't send this; their animation starts from the display update.
    --- No payload.
    ANIMATION_START = "CLN_ANIMATION_START",

    --- Playback was paused: stop the portrait animating. No payload.
    ANIMATION_FREEZE = "CLN_ANIMATION_FREEZE",
}

return CLN.Messages
