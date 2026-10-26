--[[--
Home button as Back (and other small fixes for the PocketBook Era Lite).

Three small fixes, all done at runtime (KOReader's input tables, InkView
calls) so that no KOReader file has to be patched and the changes survive
updates:

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

3. KOReader started while the device is held upside down does not stay
   upside down whichever way it is turned. Default on for the PocketBook
   devices that already get an orientation sync after resume (Era, Era
   Color, Era Lite), see https://github.com/koreader/koreader/issues/15370
   and https://github.com/koreader/koreader/issues/16074.

@module koplugin.HomeBack
--]]--

local Device = require("device")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local HOME_SETTING = "homeback_enabled"
local ROTATION_SETTING = "homeback_rotation_map"
local ORIENTATION_SETTING = "homeback_orientation_mode"

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
-- Screen not upside down when KOReader is started upside down
-------------------------------------------------------------------------------

-- On PocketBook, KOReader draws into InkView's task framebuffer and does all
-- the rotation itself in software, so it relies on its buffer being shown
-- upright. When KOReader is started while the device is held upside down the
-- firmware shows the task turned 180° (InkView reports app orientation 3,
-- "portrait 180", for it), and everything KOReader draws is shown turned a
-- further 180°. Every later flip is applied on top of that fixed offset, so
-- turning the device never puts the screen right.
--
-- Tested on an Era Lite (FW 6.11): neither iv_update_orientation() (what
-- PocketBookPowerD:afterResume() calls) nor the public SetOrientation(0)
-- removes that offset for KOReader's buffer, although GetOrientation() then
-- reports 0. So the default mode here does not fight the firmware: it tells
-- KOReader's framebuffer that "upside down" is the native orientation of the
-- panel while InkView reports app orientation 3, which folds the offset into
-- KOReader's own rotation (and touch translation) maths, then brings
-- KOReader's rotation in line with the G-sensor through the gyro handler.
-- This happens on every file browser / reader open (both restore their own
-- saved rotation without asking the sensor) and after resume. When KOReader
-- is started by the firmware to open a book, no orientation events arrive at
-- all and the firmware turns the task itself, so InkView's app orientation
-- is also polled and every change is folded in the same way.

-- Modes:
--   "compensate": fold the offset into KOReader's native rotation (default)
--   "inkview0":   SetOrientation(0) on InkView, then sync KOReader
--   "off":        only log what InkView reports
local ORIENTATION_MODES = { "compensate", "inkview0", "off" }

-- Public InkView API that KOReader's ffi/inkview_h.lua does not declare.
-- (0 = portrait, 1 = landscape 90, 2 = landscape 270, 3 = portrait 180.)
local function declareInkViewOrientationApi(ffi)
    pcall(ffi.cdef, [[
int GetOrientation();
void SetOrientation(int);
int GetGlobalOrientation();
]])
end

-- Calls an InkView function by name; nil when it is not available on this
-- firmware (missing declaration or symbol).
local function inkviewCall(inkview, name, ...)
    local ok, result = pcall(function(...) return inkview[name](...) end, ...)
    if ok then
        return result
    end
    logger.warn("HomeBack: InkView", name, "not available:", result)
    return nil
end

local function orientationSupported()
    return Device:isPocketBook() and Device:hasGSensor()
        and Device.input ~= nil and Device.input.input ~= nil
        and type(Device.input.input.translateInkViewOrientation) == "function"
end

-- Devices KOReader itself re-syncs after resume: the ones whose orientation
-- baseline is known to drift.
local function orientationDefault()
    return Device.needs_orientation_sync_after_resume == true
end

local function orientationMode()
    local value = G_reader_settings:readSetting(ORIENTATION_SETTING)
    if value == nil then
        return orientationDefault() and "compensate" or "off"
    end
    for _, mode in ipairs(ORIENTATION_MODES) do
        if value == mode then
            return mode
        end
    end
    return "off"
end

local function getInkView()
    local ok, inkview = pcall(require, "ffi/inkview")
    if not ok then
        return nil
    end
    declareInkViewOrientationApi(require("ffi"))
    return inkview
end

local function inkviewState(inkview)
    return inkviewCall(inkview, "GetOrientation"),
           inkviewCall(inkview, "GetGlobalOrientation"),
           inkviewCall(inkview, "GetGSensorOrientation")
end

-- Translate an InkView orientation to KOReader's rotation constants; nil for
-- anything else (sensor off, not supported).
local function toRotation(inkview_orientation)
    if type(inkview_orientation) ~= "number" or inkview_orientation < 0 or inkview_orientation > 3 then
        return nil
    end
    return Device.input.input.translateInkViewOrientation(inkview_orientation)
end

