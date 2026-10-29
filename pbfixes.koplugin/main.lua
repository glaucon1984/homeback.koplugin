--[[--
PocketBook fixes: Home button as Back, page-turn buttons that follow the
screen rotation, and no upside-down start (written for the Era Lite).

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

@module koplugin.PBFixes
--]]--

local Device = require("device")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local HOME_SETTING = "pbfixes_home_back"
local ROTATION_SETTING = "pbfixes_rotation_map"
local ORIENTATION_SETTING = "pbfixes_orientation_mode"

local PBFixes = WidgetContainer:extend{
    name = "pbfixes",
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
    if input._pbfixes_codes then
        return input._pbfixes_codes
    end
    local codes = {}
    -- pairs() only walks the device's own table, not the __index fallback,
    -- which is exactly where the "Home" entry lives on all devices.
    for code, name in pairs(input.event_map) do
        if name == "Home" then
            table.insert(codes, code)
        end
    end
    input._pbfixes_codes = codes
    return codes
end

local function isHomeEnabled()
    return G_reader_settings:nilOrTrue(HOME_SETTING)
end

local function applyHome(enabled)
    local codes = getHomeCodes()
    if #codes == 0 then
        logger.warn("PBFixes: this device has no Home key in its event map, nothing to remap")
        return false
    end
    local target = enabled and "Back" or "Home"
    for _, code in ipairs(codes) do
        Device.input.event_map[code] = target
    end
    logger.info("PBFixes: Home key(s)", codes, "now send", target)
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

-- The firmware does swap the buttons when its *own* app orientation is not
-- upright, which is the case when KOReader is started upside down (see the
-- orientation fix below, which folds that offset into the framebuffer's
-- native rotation). So KOReader must only swap for the rotation it does in
-- software: the current mode relative to that offset, as with touch.
local function relativeRotationMap()
    local map = standardRotationMap()
    return setmetatable({}, {
        __index = function(_, rota)
            local fb = Device.screen
            local native = fb.native_rotation_mode or 0
            local offset = native - (fb._pbfixes_orig_native or native)
            return map[(4 + rota - offset) % 4] or map[0]
        end,
    })
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
        logger.warn("PBFixes: this device has no key rotation map, nothing to do")
        return false
    end
    -- Keep the device's own map so the toggle can restore it.
    if not input._pbfixes_rotation_map then
        input._pbfixes_rotation_map = input.rotation_map
    end
    input.rotation_map = enabled and relativeRotationMap() or input._pbfixes_rotation_map
    logger.info("PBFixes: page-turn buttons", enabled and "follow the screen rotation" or "use the device's own rotation map")
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
    logger.warn("PBFixes: InkView", name, "not available:", result)
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
    if fb._pbfixes_orig_native == nil then
        fb._pbfixes_orig_native = fb.native_rotation_mode
    end
    local app = inkviewCall(inkview, "GetOrientation")
    local native = fb._pbfixes_orig_native
    if app == 3 then
        native = fb.DEVICE_ROTATED_UPSIDE_DOWN
    elseif app ~= 0 then
        logger.warn("PBFixes: InkView app orientation", app, "not compensated (only 0 and 3 are)")
    end
    if fb.native_rotation_mode == native then
        return false
    end
    logger.info("PBFixes:", why, "InkView app orientation", app,
        "-> KOReader native rotation", fb.native_rotation_mode, "->", native)
    fb.native_rotation_mode = native
    -- Touch coordinates arrive translated by InkView for its own orientation,
    -- so KOReader must only translate by the remainder.
    if not fb._pbfixes_orig_getTouchRotation then
        fb._pbfixes_orig_getTouchRotation = fb.getTouchRotation
    end
    if native == fb._pbfixes_orig_native then
        fb.getTouchRotation = fb._pbfixes_orig_getTouchRotation
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
        logger.warn("PBFixes: no usable G-sensor orientation, KOReader rotation left alone")
        return
    end
    if G_reader_settings:isTrue("input_ignore_gsensor") then
        logger.info("PBFixes: accelerometer events are ignored, KOReader rotation left alone")
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
        logger.warn("PBFixes: InkView not available, not syncing the orientation")
        return
    end
    local mode = orientationMode()
    local app, global, sensor = inkviewState(inkview)
    logger.info("PBFixes:", why, "mode", mode, "InkView app", app, "global", global,
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
        logger.info("PBFixes: InkView orientation set to upright, now", inkviewCall(inkview, "GetOrientation"))
        repaint = true
    end

    syncKOReaderWithSensor(sensor)

    if repaint then
        UIManager:setDirty("all", "full")
    end
    logger.info("PBFixes:", why, "done, KOReader rotation now", Device.screen:getRotationMode(),
        "native", Device.screen.native_rotation_mode)
end

-- Log every G-sensor event with InkView's state at that moment, so a wrong
-- rotation can be traced from crash.log without debug logging.
local function hookGyroEvents()
    local input = Device.input
    if Device._pbfixes_gyro_hooked then
        return
    end
    Device._pbfixes_gyro_hooked = true
    local original = input.handleMiscGyroEv
    local function logged(self, ev)
        local inkview = getInkView()
        local app, sensor
        if inkview then
            app, _, sensor = inkviewState(inkview)
        end
        logger.info("PBFixes: gyro event value", ev.value, "InkView app", app, "G-sensor", sensor,
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
    if Device._pbfixes_poll_running then
        UIManager:unschedule(pollInkViewOrientation)
        Device._pbfixes_poll_running = false
    end
end

pollInkViewOrientation = function()
    if orientationMode() ~= "compensate" then
        Device._pbfixes_poll_running = false
        return
    end
    local inkview = getInkView()
    local app = inkview and inkviewCall(inkview, "GetOrientation")
    if app ~= nil and app ~= Device._pbfixes_last_app_orientation then
        local _, _, sensor = inkviewState(inkview)
        logger.info("PBFixes: InkView app orientation changed", Device._pbfixes_last_app_orientation,
            "->", app, "G-sensor", sensor, "KOReader rotation", Device.screen:getRotationMode())
        Device._pbfixes_last_app_orientation = app
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
    if Device._pbfixes_poll_running or orientationMode() ~= "compensate" then
        return
    end
    local inkview = getInkView()
    Device._pbfixes_last_app_orientation = inkview and inkviewCall(inkview, "GetOrientation")
    Device._pbfixes_poll_running = true
    UIManager:scheduleIn(POLL_SECONDS, pollInkViewOrientation)
end

-- Runs on every plugin instance, i.e. every time the file browser or a
-- document is opened: both restore their own saved rotation (upright by
-- default) without asking the sensor, so a book opened while the device is
-- held upside down would come up upside down until the next flip. The
-- InkView compensation itself is idempotent, so re-checking it is free.
local function scheduleOrientationSync(why)
    if not Device._pbfixes_gyro_hooked then
        hookGyroEvents()
    end
    startInkViewPoll()
    -- Plugins are created before the reader restores the document's rotation
    -- (ReaderUI:init sends ReadSettings after loading the plugins) and before
    -- the screen is shown, so run once the current step is done.
    UIManager:nextTick(syncOrientation, why)
end

-------------------------------------------------------------------------------
-- Upgrade from homeback.koplugin (the plugin's name up to v0.3.1)
-------------------------------------------------------------------------------

local OLD_PLUGIN_DIR = "homeback.koplugin"

-- Settings keys of homeback.koplugin and their names here.
local MIGRATED_SETTINGS = {
    { "homeback_enabled",          HOME_SETTING },
    { "homeback_rotation_map",     ROTATION_SETTING },
    { "homeback_orientation_mode", ORIENTATION_SETTING },
}

-- True when the old plugin folder is still installed next to this one. Both
-- would then patch the same input tables (and swap the page-turn buttons
-- twice), so this plugin stands down and asks for the old folder to be removed.
local function oldPluginInstalled()
    local lfs = require("libs/libkoreader-lfs")
    local DataStorage = require("datastorage")
    local dirs = { "plugins/" .. OLD_PLUGIN_DIR, DataStorage:getDataDir() .. "/plugins/" .. OLD_PLUGIN_DIR }
    for _, dir in ipairs(dirs) do
        if lfs.attributes(dir .. "/main.lua", "mode") == "file" then
            return dir
        end
    end
    return nil
end

local function warnOldPluginInstalled(dir)
    logger.warn("PBFixes: old plugin folder", dir, "is still installed, PocketBook fixes disabled until it is removed")
    if Device._pbfixes_old_warned then
        return
    end
    Device._pbfixes_old_warned = true
    UIManager:nextTick(function()
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = _([[PocketBook fixes (pbfixes.koplugin) is the new name of homeback.koplugin.

The old folder is still installed, so this plugin does nothing yet. Please delete koreader/plugins/homeback.koplugin and restart KOReader.]]),
        })
    end)
end

-- Carry the toggles over from the old settings keys, once. An existing new
-- key wins; the old keys are removed so this is a no-op from then on.
local function migrateSettings()
    local changed = false
    for _, pair in ipairs(MIGRATED_SETTINGS) do
        local old_key, new_key = pair[1], pair[2]
        if G_reader_settings:has(old_key) then
            if not G_reader_settings:has(new_key) then
                G_reader_settings:saveSetting(new_key, G_reader_settings:readSetting(old_key))
            end
            G_reader_settings:delSetting(old_key)
            changed = true
        end
    end
    if changed then
        logger.info("PBFixes: settings migrated from homeback.koplugin")
    end
end

-------------------------------------------------------------------------------

function PBFixes:init()
    local old_dir = oldPluginInstalled()
    if old_dir then
        warnOldPluginInstalled(old_dir)
        return
    end
    migrateSettings()
    if Device:hasKeys() then
        applyHome(isHomeEnabled())
        applyRotation(isRotationEnabled())
    end
    if orientationSupported() then
        local why = self.ui.document and "reader open" or "file browser open"
        if not Device._pbfixes_orientation_started then
            Device._pbfixes_orientation_started = true
            why = "startup, " .. why
        end
        scheduleOrientationSync(why)
    end
    self.ui.menu:registerToMainMenu(self)
end

-- After a wake the firmware may have changed the task's orientation again
-- (the sleep screen is drawn the way the device lay). PocketBookPowerD's own
-- sync runs after the Resume broadcast, so re-check on the next tick.
function PBFixes:onResume()
    if orientationSupported() and orientationMode() ~= "off" then
        UIManager:nextTick(syncOrientation, "resume")
        startInkViewPoll()
    end
end

function PBFixes:onSuspend()
    stopInkViewPoll()
end

function PBFixes:onCloseWidget()
    -- The poll belongs to the process, not to this instance: a new instance
    -- (reader <-> file browser) restarts it in init.
end

function PBFixes:addToMainMenu(menu_items)
    if Device:hasKeys() and #getHomeCodes() > 0 then
        menu_items.pbfixes_home = {
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
        menu_items.pbfixes_rotation = {
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
        menu_items.pbfixes_orientation = {
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

return PBFixes
