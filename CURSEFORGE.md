<!--
CurseForge project description for Chatty Little NPC.
Kept here for reference only; not packaged (see pkgmeta.yaml ignore list).
Paste the content below this comment into the CurseForge description editor (Markdown mode).
-->

## Chatty Little NPC

**Give a voice to every quest giver in Azeroth, on every WoW client, including WoW Forever.**

Chatty Little NPC plays AI-generated voiceovers for quest text, NPC gossip, books and letters. Each NPC gets a voice that fits their race and gender, and a conversation window shows them talking with subtitles as they speak.

<iframe src="https://www.youtube.com/embed/3VhY3L3A5Dg" width="560" height="314" allowfullscreen="allowfullscreen"></iframe>

### ✨ Now on every WoW client, including WoW Forever

One addon covers every client. Install it, add the voiceover packs for the content you play, and it works:

*   **Retail**, including **Midnight**
*   **WoW Forever**
*   **Mists of Pandaria Classic**
*   **The Burning Crusade Anniversary**
*   **Classic Era**

Playing on WoW Forever or Classic Era? Install the **Vanilla** pack. Anniversary needs **Vanilla** and **The Burning Crusade**.

## Getting Started

The base addon contains no audio. The voices come in separate packs, one for each expansion.

1.  Install **Chatty Little NPC** (this addon).
2.  Install the voiceover packs for the expansions you play (see the list below).
3.  Log in or `/reload`. The first time, a welcome screen walks you through the main settings.

## Features

*   **Voiced dialog**: quest greetings, descriptions, progress and completion text, NPC gossip, and readable items such as books and letters.
*   **Voices by race and gender**: different NPCs sound different.
*   **Conversation window**: an animated portrait of the NPC who is speaking, with subtitles and a queue of upcoming lines. Pick a minimal, panel or cinematic style, place the portrait above, below or beside the text, and move it anywhere with Edit Mode.
*   **Replay any line**: a play button in the quest log and dialog windows, plus a keybind to play or stop voiceovers that also works with controller buttons (Key Bindings > Chatty Little NPC).
*   **Voiceover library**: browse, search and play every voiceover in your installed packs (`/clnlibrary`).
*   **Works with Blizzard voice acting**: it stays quiet for NPCs that Blizzard already voices, and you can manage the list yourself.
*   **Profiles**: use settings per character or share them across characters.
*   **Compatible with** DialogueUI and ElvUI.
*   **For addon authors**: a public API lets other addons play, stop and react to voiceovers.

## Commands

*   `/clnsettings`: open the settings window
*   `/clnlibrary`: browse and play installed voiceovers
*   `/clnwelcome`: show the welcome screen again

## Voiceover Packs

*   [Vanilla](https://www.curseforge.com/wow/addons/chatty-little-npc-vanilla)
*   [The Burning Crusade](https://www.curseforge.com/wow/addons/chatty-little-npc-the-burning-crusade)
*   [Wrath of the Lich King](https://www.curseforge.com/wow/addons/chatty-little-npc-wrath-of-the-lich-king)
*   [Cataclysm](https://www.curseforge.com/wow/addons/chatty-little-npc-cataclysm)
*   [Mists of Pandaria](https://www.curseforge.com/wow/addons/chatty-little-npc-mists-of-pandaria)
*   [Warlords of Draenor](https://www.curseforge.com/wow/addons/chatty-little-npc-warlords-of-draenor)
*   [Legion](https://www.curseforge.com/wow/addons/chatty-little-npc-legion)
*   [Battle for Azeroth](https://www.curseforge.com/wow/addons/chatty-little-npc-battle-for-azeroth)
*   [Shadowlands](https://www.curseforge.com/wow/addons/chatty-little-npc-shadowlands)
*   [Dragonflight](https://www.curseforge.com/wow/addons/chatty-little-npc-dragonflight)
*   [The War Within](https://www.curseforge.com/wow/addons/chatty-little-npc-the-war-within-en-us)
*   [Midnight](https://www.curseforge.com/wow/addons/chatty-little-npc-midnight-english-ai-voiceover)

The About tab in the settings window shows which packs you have installed.

## Help Fill the Gaps

Found a line with no voice? Turn on **Track NPC Dialog Data** (Settings > Developer) and the addon records the dialog you see while playing. Share your `WTF\Account\<ACCOUNT>\SavedVariables\ChattyLittleNpc.lua` file in **#data-gathering-chat** on Discord, and new voiceovers get made from it.

## Coming Next

*   Better voice quality with each voice engine update

## A Note on AI Use

Chatty Little NPC started in May 2024 as a hand-written experiment, and I spent roughly the first year building and learning by hand. From mid-2025, once models like Claude Opus 4 and Sonnet 4 became accurate enough and available in VS Code, I started using AI more and more to help maintain the addon and build new features. That work is currently done with Anthropic's Claude Opus 5.5 model.

## Discord: [Chatty Little NPC](https://discord.gg/dVjTXBgNb)
