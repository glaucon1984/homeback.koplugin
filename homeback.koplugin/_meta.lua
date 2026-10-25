local _ = require("gettext")
return {
    fullname = _("Home button as Back"),
    version = "0.2.0",
    description = _([[Makes the physical Home button act as the Back key: go up one folder in the file browser, close dialogs and menus, and go back in the reader. Can also make the page-turn buttons follow the screen rotation on devices where the firmware does not (PocketBook Era Lite). Both toggles are under Settings > Navigation.]]),
}