-- "compensate": make KOReader treat InkView's current app orientation as the
-- panel's native orientation. Only the 180° case is handled: the Era family
-- is portrait-only and a landscape native rotation would need a re-layout.
-- Returns true when something changed.
local function compensateInkViewOrientation(inkview, why)
    local fb = Device.screen
    if fb._homeback_orig_native == nil then
        fb._homeback_orig_native = fb.native_rotation_mode
    end
    local app = inkviewCall(inkview, "GetOrientation")
    local native = fb._homeback_orig_native
    if app == 3 then
        native = fb.DEVICE_ROTATED_UPSIDE_DOWN
    elseif app ~= 0 then
        logger.warn("HomeBack: InkView app orientation", app, "not compensated (only 0 and 3 are)")
    end
    if fb.native_rotation_mode == native then
        return false
    end
    logger.info("HomeBack:", why, "InkView app orientation", app,
        "-> KOReader native rotation", fb.native_rotation_mode, "->", native)
    fb.native_rotation_mode = native
    -- Touch coordinates arrive translated by InkView for its own orientation,
    -- so KOReader must only translate by the remainder.
    if not fb._homeback_orig_getTouchRotation then
        fb._homeback_orig_getTouchRotation = fb.getTouchRotation
    end
    if native == fb._homeback_orig_native then
        fb.getTouchRotation = fb._homeback_orig_getTouchRotation
    else
        fb.getTouchRotation = function(self)
            return (4 + self:getRotationMode() - self.native_rotation_mode) % 4
        end
    end
    -- Re-apply the current rotation mode so the blitbuffer picks up the new
    -- native orientation.
    fb:setRotationMode(fb:getRotationMode())
    return true
end

-- Bring KOReader's own rotation in line with an InkView orientation value,
-- through the gyro handler so "Lock auto rotation" is honoured like for a
-- real event. handleMiscGyroEv is called directly rather than handleGyroEv:
-- the latter is voided while input is inhibited, which is the case while a
-- document is being opened, exactly when this needs to run. The "Ignore
-- accelerometer rotation events" setting is checked by hand instead.
local function syncKOReaderWithSensor(sensor)
    local gyro_value = toRotation(sensor)
    if gyro_value == nil then
        logger.warn("HomeBack: no usable G-sensor orientation, KOReader rotation left alone")
        return
    end
    if G_reader_settings:isTrue("input_ignore_gsensor") then
        logger.info("HomeBack: accelerometer events are ignored, KOReader rotation left alone")
        return
    end
    local ev = Device.input:handleMiscGyroEv({ value = gyro_value })
    if ev then
        UIManager:sendEvent(ev)
    end
end

local function syncOrientation(why)
    local inkview = getInkView()
    if not inkview then
        logger.warn("HomeBack: InkView not available, not syncing the orientation")
        return
    end
    local mode = orientationMode()
    local app, global, sensor = inkviewState(inkview)
    logger.info("HomeBack:", why, "mode", mode, "InkView app", app, "global", global,
        "G-sensor", sensor, "KOReader rotation", Device.screen:getRotationMode(),
        "native", Device.screen.native_rotation_mode)
    if mode == "off" then
        return
    end

    local repaint = false
    if mode == "compensate" then
        repaint = compensateInkViewOrientation(inkview, why)
    elseif mode == "inkview0" and app ~= nil and app ~= 0 then
        inkviewCall(inkview, "SetOrientation", 0)
        logger.info("HomeBack: InkView orientation set to upright, now", inkviewCall(inkview, "GetOrientation"))
        repaint = true
    end

    syncKOReaderWithSensor(sensor)

    if repaint then
        UIManager:setDirty("all", "full")
    end
    logger.info("HomeBack:", why, "done, KOReader rotation now", Device.screen:getRotationMode(),
        "native", Device.screen.native_rotation_mode)
end

-- Log every G-sensor event with InkView's state at that moment, so a wrong
-- rotation can be traced from crash.log without debug logging.
local function hookGyroEvents()
    local input = Device.input
    if Device._homeback_gyro_hooked then
        return
    end
    Device._homeback_gyro_hooked = true
    local original = input.handleMiscGyroEv
    local function logged(self, ev)
        local inkview = getInkView()
        local app, sensor
        if inkview then
            app, _, sensor = inkviewState(inkview)
        end
        logger.info("HomeBack: gyro event value", ev.value, "InkView app", app, "G-sensor", sensor,
            "KOReader rotation", Device.screen:getRotationMode(), "native", Device.screen.native_rotation_mode)
        return original(self, ev)
    end
    input.handleMiscGyroEv = logged
    -- handleGyroEv is a copy of handleMiscGyroEv made at init (or voidEv when
    -- the accelerometer is ignored); keep the toggle logic's identity checks working.
    if input.handleGyroEv == original then
        input.handleGyroEv = logged
    end
end

