--[[--
Home button as Back.

Remaps the physical "Home" key to KOReader's "Back" key by editing the
device's input event map at runtime, so no KOReader file has to be patched
and the change survives updates.

Works on any device whose event map contains a "Home" key (PocketBook,
Kobo, Kindle, ...). On PocketBook the firmware must be set to pass the
Home press to the running app (set the Home single-press action to
"none" in the PocketBook settings if KOReader does not react to it).

@module koplugin.HomeBack
--]]--

local Device = require("device")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local SETTING = "homeback_enabled"

local HomeBack = WidgetContainer:extend{
    name = "homeback",
    is_doc_only = false,
}

-- Returns the list of raw key codes that the device maps to "Home".
-- The list is stashed on the (process-wide) input object the first time we
-- look, so that later instances still know the codes after we renamed them.
local function getHomeCodes()
    local input = Device.input
    if not input or not input.event_map then
        return {}
    end
    if input._homeback_codes then
        return input._homeback_codes
    end
    local codes = {}
    -- pairs() only walks the device's own table, not the __index fallback,
    -- which is exactly where the "Home" entry lives on all devices.
    for code, name in pairs(input.event_map) do
        if name == "Home" then
            table.insert(codes, code)
        end
    end
    input._homeback_codes = codes
    return codes
end

local function isEnabled()
    return G_reader_settings:nilOrTrue(SETTING)
end

local function apply(enabled)
    local codes = getHomeCodes()
    if #codes == 0 then
        logger.warn("HomeBack: this device has no Home key in its event map, nothing to remap")
        return false
    end
    local target = enabled and "Back" or "Home"
    for _, code in ipairs(codes) do
        Device.input.event_map[code] = target
    end
    logger.info("HomeBack: Home key(s)", codes, "now send", target)
    return true
end

function HomeBack:init()
    if not Device:hasKeys() then
        return
    end
    apply(isEnabled())
    self.ui.menu:registerToMainMenu(self)
end

function HomeBack:addToMainMenu(menu_items)
    if #getHomeCodes() == 0 then
        return
    end
    menu_items.homeback = {
        text = _("Home button acts as Back"),
        sorting_hint = "navigation",
        help_text = _([[When enabled, the physical Home button sends the Back key instead of Home: it goes up one folder in the file browser, closes menus and dialogs, and in the reader does whatever "Back in reader" is set to.

Disable to restore the default Home behaviour.]]),
        checked_func = isEnabled,
        callback = function()
            G_reader_settings:flipNilOrTrue(SETTING)
            apply(isEnabled())
        end,
    }
end

return HomeBack
