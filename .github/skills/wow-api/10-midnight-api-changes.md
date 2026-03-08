# Midnight API Changes (Patch 12.0.1)

> Patch 12.0.1 is the Midnight launch patch. TOC: 120001.
> Full reference: https://warcraft.wiki.gg/wiki/Patch_12.0.1/API_changes
> Previous: https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes

## Resources

- **Interface version**: `120001`
- **Build**: 65893 (Feb 11 2026)
- **Source diffs**: [wow-ui-source 12.0.0..12.0.1](https://github.com/Gethe/wow-ui-source/compare/12.0.0..12.0.1)
- **Official notes**: [Second Midnight Pre-Expansion Update Notes](https://worldofwarcraft.blizzard.com/en-us/news/24246298/second-midnight-pre-expansion-update-notes#item5)

## New Global APIs (59 added)

### Battle.net
```lua
C_BattleNet.SetAFK()
C_BattleNet.SetDND()
```

### Catalog Shop
```lua
C_CatalogShop.BulkRefundDecors()
C_CatalogShop.FindBestCurrencyProductForNeededAmount()
C_CatalogShop.GetVCProductInfos()
C_CatalogShop.OnLegalPersonalizedOptOutClicked()
C_CatalogShop.ShouldShowHousingWarning()
```

### Combat Audio Alerts (Accessibility)
```lua
C_CombatAudioAlert.GetCategoryVoice()
C_CombatAudioAlert.GetCategoryVolume()
C_CombatAudioAlert.SetCategoryVoice()
C_CombatAudioAlert.SetCategoryVolume()
```

### Damage Meter
```lua
C_DamageMeter.GetSessionDurationSeconds()
```

### Death Recap
```lua
C_DeathRecap.GetRecapMaxHealth()
```

### Delves
```lua
C_DelvesUI.GetPlayerCompanionPDEID()
C_DelvesUI.GetTieredEntrancePDEID()
```

### Encounter Events (Boss Mechanics)
```lua
C_EncounterEvents.GetEventColor()
C_EncounterEvents.GetEventInfo()
C_EncounterEvents.GetEventList()
C_EncounterEvents.GetEventSound()
C_EncounterEvents.HasEventInfo()
C_EncounterEvents.PlayEventSound()
C_EncounterEvents.SetEventColor()
C_EncounterEvents.SetEventSound()
```

### Encounter Timeline
```lua
C_EncounterTimeline.GetEventHighlightTime()
C_EncounterTimeline.GetEventTimer()
C_EncounterTimeline.GetSortedEventList()
C_EncounterTimeline.GetTrackMaxEventDuration()
C_EncounterTimeline.GetTrackType()
C_EncounterTimeline.GetViewType()
C_EncounterTimeline.SetViewType()
```

### Encounter Warnings
```lua
C_EncounterWarnings.GetColorForSeverity()
C_EncounterWarnings.GetPlayCustomSoundsWhenHidden()
C_EncounterWarnings.GetWarningsShown()
C_EncounterWarnings.SetPlayCustomSoundsWhenHidden()
C_EncounterWarnings.SetWarningsShown()
```

### Housing
```lua
C_Housing.IsHousingMarketCartFullRemoveEnabled()
C_HousingCatalog.GetMarketInfoForDecor()
C_HousingLayout.GetNumFloors()
```

### Housing Photo Sharing
```lua
C_HousingPhotoSharing.BeginAuthorizationFlow()
C_HousingPhotoSharing.ClearAuthorization()
C_HousingPhotoSharing.CompleteAuthorizationFlow()
C_HousingPhotoSharing.GetCropRatio()
C_HousingPhotoSharing.GetPhotoSharingAuthURL()
C_HousingPhotoSharing.IsAuthorized()
C_HousingPhotoSharing.IsEnabled()
C_HousingPhotoSharing.SetScreenshotPreviewTexture()
C_HousingPhotoSharing.TakePhoto()
C_HousingPhotoSharing.UploadPhotoToService()
```

### LFG
```lua
C_LFGList.IsPlayerValidForEndgameFieldEdits()
C_LFGList.ListingUsesEndgameEditRestrictions()
```

### Utility
```lua
C_StringUtil.StripTextureMarkupForLooseFiles()
C_TableUtil.FindIndexedMismatch()
GetNumTotemSlots()
dumpobject()  -- Debug utility
```

### Transmog
```lua
C_TransmogCollection.IsSpellItemEnchantmentHiddenVisual()
C_TransmogOutfitInfo.InTransmogEvent()
C_TransmogOutfitInfo.IsUsableDiscountAvailable()
C_TransmogOutfitInfo.SetOutfitToOutfit()
C_TransmogOutfitInfo.TransmogEventActive()
```

## Removed Global APIs (8 removed)

```lua
BNSetAFK()                        -- Replaced by C_BattleNet.SetAFK()
BNSetDND()                        -- Replaced by C_BattleNet.SetDND()
C_CombatAudioAlert.GetSpeakerVolume()  -- Replaced by GetCategoryVolume()
C_CombatAudioAlert.SetSpeakerVolume()  -- Replaced by SetCategoryVolume()
C_NamePlate.GetTargetClampingInsets()
C_NamePlate.SetTargetClampingInsets()
GetCurrentGraphicsSetting()
SetCurrentGraphicsSetting()
```

## Changed APIs

```lua
-- New argument added
C_CombatAudioAlert.SpeakText()    -- + arg 2: category
C_StringUtil.StripHyperlinks()    -- + arg 6: maintainTextures

-- Nilability changes
C_DamageMeter.GetCombatSessionSourceFromID()   -- arg 3 now Nilable; + arg 4: sourceCreatureID
C_DamageMeter.GetCombatSessionSourceFromType() -- arg 3 now Nilable; + arg 4: sourceCreatureID
C_VoiceChat.GetChannel()                       -- ret 1 Nilable: true → false
C_VoiceChat.GetChannelForChannelType()         -- ret 1 Nilable: true → false
C_VoiceChat.GetChannelForCommunityStream()     -- ret 1 Nilable: true → false

-- New return value
UnitCastingInfo()                  -- + ret 11: delayTimeMs
```

## New Widget APIs (2 added)

```lua
FontString:ClearText()            -- Clear font string text
GameTooltip:ClearPadding()        -- Clear tooltip padding
```

## New Events (11 added)

```lua
BULK_REFUND_RESULT_RECEIVED       -- result
ENCOUNTER_TIMELINE_VIEW_ACTIVATED
ENCOUNTER_TIMELINE_VIEW_DEACTIVATED
PHOTO_SHARING_AUTHORIZATION_NEEDED
PHOTO_SHARING_AUTHORIZATION_UPDATED
PHOTO_SHARING_PHOTO_UPLOAD_STATUS
PHOTO_SHARING_SCREENSHOT_READY
PHOTO_SHARING_THIRD_PARTY_AUTHORIZATION_NEEDED
PLAYER_MAX_LEVEL_UPDATE
SIMPLE_BROWSER_POPUP              -- url
SIMPLE_BROWSER_SOCIAL_CALLBACK_INVOKED  -- url
```

## Removed Events (1 removed)

```lua
CHAT_MSG_ENCOUNTER_EVENT          -- Removed
```

## Changed Events

```lua
BULK_PURCHASE_RESULT_RECEIVED     -- + arg 3: bestTopUpProductID, + arg 4: totalCost
HOUSING_CLEANUP_MODE_HOVERED_TARGET_CHANGED  -- + arg 2: targetType
```

## New CVars (32 added)

### Combat Audio Alert CVars
```
CAADebuffSelfAlert, CAAPartyHealthVoice, CAAPartyHealthVolume,
CAAPlayerCastVoice, CAAPlayerCastVolume, CAAPlayerHealthVoice,
CAAPlayerHealthVolume, CAAResource1Voice, CAAResource1Volume,
CAAResource2Voice, CAAResource2Volume, CAASayYourDebuffs,
CAASayYourDebuffsFormat, CAASayYourDebuffsMinDuration,
CAASayYourDebuffsVoice, CAASayYourDebuffsVolume,
CAATargetCastVoice, CAATargetCastVolume,
CAATargetHealthVoice, CAATargetHealthVolume
```

### Other New CVars
```
damageMeterResetOnNewInstance, enableConnectToPhotoSharing,
encounterTimelineHighlightDuration, encounterTimelineShowSequenceCount,
highestUnlockedTieredEntranceTier, imageSharingPublishCooldown,
lastLockedTieredEntranceCompanionAbilities, lastSelectedTieredEntranceTier,
nameplateSimplifiedScale, nameplateUseClassColorForFriendlyPlayerUnitNames,
raidFramesHealthBarColorBG, seenPurchasableClassCapstone
```

## Removed CVars (25 removed)

Including: `activeCUFProfile`, `guildRosterView`, `highestUnlockedDelvesTier`, `lastLockedDelvesCompanionAbilities`, `lastSelectedDelvesTier`, and various nameplate-related CVars.

## Key Takeaways for Addon Development

1. **UnitCastingInfo now returns delayTimeMs** — useful for cast bar addons
2. **Encounter Events/Timeline/Warnings** — New systems for boss encounter UI
3. **Housing Photo Sharing** — Entirely new system
4. **Combat Audio Alerts expanded** — Accessibility improvements with per-category voice/volume
5. **Delves tiered entrance** — Replaces the old delves tier system
6. **FontString:ClearText()** — More efficient than SetText("")
7. **CHAT_MSG_ENCOUNTER_EVENT removed** — Boss encounter events restructured
