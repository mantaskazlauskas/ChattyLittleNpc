# Third-Party APIs (Raider.IO, Warcraft Logs, Wago)

> Community APIs for rankings, combat logs, and addon distribution.

## Raider.IO API

> Mythic+ and raid rankings. Free, rate-limited, no auth for basic use.
> Docs: https://raider.io/api (Swagger UI)
> OpenAPI spec: https://raider.io/openapi.json

### Rate Limits
- **200 requests/minute** unauthenticated
- Higher limits with API key from https://raider.io/settings/apps

### Key Endpoints

#### Character Profile
```
GET https://raider.io/api/v1/characters/profile
  ?region=us
  &realm=tichondrius
  &name=CharacterName
  &fields=mythic_plus_scores_by_season:current,raid_progression,gear,talents
```

**Available fields:**
- `gear` — Item info
- `talents` — Talent loadouts (`talents:categorized` for class/spec split)
- `guild` — Basic guild info
- `raid_progression` — Raid boss kills (`:current-expansion`, `:current-tier`, or raid slug)
- `mythic_plus_scores_by_season:current` — M+ scores
- `mythic_plus_ranks` — Current season rankings
- `mythic_plus_recent_runs` — 10 most recent M+ runs
- `mythic_plus_best_runs` — 10 best M+ runs (`:all` for complete list)
- `mythic_plus_alternate_runs` — Alternate (2nd best) runs
- `mythic_plus_highest_level_runs` — Highest keys
- `raid_achievement_curve` — AOTC/CE status per raid slug

#### Guild Profile
```
GET https://raider.io/api/v1/guilds/profile
  ?region=us&realm=tichondrius&name=GuildName
  &fields=raid_progression,raid_rankings,members
```

#### Mythic+ Runs (Top Runs)
```
GET https://raider.io/api/v1/mythic-plus/runs
  ?season=season-tww-3
  &region=world
  &dungeon=all
  &page=0
```

#### Current Affixes
```
GET https://raider.io/api/v1/mythic-plus/affixes?region=us&locale=en
```

#### Mythic+ Static Data (Seasons/Dungeons)
```
GET https://raider.io/api/v1/mythic-plus/static-data?expansion_id=11
```
Expansion IDs: 11=Midnight, 10=TWW, 9=Dragonflight, 8=Shadowlands, 7=BfA, 6=Legion

#### Score Tiers (Colors)
```
GET https://raider.io/api/v1/mythic-plus/score-tiers?season=season-tww-3
```

#### Season Cutoffs
```
GET https://raider.io/api/v1/mythic-plus/season-cutoffs?season=season-tww-3&region=us
```

#### Current/Next Period
```
GET https://raider.io/api/v1/periods
```

### Attribution
Public-facing apps **must** link back to https://raider.io.

---

## Warcraft Logs API (v2)

> Combat log analysis data via GraphQL.
> Docs: https://www.warcraftlogs.com/api/docs
> Endpoint: https://www.warcraftlogs.com/api/v2/client

### Authentication
1. Create app at https://www.warcraftlogs.com/api/clients
2. Uses OAuth2 client credentials flow
3. Token endpoint: `https://www.warcraftlogs.com/oauth/token`

```bash
curl -X POST "https://www.warcraftlogs.com/oauth/token" \
  -d "grant_type=client_credentials" \
  -u "CLIENT_ID:CLIENT_SECRET"
```

### GraphQL Queries

```graphql
# Get character parses
{
  characterData {
    character(name: "CharName", serverSlug: "tichondrius", serverRegion: "US") {
      name
      classID
      encounterRankings(encounterID: 2820)  # Boss encounter ID
      zoneRankings(zoneID: 38)               # Raid zone ID
    }
  }
}
```

```graphql
# Get report data
{
  reportData {
    report(code: "REPORT_CODE") {
      title
      startTime
      endTime
      fights {
        id
        name
        kill
        difficulty
      }
    }
  }
}
```

```graphql
# World data (rankings, zones)
{
  worldData {
    zone(id: 38) {
      name
      encounters {
        id
        name
      }
    }
  }
}
```

### Key Query Types
- `characterData.character` — Character rankings and parses
- `reportData.report` — Individual combat log reports
- `reportData.reports` — List of reports for a guild
- `worldData.zone` — Raid zone info and encounters
- `worldData.encounter` — Specific encounter data
- `guildData.guild` — Guild info and reports

### Rate Limits
- **3,600 points/hour** (each query costs points based on complexity)
- Optimize queries to request only needed fields

---

## Wago.io API

> Addon and WeakAura distribution platform.
> Docs: https://docs.wago.io/

### Authentication

```
Authorization: Bearer YOUR_API_KEY
```

Generate keys at: https://addons.wago.io/account/apikeys

### Addon Release Upload

```bash
POST https://addons.wago.io/api/projects/{project_id}/version

curl -f -X POST \
  -F "metadata={\"label\":\"1.2.3\",\"stability\":\"stable\",\"changelog\":\"# Changes...\"}" \
  -F "file=@MyAddon-1.2.3.zip" \
  -H "Authorization: Bearer $WAGO_API_KEY" \
  -H "Accept: application/json" \
  https://addons.wago.io/api/projects/{project_id}/version
```

### Release Metadata JSON

```json
{
  "label": "1.2.3",
  "stability": "stable",           // stable, beta, alpha
  "changelog": "# Changelog...",   // Markdown string
  "supported_retail_patch": "12.0.1",
  "supported_classic_patch": "1.15.8"
}
```

### Available Game Versions
```
GET https://addons.wago.io/api/data/game
```

### TOC Integration

Add your Wago project ID to your addon's `.toc`:
```toc
## X-Wago-ID: as3Dfg57
```

### BigWigs Packager Integration

The [BigWigs packager](https://github.com/BigWigsMods/packager) automates releases to Wago.

**GitHub Actions:**
```yaml
- name: Create Package
  uses: BigWigsMods/packager@master
  env:
    WAGO_API_TOKEN: ${{ secrets.WAGO_API_TOKEN }}
```

---

## Other Notable APIs

### Postman Collections
Community-maintained WoW API collections: https://www.postman.com/api-evangelist/blizzard

### WoW.tools
Datamining tool for browsing game data files, models, sounds:
- https://wow.tools/

### GitHub: wow-ui-source (Gethe)
Mirror of Blizzard's UI source code — the most authoritative reference for FrameXML behavior:
- https://github.com/Gethe/wow-ui-source
- Browse by branch: `live` (current retail), `12.0.1`, `beta`, etc.
- Blizzard API docs are at: `Interface/AddOns/Blizzard_APIDocumentationGenerated/`
