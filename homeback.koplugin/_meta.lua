local _ = require("gettext")
return {
    fullname = _("Home button as Back"),
    version = "0.3.0",
    description = _([[Makes the physical Home button act as the Back key: go up one folder in the file browser, close dialogs and menus, and go back in the reader. Can also make the page-turn buttons follow the screen rotation on devices where the firmware does not (PocketBook Era Lite), and keep the screen the right way up when KOReader or a book is opened while the device is held upside down (PocketBook Era, Era Color, Era Lite). Toggles under Settings > Navigation and Settings > Screen > Rotation.]]),
}
