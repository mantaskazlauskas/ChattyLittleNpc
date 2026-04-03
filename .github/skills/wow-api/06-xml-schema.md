# XML Schema (Patch 12.0.1)

> XML files define UI elements. XML is optional — most functionality is also available via Lua.
> Full reference: https://warcraft.wiki.gg/wiki/XML_schema

## Basic Structure

```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.blizzard.com/wow/ui/
        https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_SharedXML/UI.xsd">

    <Script file="MyCode.lua"/>
    <Include file="OtherFile.xml"/>

    <Frame name="MyFrame" parent="UIParent">
        <Size x="200" y="100"/>
        <Anchors>
            <Anchor point="CENTER"/>
        </Anchors>
        <Layers>
            <Layer level="ARTWORK">
                <Texture file="Interface/Icons/myicon" setAllPoints="true"/>
                <FontString name="$parentText" inherits="GameFontNormal">
                    <Anchor point="CENTER"/>
                </FontString>
            </Layer>
        </Layers>
        <Frames>
            <Button name="$parentButton" inherits="UIPanelButtonTemplate">
                <Size x="100" y="30"/>
                <Anchor point="BOTTOM" y="10"/>
                <Scripts>
                    <OnClick>
                        print("Clicked!")
                    </OnClick>
                </Scripts>
            </Button>
        </Frames>
        <Scripts>
            <OnLoad>
                self:RegisterEvent("PLAYER_ENTERING_WORLD")
            </OnLoad>
            <OnEvent function="MyFrame_OnEvent"/>
        </Scripts>
    </Frame>
</Ui>
```

## Top-Level Tags

### `<Ui>`
Root element. Encloses all other tags.

### `<Script>`
Loads or contains Lua code.
- `file` (string) — Path to a `.lua` file

### `<Include>`
Loads another XML file.
- `file` (string) — Path to a `.xml` file

## LayoutFrame Attributes (Common to most widgets)

