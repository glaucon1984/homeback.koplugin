--[[--
Home button as Back (and page-turn buttons that follow rotation).

Two small fixes for devices with physical buttons, both done by editing
KOReader's input tables at runtime so that no KOReader file has to be
patched and the changes survive updates:

1. The physical "Home" key is remapped to KOReader's "Back" key.
   Works on any device whose event map contains a "Home" key (PocketBook,
   Kobo, Kindle, ...). On PocketBook the firmware must be set to pass the
   Home press to the running app (set the Home short-press action to
   "none" in the PocketBook settings).

2. KOReader's standard key rotation map (which swaps the page-turn and
   cursor keys when the screen is rotated) is restored on devices whose
   device layer disabled it although the firmware does not swap the keys
   itself. Default on for the PocketBook Era Lite (PB710), see
   https://github.com/koreader/koreader/issues/15909.

@module koplugin.HomeBack
--]]--

local Device = require("device")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local HOME_SETTING = "homeback_enabled"
local ROTATION_SETTING = "homeback_rotation_map"

local HomeBack = WidgetContainer:extend{
    name = "homeback",
    is_doc_only = false,
}

-------------------------------------------------------------------------------
-- Home -> Back
-------------------------------------------------------------------------------

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

local function isHomeEnabled()
    return G_reader_settings:nilOrTrue(HOME_SETTING)
end

local function applyHome(enabled)
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

-------------------------------------------------------------------------------
-- Page-turn buttons follow the screen rotation
-------------------------------------------------------------------------------

-- Same table as Input:init() builds when the device does not call
-- Input:disableRotationMap() (frontend/device/input.lua).
local function standardRotationMap()
    local framebuffer = require("ffi/framebuffer")
    return {
        [framebuffer.DEVICE_ROTATED_UPRIGHT]           = {},
        [framebuffer.DEVICE_ROTATED_CLOCKWISE]         = { Up = "Right", Right = "Down", Down = "Left",  Left = "Up",    LPgBack = "LPgFwd",  LPgFwd  = "LPgBack", RPgBack = "RPgFwd",  RPgFwd  = "RPgBack" },
        [framebuffer.DEVICE_ROTATED_UPSIDE_DOWN]       = { Up = "Down",  Right = "Left", Down = "Up",    Left = "Right", LPgFwd  = "LPgBack", LPgBack = "LPgFwd",  RPgFwd  = "RPgBack", RPgBack = "RPgFwd" },
        [framebuffer.DEVICE_ROTATED_COUNTER_CLOCKWISE] = { Up = "Left",  Right = "Up",   Down = "Right", Left = "Down" },
    }
end

-- Devices whose device layer disables KOReader's rotation map although the
-- firmware does not swap the buttons itself.
local function rotationDefault()
    return Device:isPocketBook() and Device.model == "PB710"
end

local function isRotationEnabled()
    local value = G_reader_settings:readSetting(ROTATION_SETTING)
    if value == nil then
        return rotationDefault()
    end
    return value == true
end

local function applyRotation(enabled)
    local input = Device.input
    if not input or not input.rotation_map then
        logger.warn("HomeBack: this device has no key rotation map, nothing to do")
        return false
    end
    -- Keep the device's own map so the toggle can restore it.
    if not input._homeback_rotation_map then
        input._homeback_rotation_map = input.rotation_map
    end
    input.rotation_map = enabled and standardRotationMap() or input._homeback_rotation_map
    logger.info("HomeBack: page-turn buttons", enabled and "follow the screen rotation" or "use the device's own rotation map")
    return true
end

-------------------------------------------------------------------------------

function HomeBack:init()
    if not Device:hasKeys() then
        return
    end
    applyHome(isHomeEnabled())
    applyRotation(isRotationEnabled())
    self.ui.menu:registerToMainMenu(self)
end

function HomeBack:addToMainMenu(menu_items)
    if #getHomeCodes() > 0 then
        menu_items.homeback = {
            text = _("Home button acts as Back"),
            sorting_hint = "navigation",
            help_text = _([[When enabled, the physical Home button sends the Back key instead of Home: it goes up one folder in the file browser, closes menus and dialogs, and in the reader does whatever "Back in reader" is set to.

Disable to restore the default Home behaviour.]]),
            checked_func = isHomeEnabled,
            callback = function()
                G_reader_settings:flipNilOrTrue(HOME_SETTING)
                applyHome(isHomeEnabled())
            end,
        }
    end
    if Device.input and Device.input.rotation_map then
        menu_items.homeback_rotation = {
            text = _("Page-turn buttons follow rotation"),
            sorting_hint = "navigation",
            help_text = _([[KOReader normally swaps the page-turn (and cursor) buttons when the screen is rotated, but on some devices it leaves that to the firmware, which may not do it (PocketBook Era Lite). When enabled, KOReader's own rotation map is used so the buttons always follow the screen.

If your device already swaps the buttons by itself, this makes them swap twice: turn it off then.]]),
            checked_func = isRotationEnabled,
            callback = function()
                G_reader_settings:saveSetting(ROTATION_SETTING, not isRotationEnabled())
                applyRotation(isRotationEnabled())
            end,
        }
    end
end

return HomeBack
