local _ = require("gettext")
return {
    fullname = _("PocketBook fixes"),
    version = "0.4.0",
    description = _([[Small fixes for PocketBook e-readers (written for the Era Lite): the physical Home button acts as the Back key (go up one folder in the file browser, close dialogs and menus, go back in the reader); the page-turn buttons follow the screen rotation on devices where the firmware does not swap them (Era Lite); and the screen is the right way up when KOReader or a book is opened while the device is held upside down (Era, Era Color, Era Lite). Toggles under Settings > Navigation and Settings > Screen > Rotation. Formerly homeback.koplugin.]]),
}
