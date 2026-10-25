# homeback.koplugin — Home button as Back

A tiny [KOReader](https://koreader.rocks) plugin that makes the physical
**Home** button act as the **Back** key:

| Where | What Home does with the plugin |
|---|---|
| File browser | goes up one folder (instead of jumping to the home folder) |
| Menus and dialogs | closes them, or steps back to the parent menu |
| Reader | whatever *Settings → Navigation → Back in reader* is set to (previous location, file browser, …) |

It was written for the PocketBook Era Lite, where KOReader has no key bound
to Back and getting out of a deep folder means paging back to the top
(see [koreader/koreader#14058](https://github.com/koreader/koreader/issues/14058)).
It should work on any device whose KOReader event map has a `Home` key
(other PocketBooks, Kobo, Kindle), but only PocketBook has been tested.

The remap is done at runtime, in KOReader's input event map, so no KOReader
file is edited and the change survives KOReader updates.

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
3. Restart KOReader. The plugin is enabled by default.

## Settings

*Settings → Navigation → Home button acts as Back* (both in the file browser
and in the reader) toggles the remap. Turning it off restores the normal
Home behaviour at once; the help text of the item repeats this.

## How it works

KOReader's device layer maps raw key codes to key names in
`Device.input.event_map`; on PocketBook the Home press arrives as code
`-26` and is mapped to `"Home"`. The plugin finds every entry mapped to
`"Home"` when it starts and rewrites it to `"Back"` (or back to `"Home"`
when toggled off). Because the map is consulted on every key event, every
widget that handles Back — file chooser, menus, dialogs, the reader's Back
module — gets the press, including dialogs stacked on top of the current
screen.

### Alternative without a plugin

KOReader can also load a user key map from `koreader/settings/event_map.lua`
at start-up. A file containing

```lua
return { [-26] = "Back" }
```

does the same remap permanently (no toggle); the settings folder survives
updates too. The plugin exists for the menu toggle and for devices with a
different Home key code.

## Troubleshooting

- Nothing happens when pressing Home on a PocketBook: check step 2 above.
- Lines starting with `HomeBack:` in `koreader/crash.log` show which key
  codes were found and what they were set to. "This device has no Home key
  in its event map" means the device layer names the key differently; please
  open an issue with your device model.

## License

AGPL-3.0-or-later, like KOReader.
