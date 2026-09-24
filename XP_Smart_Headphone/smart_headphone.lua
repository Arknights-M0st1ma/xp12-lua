--[[
    Smart Headphone for X-Plane 12
    ==============================
    A "noise cancelling headphone" for the cockpit: hit one hotkey and the
    low-frequency drone (engine / prop / wind) fades away, while radio, voices
    and warnings stay at full volume -- the way a real ANR headset feels.

    WHAT IT REALLY DOES  (read this once)
    FlyWithLua cannot touch X-Plane's audio mixer or its sample stream, so a
    real low-frequency filter cannot be patched into the sound output from
    Lua. What IS available is X-Plane's own sound-channel volumes -- the
    sliders in Settings -> Sound -- and the engine drone lives in the
    interior / exterior aircraft channels. So this script approximates ANR by
    fading down the channels that carry the drone and leaving the channels
    that carry information alone:

        faded down : interior aircraft  (the drone you hear in the cockpit)
                     exterior aircraft  (the engine as heard from outside)
                     environment        (wind / rain rumble)
        untouched  : radio (ATC + voices), copilot, UI

    How deep each channel is cut is set per channel in CONFIG below.
    Genuine low-frequency filtering needs a system EQ (Equalizer APO,
    Voicemeeter, ...) -- see the README.

    HOTKEY
    Bind any key or joystick button yourself in
    Settings -> Keyboard / Joystick, search "smartheadphone":
        FlyWithLua/smart_headphone/toggle   <- the one you normally bind
        FlyWithLua/smart_headphone/on
        FlyWithLua/smart_headphone/off
        FlyWithLua/smart_headphone/reset    <- escape hatch: full volume back

    STATE
    The on/off state plus your own volume mix is remembered in
    %APPDATA%\xplane_smart_headphone.state, so a FlyWithLua script reload
    (X-Plane reloads scripts on every aircraft load) neither loses "ANR on"
    nor strands the sound sliders at the faded level.

    Author: built with Codex. License: MIT, same as this repo.
]]

-- ===========================================================================
-- CONFIG -- everything you might want to change lives in this block
-- ===========================================================================

local FADE_SECS         = 0.8    -- ramp when you toggle (0 = snap instantly)
local RESTORE_FADE_SECS = 0.4    -- ramp when a saved "ANR on" state is restored
local REARM_SECS        = 0.4    -- how long the toggle must be quiet before the
                                 -- next press counts (swallows auto-repeat and
                                 -- a held key, so one press is one toggle)
local SHOW_TOAST        = true   -- brief on-screen "ANR on / off" message
local TOAST_SECS        = 2.0
local TOAST_X, TOAST_Y  = 20, 120
local DEFAULT_LEVEL     = 1.0    -- level the /reset command restores
local STATE_FILE        = "xplane_smart_headphone.state"

-- factor = how much of that channel survives while ANR is on.
-- 1.00 = untouched, 0.50 = -6 dB, 0.25 = -12 dB, 0.15 = -16 dB, 0.10 = -20 dB.
-- A channel that does not exist in your build is simply skipped (see the log),
-- and factor = 1.0 is a way to switch a channel off.
local CHANNELS = {
    { path = "sim/operation/sound/interior_volume_ratio",    factor = 0.20 },
    { path = "sim/operation/sound/exterior_volume_ratio",    factor = 0.15 },
    { path = "sim/operation/sound/environment_volume_ratio", factor = 0.50 },
    -- Dedicated engine / prop channels. Not every X-Plane build has them;
    -- listed anyway because this script checks before it binds.
    { path = "sim/operation/sound/engine_volume_ratio",      factor = 0.15 },
    { path = "sim/operation/sound/prop_volume_ratio",        factor = 0.15 },
}

-- ===========================================================================
-- Binding a sound channel
-- ===========================================================================

local function clamp01(v)
    if v < 0 then return 0 elseif v > 1 then return 1 end
    return v
end

-- FlyWithLua builds differ in which low-level XPLM functions they expose, so
-- try the raw data-access API first (it lets us check writability up front)
-- and fall back to FlyWithLua's own dataref binding. Returns nil plus the
-- reason when a channel does not exist or cannot be written, so a wrong name
-- degrades into a log line instead of a script that fails to load.
local probe_count = 0

