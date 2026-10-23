<div style="display: flex; justify-content: space-between;">
    <span><h1>Chatty Little NPC </h1></span>
    <span style="display: inline-block;">
        <a href="https://www.paypal.com/donate/?hosted_button_id=CZGQYKYFRURMW" target="_blank">
            <img src="https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif" alt="Donate with PayPal">
        </a>
    </span>
</div>

Chatty Little NPC gives a voice to World of Warcraft's quest givers and NPCs. It plays AI-generated voiceovers for quest text, gossip, books and letters, with voices matched to each NPC's race and gender, and shows the NPC speaking in a small conversation frame.

**Discord:** [discord.gg/dVjTXBgNb](https://discord.gg/dVjTXBgNb)

## Getting Started

The addon itself contains no audio. The voices come in separate voiceover packs, one per expansion:

1. Install **Chatty Little NPC**.
2. Install the voiceover packs for the content you play (see the list below).
3. `/reload` or log in. A welcome screen walks you through the main settings the first time.

| Expansion | Pack |
| --- | --- |
| Vanilla (Classic / Classic Era) | [CurseForge](https://www.curseforge.com/wow/addons/chatty-little-npc-vanilla) |
| The Burning Crusade | [CurseForge](https://www.curseforge.com/wow/addons/chatty-little-npc-the-burning-crusade) |
| Wrath of the Lich King | [CurseForge](https://www.curseforge.com/wow/addons/chatty-little-npc-wrath-of-the-lich-king) |
| Cataclysm | [CurseForge](https://www.curseforge.com/wow/addons/chatty-little-npc-cataclysm) |
| Mists of Pandaria | [CurseForge](https://www.curseforge.com/wow/addons/chatty-little-npc-mists-of-pandaria) |
| Warlords of Draenor | [CurseForge](https://www.curseforge.com/wow/addons/chatty-little-npc-warlords-of-draenor) |
| Legion | [CurseForge](https://www.curseforge.com/wow/addons/chatty-little-npc-legion) |
| Battle for Azeroth | [CurseForge](https://www.curseforge.com/wow/addons/chatty-little-npc-battle-for-azeroth) |
| Shadowlands | [CurseForge](https://www.curseforge.com/wow/addons/chatty-little-npc-shadowlands) |
| Dragonflight | [CurseForge](https://www.curseforge.com/wow/addons/chatty-little-npc-dragonflight) |
| The War Within | [CurseForge](https://www.curseforge.com/wow/addons/chatty-little-npc-the-war-within-en-us) |
| Midnight | [CurseForge](https://www.curseforge.com/wow/addons/chatty-little-npc-midnight-english-ai-voiceover) |

The About tab in the settings window shows which packs you have installed.

## Features

- **Voiced dialog**: quest greetings, descriptions, progress and completion text, NPC gossip, and readable items such as books and letters.
- **Distinct voices**: separate voices by race and gender, so different NPCs sound different.
- **Conversation frame**: an animated portrait of the speaking NPC with subtitles and a queue of upcoming lines. Choose from minimal, panel and cinematic styles, dock the portrait above, below or beside the text, and move it with Edit Mode.
- **Play button and keybind**: replay any line from the quest log or dialog window, or bind a key to play and stop voiceovers (Key Bindings > AddOns > Chatty Little NPC).
- **Voiceover library**: browse, search and play every voiceover in your installed packs.
- **Plays well with Blizzard voice acting**: pauses for NPCs that already have Blizzard voice acting, with a whitelist you can manage.
- **Language-aware packs**: choose a voiceover language when packs for more than one language are installed.
- **Profiles**: per-character or shared settings profiles.
- **Compatible with** DialogueUI and ElvUI.

## Supported Game Versions

Retail (including Midnight), Mists of Pandaria Classic, Cataclysm Classic, Wrath Classic, Burning Crusade Classic, Classic Era and WoW Forever.

## Commands

| Command | What it does |
| --- | --- |
| `/clnsettings` | Open or close the settings window |
| `/clnlibrary` | Browse and play every installed voiceover |
| `/clnwelcome` | Show the welcome screen again |
| `/clnlogs` | Open the addon log window |

## Help Expand the Database

Missing a voiceover? The addon can record the quest and NPC dialog you see while playing (turn on **Track NPC Dialog Data** in Settings > Developer). New voiceovers are made from this data.

To share it, post your `ChattyLittleNpc.lua` file in the **#data-gathering-chat** channel on [Discord](https://discord.gg/dVjTXBgNb). You'll find it in your game folder (`_retail_`, `_classic_` or `_classic_era_`) under:

```
WTF\Account\<ACCOUNT>\SavedVariables\ChattyLittleNpc.lua
```

The game writes this file when you log out or `/reload`.

## Roadmap

- (DONE) Different narrator voices for male and female NPCs.
- (DONE) Voiceovers for all dialog types: gossip, quest greeting, description, progress and completion.
- (DONE) Record dialog while playing so that missing voiceovers can be generated.
- (DONE) Distinct voices for different races and body types.
- (DONE) Voiceover packs for every expansion.
- (DONE) Voiceovers for books, letters and other readable items.
- (IN PROGRESS) Keep upgrading the voice engine to reduce hallucinations and improve voice quality.
- (IN PROGRESS) Voiceover packs in more languages.
