# homeback.koplugin — Home button as Back

A tiny [KOReader](https://koreader.rocks) plugin with three fixes written
for the PocketBook Era Lite:

1. the physical **Home** button acts as the **Back** key;
2. the **page-turn buttons follow the screen rotation** on devices where
   the firmware does not swap them (the Era Lite);
3. the **screen is not upside down when KOReader is started upside down**,
   and books come up the way the device is held (Era, Era Color, Era Lite).

All three are done at runtime (KOReader's input tables, InkView calls), so no
KOReader file is edited and the changes survive KOReader updates.

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
follow the screen in every orientation. The firmware *does* swap the buttons
when its own task orientation is not upright, which is the case after an
upside-down start (next section), so the map only swaps for the rotation
KOReader does in software.

This is **on by default only on the Era Lite (PB710)**. On any other device
with buttons it is available as a toggle but off: if the firmware already
swaps the buttons, enabling it would swap them twice.

## Fix orientation when started upside down

If KOReader is started while the device is held upside down (buttons on the
left), everything is shown upside down, and turning the device does not put
it right: every flip is applied on top of a wrong starting orientation. Only
putting the device to sleep and waking it fixes it (see
[koreader/koreader#15370](https://github.com/koreader/koreader/issues/15370)
and [#16074](https://github.com/koreader/koreader/issues/16074)). A book
also always opens with the rotation it was last closed with, whichever way
the device is held now, and needs a flip to catch up.

The plugin folds the firmware's offset into KOReader's own rotation, and
brings KOReader's rotation in line with the G-sensor every time the file
browser or a book is opened. It is **on by default on the PocketBook devices
KOReader already re-syncs after resume** (Era, Era Color, Era Lite) and
available on any other PocketBook with a G-sensor. KOReader's own rotation
settings are honoured: with *Ignore accelerometer rotation events* on,
KOReader's rotation is left alone; with *Lock auto rotation to current
orientation* on, only a portrait↔portrait or landscape↔landscape correction
is applied.

Three modes are selectable, in case a firmware behaves differently:

- **Compensate the firmware's offset** (default): the fix described above,
  tested on an Era Lite with firmware 6.11.
- **Reset InkView to upright**: asks the firmware to show the task upright
  (`SetOrientation(0)`) and then syncs KOReader with the sensor. On the Era
  Lite the firmware accepts the call but the picture does not change.
- **Off (log only)**: writes what the firmware reports to `crash.log` and
  changes nothing.

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
3. Restart KOReader. All three fixes are enabled by default on the Era Lite.

## Settings

The toggles are available in the file browser and in the reader:

- *Settings → Navigation* → **Home button acts as Back** (default on). Off
  restores the normal Home behaviour. Acts at once.
- *Settings → Navigation* → **Page-turn buttons follow rotation** (default on
  for the Era Lite, off elsewhere). Off restores the device's own rotation
  map. Acts at once.
- *Settings → Screen → Rotation* → **Fix orientation when started upside
  down** (default *Compensate* for the Era, Era Color and Era Lite, *Off* on
  other PocketBooks). Takes effect at the next start.

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

On PocketBook, KOReader draws into InkView's task framebuffer and does all
the rotation itself in software, so it relies on that buffer being shown
upright. When KOReader starts while the device is held upside down, the
firmware shows the task turned 180° (InkView reports app orientation 3 for
it) and everything KOReader draws is shown turned a further 180°. Neither
`iv_update_orientation()` (what KOReader's own resume sync calls) nor the
public `SetOrientation(0)` removes that offset on the Era Lite, although
`GetOrientation()` then reports 0.

So the plugin does not fight the firmware. Whenever InkView reports app
orientation 3, it sets KOReader's framebuffer `native_rotation_mode` to
"upside down" and re-applies the current rotation mode, so the offset is
folded into KOReader's own blitbuffer rotation; touch coordinates, which
InkView already translates for its orientation, get the matching
`getTouchRotation` override, and the key rotation map (fix 2) is looked up
by the same relative rotation, because InkView swaps the page-turn buttons
itself at app orientation 3. Then it feeds the current
`GetGSensorOrientation()` through KOReader's gyro handler (`handleMiscGyroEv`
directly, because `handleGyroEv` is voided while input is inhibited, which is
the case while a book loads) so KOReader's rotation matches the way the
device is held. This runs on every plugin instance, i.e. on every file
browser and reader open, on the tick after the screen has applied its own
saved rotation, and again after resume.

When KOReader is started by the firmware to open a book (file association),
no orientation events reach KOReader at all: the firmware turns the task
itself as the device is flipped, and InkView's app orientation changes under
KOReader. The plugin therefore polls `GetOrientation()` every two seconds
(paused during sleep) and, on a change, re-folds the offset and rotates
KOReader to the new value.

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
- Page-turn buttons are wrong only after an upside-down start: that was
  v0.3.0 (double swap with the firmware); update to v0.3.1 or later.
- The screen is still upside down: `koreader/crash.log` has a
  `HomeBack: startup ... InkView app N global N G-sensor N KOReader rotation N`
  line per start, a `HomeBack: gyro event` line per sensor event, and
  `HomeBack: InkView app orientation changed` lines when the firmware turns
  the task itself. "no usable G-sensor orientation" means the sensor is off
  in the PocketBook settings or the firmware does not report it. Please open
  an issue with those lines and your device model and firmware.
- Lines starting with `HomeBack:` in `koreader/crash.log` show which key
  codes were found, what they were set to, and which rotation map is active.
  "This device has no Home key in its event map" means the device layer
  names the key differently; please open an issue with your device model.

## License

AGPL-3.0-or-later, like KOReader.
