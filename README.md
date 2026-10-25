# homeback.koplugin — Home button as Back

A tiny [KOReader](https://koreader.rocks) plugin with two fixes for devices
with physical buttons, written for the PocketBook Era Lite:

1. the physical **Home** button acts as the **Back** key;
2. the **page-turn buttons follow the screen rotation** on devices where
   the firmware does not swap them (the Era Lite).

Both are done at runtime, in KOReader's input tables, so no KOReader file is
edited and the changes survive KOReader updates.

## Home button as Back

| Where | What Home does with the plugin |
|---|---|
| File browser | goes up one folder (instead of jumping to the home folder) |
| Menus and dialogs | closes them, or steps back to the parent menu |
| Reader | whatever *Settings → Navigation → Back in reader* is set to (previous location, file browser, …) |

On the Era Lite KOReader has no key bound to Back, so getting out of a deep
folder means paging back to the top
(see [koreader/koreader#14058](https://github.com/koreader/koreader/issues/14058)).
It should work on any device whose KOReader event map has a `Home` key
(other PocketBooks, Kobo, Kindle), but only PocketBook has been tested.

## Page-turn buttons follow rotation

When the screen is rotated, KOReader normally swaps the page-turn (and
cursor) keys so that "top button = back" stays true. On the Era Lite the
device layer tells KOReader that the firmware does the swapping, which it
does not, so after a 180° flip the buttons keep their upright meaning
(see [koreader/koreader#15909](https://github.com/koreader/koreader/issues/15909)).
The plugin restores KOReader's standard key rotation map, so the buttons
follow the screen in every orientation.

This is **on by default only on the Era Lite (PB710)**. On any other device
with buttons it is available as a toggle but off: if the firmware already
swaps the buttons, enabling it would swap them twice.

## Install

1. Download `homeback.koplugin.zip` from the
   [latest release](https://github.com/glaucon1984/homeback.koplugin/releases/latest)
   and unzip it into `koreader/plugins/` on the device, so that
   `koreader/plugins/homeback.koplugin/main.lua` exists
   (on a PocketBook that is `applications/koreader/plugins/`).
2. **PocketBook only:** the firmware must let the Home press reach KOReader.
   In the PocketBook's own settings, set the Home button's **short press
   action to "none"** (Settings → Personal settings → Key mapping, or the
   equivalent in your firmware version; the long press keeps its firmware
   function). Without this the firmware handles the button itself and
   KOReader never sees it. This was required on the Era Lite.
3. Restart KOReader. Both fixes are enabled by default on the Era Lite.

## Settings

Both toggles live under *Settings → Navigation*, in the file browser and in
the reader, and act at once:

- **Home button acts as Back** (default on). Off restores the normal Home
  behaviour.
- **Page-turn buttons follow rotation** (default on for the Era Lite, off
  elsewhere). Off restores the device's own rotation map.

## How it works

KOReader's device layer maps raw key codes to key names in
`Device.input.event_map`; on PocketBook the Home press arrives as code
`-26` and is mapped to `"Home"`. The plugin finds every entry mapped to
`"Home"` when it starts and rewrites it to `"Back"` (or back to `"Home"`
when toggled off). Because the map is consulted on every key event, every
widget that handles Back — file chooser, menus, dialogs, the reader's Back
module — gets the press, including dialogs stacked on top of the current
screen.

After that lookup, `input.lua` passes the key name through
`Device.input.rotation_map[<current rotation>]`. Devices flagged with
`inkview_translates_buttons` get an empty map from
`Input:disableRotationMap()`; the plugin replaces it with the standard map
that `Input:init()` builds for every other device (the same table as the
user patch from the issue above), and keeps the device's own map so the
toggle can put it back.

### Alternative without a plugin

KOReader can also load a user key map from `koreader/settings/event_map.lua`
at start-up. A file containing

```lua
return { [-26] = "Back" }
```

does the Home remap permanently (no toggle); the settings folder survives
updates too. The rotation fix has no settings-file equivalent, but it can be
done with a user patch in `koreader/patches/` as shown in the issue.

## Troubleshooting

- Nothing happens when pressing Home on a PocketBook: check step 2 above.
- Page-turn buttons swap twice after rotating: your device swaps them in
  firmware already; turn *Page-turn buttons follow rotation* off.
- Lines starting with `HomeBack:` in `koreader/crash.log` show which key
  codes were found, what they were set to, and which rotation map is active.
  "This device has no Home key in its event map" means the device layer
  names the key differently; please open an issue with your device model.

## License

AGPL-3.0-or-later, like KOReader.