| Attribute | Type | Description |
|-----------|------|-------------|
| `name` | string | Global name (`$parent` substitutes parent's name) |
| `parentKey` | string | Key on parent table to reference this widget |
| `parentArray` | string | Array key on parent to insert reference |
| `inherits` | string | Comma-separated virtual template names |
| `virtual` | bool | Creates a template instead of widget (requires name) |
| `mixin` | string | Comma-separated Lua mixin names |
| `secureMixin` | string | Secure Lua mixin names |
| `setAllPoints` | bool | Match parent size |
| `hidden` | bool | Initially hidden |

## LayoutFrame Child Elements

### `<Size>`
```xml
<Size x="200" y="100"/>
<!-- or -->
<Size>
    <AbsDimension x="200" y="100"/>
</Size>
```

### `<Anchors>`
```xml
<Anchors>
    <Anchor point="TOPLEFT" relativeTo="UIParent" relativePoint="TOPLEFT" x="10" y="-10"/>
    <Anchor point="BOTTOMRIGHT" x="-10" y="10"/>
</Anchors>
```

**Anchor attributes:**
| Attribute | Description |
|-----------|-------------|
| `point` | TOPLEFT, TOP, TOPRIGHT, LEFT, CENTER, RIGHT, BOTTOMLEFT, BOTTOM, BOTTOMRIGHT |
| `relativeTo` | Global name of anchor target |
| `relativeKey` | Sibling key anchor target |
| `relativePoint` | Point on target (defaults to same as `point`) |
| `x` | Horizontal offset |
| `y` | Vertical offset |

### `<KeyValues>`
```xml
<KeyValues>
    <KeyValue key="myProperty" value="hello" type="string"/>
    <KeyValue key="myNumber" value="42" type="number"/>
    <KeyValue key="myBool" value="true" type="boolean"/>
</KeyValues>
```

## Frame Attributes

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `alpha` | float | 1.0 | Opacity |
| `scale` | float | 1.0 | Size multiplier |
| `parent` | string | — | Parent frame name |
| `frameStrata` | string | PARENT | Frame strata |
| `frameLevel` | int | — | Level within strata |
| `id` | int | 0 | Frame ID |
| `toplevel` | bool | false | Render in front |
| `movable` | bool | false | Allow dragging |
| `resizable` | bool | false | Allow resizing |
| `enableMouse` | bool | false | Receive mouse input |
| `enableMouseClicks` | bool | false | Receive clicks only |
| `enableMouseMotion` | bool | false | Receive hover events |
| `enableKeyboard` | bool | false | Receive keyboard input |
| `clampedToScreen` | bool | false | Prevent off-screen |
| `clipChildren` | bool | false | Clip overflowing children |
| `hidden` | bool | false | Initially hidden |
| `protected` | bool | false | Secure frame |
| `propagateKeyboardInput` | bool | false | Pass keyboard to parent |
| `hyperlinksEnabled` | bool | false | Interactive hyperlinks |
| `intrinsic` | bool | false | Create intrinsic frame type |

## Frame Child Elements

### `<Layers>`
```xml
<Layers>
    <Layer level="BACKGROUND">
        <Texture name="$parentBG" setAllPoints="true">
            <Color r="0" g="0" b="0" a="0.5"/>
        </Texture>
    </Layer>
    <Layer level="ARTWORK">
        <FontString name="$parentTitle" inherits="GameFontNormal" text="Hello">
            <Anchor point="TOP" y="-10"/>
        </FontString>
    </Layer>
</Layers>
```

**Draw Layer values:** BACKGROUND, BORDER, ARTWORK, OVERLAY, HIGHLIGHT

### `<Frames>`
```xml
<Frames>
    <Frame name="$parentChild">
        <Size x="50" y="50"/>
        <Anchors><Anchor point="CENTER"/></Anchors>
    </Frame>
</Frames>
```

### `<Scripts>`
```xml
<Scripts>
    <OnLoad function="MyFrame_OnLoad"/>
    <OnEvent>
        if event == "PLAYER_LOGIN" then
            print("Logged in!")
        end
    </OnEvent>
    <OnShow method="OnShowHandler"/>
    <OnUpdate inherit="prepend">
        -- runs before inherited OnUpdate
    </OnUpdate>
</Scripts>
```

**Script tag attributes:**
| Attribute | Description |
|-----------|-------------|
| `function` | Global function name (instead of inline Lua) |
| `method` | Widget method name |
| `inherit` | "prepend" or "append" (hook inherited scripts) |
| `intrinsicOrder` | "precall" or "postcall" (for intrinsic frames) |

## Texture Element

```xml
<Texture name="$parentIcon" file="Interface/Icons/myicon">
    <Size x="32" y="32"/>
    <Anchors><Anchor point="LEFT" x="5"/></Anchors>
    <TexCoords left="0" right="1" top="0" bottom="1"/>
    <Color r="1" g="1" b="1" a="1"/>
</Texture>
```

| Attribute | Description |
|-----------|-------------|
| `file` | Texture file path or ID |
| `atlas` | Atlas name |
| `setAllPoints` | Match parent bounds |
| `desaturated` | Grayscale mode |
| `alphaMode` | Blend mode |

## FontString Element

```xml
<FontString name="$parentLabel" inherits="GameFontNormal" text="Hello World">
    <Anchors><Anchor point="CENTER"/></Anchors>
    <Color r="1" g="0.8" b="0"/>
    <Shadow>
        <Offset x="1" y="-1"/>
        <Color r="0" g="0" b="0" a="1"/>
    </Shadow>
</FontString>
```

## Button Element

```xml
<Button name="$parentButton" inherits="UIPanelButtonTemplate" text="Click Me">
    <Size x="120" y="30"/>
    <Anchors><Anchor point="CENTER"/></Anchors>
    <NormalTexture file="Interface/Buttons/UI-Panel-Button-Up"/>
    <PushedTexture file="Interface/Buttons/UI-Panel-Button-Down"/>
    <HighlightTexture file="Interface/Buttons/UI-Panel-Button-Highlight" alphaMode="ADD"/>
    <Scripts>
        <OnClick>print("clicked", self:GetName())</OnClick>
    </Scripts>
</Button>
```

## EditBox Element

```xml
<EditBox name="$parentInput" autoFocus="false" multiLine="false" maxLetters="100">
    <Size x="200" y="30"/>
    <Anchors><Anchor point="CENTER"/></Anchors>
    <FontString inherits="ChatFontNormal"/>
    <Scripts>
        <OnEnterPressed>
            print("Entered:", self:GetText())
            self:ClearFocus()
        </OnEnterPressed>
        <OnEscapePressed>
            self:ClearFocus()
        </OnEscapePressed>
    </Scripts>
</EditBox>
```

## Common Templates

| Template | Description |
|----------|-------------|
| `UIPanelButtonTemplate` | Standard button |
| `GameFontNormal` | Standard font |
| `GameFontHighlight` | Highlighted font |
| `GameFontNormalLarge` | Large font |
| `GameFontNormalSmall` | Small font |
| `InputBoxTemplate` | Standard edit box |
| `BackdropTemplate` | Frame with backdrop |
| `TooltipBorderBackdropTemplate` | Tooltip-style border |
| `SecureActionButtonTemplate` | Secure action button |
| `SecureUnitButtonTemplate` | Secure unit button |

## Virtual Templates

```xml
<!-- Define template -->
<Frame name="MyCustomTemplate" virtual="true">
    <Size x="100" y="50"/>
    <Layers>
        <Layer level="ARTWORK">
            <FontString parentKey="label" inherits="GameFontNormal"/>
        </Layer>
    </Layers>
</Frame>

<!-- Use template -->
<Frame inherits="MyCustomTemplate">
    <Anchors><Anchor point="CENTER"/></Anchors>
</Frame>
```

## Using VS Code for XML

Install the [Red Hat XML extension](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-xml) for validation and auto-completion with the WoW XSD schema.