-- When KOReader is started by the firmware to open a book (file association)
-- no orientation events reach KOReader at all; the firmware turns the task
-- itself as the device is flipped, and InkView's app orientation changes
-- under KOReader. Poll it and fold every change into KOReader's rotation.
-- One FFI call every two seconds; paused while suspended.
local POLL_SECONDS = 2
local pollInkViewOrientation -- forward declaration, it re-schedules itself

local function stopInkViewPoll()
    if Device._homeback_poll_running then
        UIManager:unschedule(pollInkViewOrientation)
        Device._homeback_poll_running = false
    end
end

pollInkViewOrientation = function()
    if orientationMode() ~= "compensate" then
        Device._homeback_poll_running = false
        return
    end
    local inkview = getInkView()
    local app = inkview and inkviewCall(inkview, "GetOrientation")
    if app ~= nil and app ~= Device._homeback_last_app_orientation then
        local _, _, sensor = inkviewState(inkview)
        logger.info("HomeBack: InkView app orientation changed", Device._homeback_last_app_orientation,
            "->", app, "G-sensor", sensor, "KOReader rotation", Device.screen:getRotationMode())
        Device._homeback_last_app_orientation = app
        local repaint = compensateInkViewOrientation(inkview, "InkView orientation changed:")
        -- InkView has just measured the device, so its value is the live one.
        syncKOReaderWithSensor(app)
        if repaint then
            UIManager:setDirty("all", "full")
        end
    end
    UIManager:scheduleIn(POLL_SECONDS, pollInkViewOrientation)
end

local function startInkViewPoll()
    if Device._homeback_poll_running or orientationMode() ~= "compensate" then
        return
    end
    local inkview = getInkView()
    Device._homeback_last_app_orientation = inkview and inkviewCall(inkview, "GetOrientation")
    Device._homeback_poll_running = true
    UIManager:scheduleIn(POLL_SECONDS, pollInkViewOrientation)
end

-- Runs on every plugin instance, i.e. every time the file browser or a
-- document is opened: both restore their own saved rotation (upright by
-- default) without asking the sensor, so a book opened while the device is
-- held upside down would come up upside down until the next flip. The
-- InkView compensation itself is idempotent, so re-checking it is free.
local function scheduleOrientationSync(why)
    if not Device._homeback_gyro_hooked then
        hookGyroEvents()
    end
    startInkViewPoll()
    -- Plugins are created before the reader restores the document's rotation
    -- (ReaderUI:init sends ReadSettings after loading the plugins) and before
    -- the screen is shown, so run once the current step is done.
    UIManager:nextTick(syncOrientation, why)
end

-------------------------------------------------------------------------------

function HomeBack:init()
    if Device:hasKeys() then
        applyHome(isHomeEnabled())
        applyRotation(isRotationEnabled())
    end
    if orientationSupported() then
        local why = self.ui.document and "reader open" or "file browser open"
        if not Device._homeback_orientation_started then
            Device._homeback_orientation_started = true
            why = "startup, " .. why
        end
        scheduleOrientationSync(why)
    end
    self.ui.menu:registerToMainMenu(self)
end

-- After a wake the firmware may have changed the task's orientation again
-- (the sleep screen is drawn the way the device lay). PocketBookPowerD's own
-- sync runs after the Resume broadcast, so re-check on the next tick.
function HomeBack:onResume()
    if orientationSupported() and orientationMode() ~= "off" then
        UIManager:nextTick(syncOrientation, "resume")
        startInkViewPoll()
    end
end

function HomeBack:onSuspend()
    stopInkViewPoll()
end

function HomeBack:onCloseWidget()
    -- The poll belongs to the process, not to this instance: a new instance
    -- (reader <-> file browser) restarts it in init.
end

function HomeBack:addToMainMenu(menu_items)
    if Device:hasKeys() and #getHomeCodes() > 0 then
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
    if Device:hasKeys() and Device.input and Device.input.rotation_map then
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
    if orientationSupported() then
        local function modeItem(mode, text)
            return {
                text = text,
                radio = true,
                checked_func = function() return orientationMode() == mode end,
                callback = function()
                    G_reader_settings:saveSetting(ORIENTATION_SETTING, mode)
                end,
            }
        end
        menu_items.homeback_orientation = {
            text = _("Fix orientation when started upside down"),
            sorting_hint = "screen_rotation",
            help_text = _([[On some PocketBook devices (Era, Era Color, Era Lite), KOReader started while the device is held upside down shows everything upside down, and turning the device does not put it right.

"Compensate" folds the firmware's 180° offset into KOReader's own rotation. "Reset InkView" asks the firmware to show the screen upright instead. "Off" only logs what the firmware reports. Takes effect at the next start. "Ignore accelerometer rotation events" and "Lock auto rotation" are honoured.]]),
            sub_item_table = {
                modeItem("compensate", _("Compensate the firmware's offset")),
                modeItem("inkview0", _("Reset InkView to upright")),
                modeItem("off", _("Off (log only)")),
            },
        }
    end
end

return HomeBack