local function bind_float(path)
    if type(XPLMFindDataRef) == "function"
        and type(XPLMGetDataf) == "function"
        and type(XPLMSetDataf) == "function" then
        local ok, ref = pcall(XPLMFindDataRef, path)
        if not ok or not ref then return nil, "not present" end
        if type(XPLMCanWriteDataRef) == "function" then
            local ok2, can = pcall(XPLMCanWriteDataRef, ref)
            if not (ok2 and can) then return nil, "read-only" end
        end
        return {
            get = function() return XPLMGetDataf(ref) end,
            set = function(v) XPLMSetDataf(ref, clamp01(v)) end,
        }
    end

    -- Builds that do not expose the XPLM functions get this path instead.
    probe_count = probe_count + 1
    local gname = "smart_headphone_probe_" .. probe_count
    if not pcall(dataref, gname, path, "float") then return nil, "not present" end
    if type(_G) ~= "table" then return nil, "unavailable" end
    if type(_G[gname]) ~= "number" then return nil, "not present" end
    -- Smoke-test writability: FlyWithLua raises on a read-only dataref.
    if not pcall(function() _G[gname] = _G[gname] end) then return nil, "read-only" end
    return {
        get = function() return _G[gname] end,
        set = function(v) _G[gname] = clamp01(v) end,
    }
end

-- ===========================================================================
-- Channel table
-- ===========================================================================

local chans, missing = {}, {}

