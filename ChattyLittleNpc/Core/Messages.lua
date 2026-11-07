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
}

return CLN.Messages
