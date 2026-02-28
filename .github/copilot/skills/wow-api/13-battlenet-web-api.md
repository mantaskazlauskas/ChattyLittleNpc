# Battle.net Web API (WoW Game Data & Profile APIs)

> External HTTP REST APIs for accessing WoW data outside the game client. Requires OAuth2.
> Official portal: https://develop.battle.net/documentation/world-of-warcraft
> Forum guide: https://us.forums.blizzard.com/en/blizzard/t/getting-started-with-the-wow-api/12097

## Overview

The Battle.net Web API (separate from the in-game Lua AddOn API) provides HTTP REST endpoints for:
- **Game Data APIs** — static/dynamic game data (items, spells, mounts, achievements, auction house, etc.)
- **Profile APIs** — player character data (equipment, collections, M+ scores, raid progression)
- **Media APIs** — image/icon URLs for items, creatures, spells, etc.

## Getting Started

### 1. Create API Credentials

1. Visit https://develop.battle.net/access/clients
2. Create a new client (use `http://localhost` for redirect URI initially)
3. Note your **Client ID** and **Client Secret**
4. Credentials may take up to 15 minutes to activate

### 2. Authentication (OAuth2)

#### Client Credentials Flow (Game Data)

```bash
# Get access token
curl -X POST "https://oauth.battle.net/token" \
  -d "grant_type=client_credentials" \
  -u "CLIENT_ID:CLIENT_SECRET"

# Response:
# {"access_token":"USxxxxx","token_type":"bearer","expires_in":86399}
```

#### Authorization Code Flow (Profile Data)

Required for endpoints that access player-specific data (protected profiles).

1. Redirect user to: `https://oauth.battle.net/authorize?client_id=CLIENT_ID&redirect_uri=REDIRECT&response_type=code&scope=wow.profile`
2. User authorizes, redirected back with `?code=AUTH_CODE`
3. Exchange code for token:
```bash
curl -X POST "https://oauth.battle.net/token" \
  -d "grant_type=authorization_code&code=AUTH_CODE&redirect_uri=REDIRECT" \
  -u "CLIENT_ID:CLIENT_SECRET"
```

### 3. Making Requests

```bash
# Game Data API example (item)
curl "https://us.api.blizzard.com/data/wow/item/19019?namespace=static-us&locale=en_US" \
  -H "Authorization: Bearer ACCESS_TOKEN"

# Profile API example (character)
curl "https://us.api.blizzard.com/profile/wow/character/tichondrius/charactername?namespace=profile-us&locale=en_US" \
  -H "Authorization: Bearer ACCESS_TOKEN"
```

## Namespaces

Every request requires a `namespace` parameter:

| Namespace | Description | Update Frequency |
|-----------|-------------|------------------|
| `static-{region}` | Items, spells, mounts, classes, etc. | Patches only |
| `dynamic-{region}` | Auctions, mythic+ leaderboards, etc. | Regular intervals |
| `profile-{region}` | Character data | On character logout |

**Regions**: `us`, `eu`, `kr`, `tw`, `cn`

## Key Endpoints

### Game Data APIs

| Category | Endpoint | Namespace |
|----------|----------|-----------|
| **Achievements** | `/data/wow/achievement/index` | static |
| **Auction House** | `/data/wow/connected-realm/{id}/auctions` | dynamic |
| **Creatures** | `/data/wow/creature/{id}` | static |
| **Dungeons** | `/data/wow/dungeon/index` | static |
| **Items** | `/data/wow/item/{id}` | static |
| **Item Classes** | `/data/wow/item-class/index` | static |
| **Journal (Raids)** | `/data/wow/journal-instance/index` | static |
| **Mounts** | `/data/wow/mount/index` | static |
| **M+ Leaderboards** | `/data/wow/connected-realm/{id}/mythic-leaderboard/` | dynamic |
| **Pets** | `/data/wow/pet/index` | static |
| **Playable Classes** | `/data/wow/playable-class/index` | static |
| **Playable Races** | `/data/wow/playable-race/index` | static |
| **Playable Specs** | `/data/wow/playable-specialization/index` | static |
| **PvP Seasons** | `/data/wow/pvp-season/index` | dynamic |
| **Quests** | `/data/wow/quest/{id}` | static |
| **Realms** | `/data/wow/realm/index` | dynamic |
| **Recipes** | `/data/wow/recipe/{id}` | static |
| **Spells** | `/data/wow/spell/{id}` | static |
| **Talents** | `/data/wow/talent-tree/index` | static |
| **Toys** | `/data/wow/toy/index` | static |

### Profile APIs

| Category | Endpoint | Auth Required |
|----------|----------|---------------|
| **Character Summary** | `/profile/wow/character/{realm}/{name}` | Client Credentials |
| **Character Equipment** | `/profile/wow/character/{realm}/{name}/equipment` | Client Credentials |
| **Character M+ Profile** | `/profile/wow/character/{realm}/{name}/mythic-keystone-profile` | Client Credentials |
| **Character Raid Progression** | `/profile/wow/character/{realm}/{name}/encounters/raids` | Client Credentials |
| **Character Collections** | `/profile/wow/character/{realm}/{name}/collections/mounts` | Client Credentials |
| **Character Achievements** | `/profile/wow/character/{realm}/{name}/achievements` | Client Credentials |
| **Account Profile** | `/profile/user/wow` | Authorization Code |
| **Protected Character** | `/profile/user/wow/protected-character/{realm-id}-{character-id}` | Authorization Code |

### Media APIs

```bash
# Get item media (icon)
GET /data/wow/media/item/{id}?namespace=static-us

# Get creature display media
GET /data/wow/media/creature-display/{id}?namespace=static-us

# Get spell media
GET /data/wow/media/spell/{id}?namespace=static-us
```

### Search Endpoints

For items and spells (too many to list in an index):

```bash
# Search items by name
GET /data/wow/search/item?namespace=static-us&name.en_US=Thunderfury&orderby=id

# Search with filters
GET /data/wow/search/item?namespace=static-us&_page=1&_pageSize=100&orderby=id
```

## Character Renders

```
# 3D renders of characters (no auth required, uses special URL)
https://render.worldofwarcraft.com/us/character/{thumbnail-path}
# Paths come from character profile API responses
```

## Rate Limits

- **36,000 requests/hour** per client (10 req/sec average)
- **100 requests/second** burst
- HTTP 429 on throttle — implement exponential backoff

## Client Libraries

| Language | Package | Status |
|----------|---------|--------|
| **Ruby** | [blizzard_api](https://rubygems.org/gems/blizzard_api) | ✅ Up to date |
| **Node.js** | [blizzapi](https://www.npmjs.com/package/blizzapi) | ✅ Up to date |
| **Python** | [blizzardapi2](https://pypi.org/project/blizzardapi2) | ✅ Up to date |
| **Go** | [blizzard](https://github.com/FuzzyStatic/blizzard) | ✅ Up to date |
| **C#** | [ArgentPonyWarcraftClient](https://www.nuget.org/packages/ArgentPonyWarcraftClient) | ⚠️ Partial |
| **PHP** | [blizzard_api_php](https://packagist.org/packages/francis-schiavo/blizzard_api) | ⚠️ Partial |

## FAQ

- **401 Unauthorized** — Using client credentials for profile-only endpoints; use authorization code flow
- **403/404** — Wrong namespace, region, or character hasn't logged in since an API update
- **Character data stale** — Updates only on character logout
- **Items/Spells not found** — Index endpoints only list items referenced by other endpoints; use Search
