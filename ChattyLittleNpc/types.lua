---@meta

-- Type definitions for ChattyLittleNpc addon
-- This file contains all class definitions and is not loaded at runtime

---@class Database
---@field profile table The current profile data (accessed via metatable)
---@field savedVarName string
---@field defaults table
---@field callbacks table
---@field sv table

---@class EventSystem
---@field frame table
---@field events table
---@field messages table

---@class ConfigSystem
---@field categories table
---@field options table
---@field db table
---@field optionsTable table
---@field category table
---@field panel table

---@class EventHandler

---@class PrintUtil
---@field Print fun(self: PrintUtil, ...: any)

---@class ReplayFrame
---@field waveLowerDelta? number Optional override for wave emote lower delta (default 0.05)
---@field talkChance? number Optional override for talk chance in emote loop
---@field talkMinDuration? number Optional override for minimum talk duration
---@field talkMaxDuration? number Optional override for maximum talk duration
---@field idleMinDuration? number Optional override for minimum idle duration
---@field idleMaxDuration? number Optional override for maximum idle duration
---@field SetQueueData? fun(self: ReplayFrame, entries: table) Set queue data for the list view
---@field QueueListFrame? table The queue list frame

---@class ChattyLittleNpc
---@field db Database The database object with profile management
---@field Database Database The Database class
---@field PrintUtil PrintUtil The Print utility class
---@field EventSystem EventSystem The EventSystem class
---@field TimerUtil table The TimerUtil class
---@field EventHandler EventHandler
---@field Options table
---@field ConfigSystem ConfigSystem
---@field locale string
---@field gameVersion number
---@field useNamespaces boolean
---@field expansions table
---@field loadedVoiceoverPacks table
---@field VoiceoverPacks table
---@field questsQueue table
---@field isDUIAddonLoaded boolean
---@field isElvuiAddonLoaded boolean
---@field currentItemInfo table
---@field Utils table
---@field VoiceoverPlayer table
---@field NpcDialogTracker table
---@field PlayButton table
---@field ReplayFrame table
---@field Print fun(self: ChattyLittleNpc, ...: any)
---@field CheckVoiceoverPacks fun(self: ChattyLittleNpc)
---@field PlayQuestTTS fun(self: ChattyLittleNpc, quest: table)
---@field SendMessage fun(self: ChattyLittleNpc, message: string, ...)