for _, def in ipairs(CHANNELS) do
    local io_ref, why = bind_float(def.path)
    if io_ref then
        chans[#chans + 1] = {
            path    = def.path,
            factor  = clamp01(def.factor),
            io      = io_ref,
            base    = nil,    -- the user's own level for this channel
            from    = 0,      -- fade endpoints
            to      = 0,
            t       = 0,      -- fade progress, seconds
            dur     = 0,
            anim    = false,
        }
    else
        missing[#missing + 1] = def.path .. " (" .. (why or "unavailable") .. ")"
    end
end

-- ===========================================================================
-- State
-- ===========================================================================

local anr_on = false

-- Remember the user's own mix. A channel that already sits at our own faded
-- level is not a user setting, so keep the base we captured earlier instead of
-- latching the faded value as the new baseline.
local function capture_base(c)
    local v = c.io.get()
    if c.base and math.abs(v - c.base * c.factor) <= 0.02 then
        return
    end
    c.base = clamp01(v)
end

local function plan_channel(c, target, dur)
    c.from = c.io.get()
    c.to   = clamp01(target)
    c.dur  = dur or 0
    c.t    = 0
    c.anim = c.dur > 0
    if not c.anim then c.io.set(c.to) end
end

local function engage(dur, keep_base)
    for _, c in ipairs(chans) do
        if not keep_base then capture_base(c) end
        if not c.base then c.base = clamp01(c.io.get()) end
        plan_channel(c, c.base * c.factor, dur)
    end
    anr_on = true
end

local function disengage(dur)
    for _, c in ipairs(chans) do
        if c.base then plan_channel(c, c.base, dur) end
    end
    anr_on = false
end

-- ===========================================================================
-- Persistence (survives FlyWithLua's reload-on-aircraft-load)
-- ===========================================================================

local function state_path()
    local dir
    if type(os.getenv) == "function" then
        dir = os.getenv("APPDATA") or os.getenv("LOCALAPPDATA") or os.getenv("TEMP")
    end
    if not dir or dir == "" then return nil end
    return dir .. "\\" .. STATE_FILE
end

local function load_state()
    local p = state_path()
    if not p then return nil end
    local f = io.open(p, "r")
    if not f then return nil end
    local st = { on = false, base = {} }
    for line in f:lines() do
        local k, v = line:match("^([^=]+)=([%-%d%.]+)")
        if k and v then
            if k == "on" then
                st.on = (tonumber(v) or 0) ~= 0
            else
                st.base[k] = tonumber(v)
            end
        end
    end
    f:close()
    return st
end

local function save_state()
    local p = state_path()
    if not p then return end
    local f = io.open(p, "w")
    if not f then return end
    f:write("on=", anr_on and "1" or "0", "\n")
    for _, c in ipairs(chans) do
        if c.base then
            f:write(c.path, "=", string.format("%.6f", c.base), "\n")
        end
    end
    f:close()
end

-- ===========================================================================
-- On-screen message
-- ===========================================================================

local toast_text, toast_until, toast_warned = nil, 0, false

local function toast(msg)
    if not SHOW_TOAST then return end
    toast_text  = msg
    toast_until = os.clock() + TOAST_SECS
end

function smart_headphone_draw()
    if not toast_text then return end
    if os.clock() > toast_until then toast_text = nil; return end
    if type(draw_string) ~= "function" then toast_text = nil; return end
    local ok = pcall(draw_string, TOAST_X, TOAST_Y, toast_text)
    if not ok then
        toast_text = nil
        if not toast_warned then
            toast_warned = true
            logMsg("smart_headphone: this FlyWithLua build rejected draw_string(); "
                .. "on-screen messages disabled (set SHOW_TOAST = false to silence)")
        end
    end
end

-- ===========================================================================
-- Commands
-- ===========================================================================

local function announce(label)
    toast("Smart Headphone: ANR " .. label)
    logMsg("smart_headphone: ANR " .. label)
    save_state()
end

-- The same handler is wired to both the "pressed" and the "held" callback slot
-- of the command, because which slot fires when is not the same in every
-- FlyWithLua build. The latch below turns either behaviour -- and key
-- auto-repeat -- into exactly one toggle per press: after firing, the toggle
-- stays disarmed until the command has been quiet for REARM_SECS, however long
-- you hold the key.
local press_armed = true
local last_press  = -1000

function smart_headphone_toggle()
    local now = os.clock()
    last_press = now
    if not press_armed then return end
    press_armed = false
    if anr_on then
        disengage(FADE_SECS)
        announce("off")
    else
        engage(FADE_SECS, false)
        announce("on")
    end
end

function smart_headphone_on()
    if anr_on then return end
    engage(FADE_SECS, false)
    announce("on")
end

function smart_headphone_off()
    if not anr_on then return end
    disengage(FADE_SECS)
    announce("off")
end

-- Escape hatch: put the watched channels back to the configured default and
-- forget the remembered mix, whatever state the sim was left in.
function smart_headphone_reset()
    for _, c in ipairs(chans) do
        c.anim = false
        c.base = nil
        c.io.set(DEFAULT_LEVEL)
    end
    anr_on = false
    toast("Smart Headphone: sound levels reset")
    logMsg("smart_headphone: sound levels reset to " .. string.format("%.2f", DEFAULT_LEVEL))
    save_state()
end

create_command("FlyWithLua/smart_headphone/toggle",
    "Smart Headphone: toggle noise cancelling (ANR)",
    "smart_headphone_toggle()", "smart_headphone_toggle()", "")

create_command("FlyWithLua/smart_headphone/on",
    "Smart Headphone: noise cancelling ON",
    "smart_headphone_on()", "smart_headphone_on()", "")

create_command("FlyWithLua/smart_headphone/off",
    "Smart Headphone: noise cancelling OFF",
    "smart_headphone_off()", "smart_headphone_off()", "")

create_command("FlyWithLua/smart_headphone/reset",
    "Smart Headphone: restore full sound levels (escape hatch)",
    "smart_headphone_reset()", "", "")

-- ===========================================================================
-- Per-frame fade
-- ===========================================================================

local last_clock = nil

function smart_headphone_frame()
    local now = os.clock()
    local dt
    if type(SIM_PERIOD) == "number" and SIM_PERIOD > 0 and SIM_PERIOD <= 0.5 then
        dt = SIM_PERIOD
    elseif last_clock then
        dt = now - last_clock
    else
        dt = 0.02
    end
    last_clock = now
    if dt <= 0.0001 then dt = 0.005 elseif dt > 0.5 then dt = 0.05 end

    -- re-arm the toggle once the key has been released for a moment
    if not press_armed and (now - last_press) > REARM_SECS then press_armed = true end

    for _, c in ipairs(chans) do
        if c.anim then
            c.t = c.t + dt / c.dur
            local k = c.t
            if k >= 1 then k = 1; c.anim = false end
            local e = 1 - (1 - k) * (1 - k)   -- ease-out: quick bite, soft landing
            c.io.set(c.from + (c.to - c.from) * e)
        end
    end
end

do_every_frame("smart_headphone_frame()")
if type(do_every_draw) == "function" then
    do_every_draw("smart_headphone_draw()")
end

-- ===========================================================================
-- Startup
-- ===========================================================================

local st = load_state()
if st then
    for _, c in ipairs(chans) do
        local v = st.base[c.path]
        if v then c.base = clamp01(v) end
    end
    if st.on then
        engage(RESTORE_FADE_SECS, true)
    end
end

logMsg("smart_headphone: ready -- " .. #chans .. "/" .. #CHANNELS
    .. " sound channels active, ANR " .. (anr_on and "ON (restored)" or "off"))
if #missing > 0 then
    logMsg("smart_headphone: skipped channels: " .. table.concat(missing, ", "))
    logMsg("smart_headphone: if engine noise is still loud, check the real names with "
        .. "findstr /i volume_ratio \"Resources\\plugins\\DataRefs.txt\" and add them to CHANNELS")
end
logMsg("smart_headphone: state file = " .. tostring(state_path() or "(unavailable, session-only)"))
