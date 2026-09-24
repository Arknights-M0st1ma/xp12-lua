--[[
    Instant Quick-Looks for X-Plane 12  (recall only)
    -------------------------------------------------
    X-Plane's built-in "Go to saved 3-D cockpit location" (sim/view/quick_look_N)
    eases the camera over ~0.5s. This script provides INSTANT recall commands that
    jump straight to the saved view, by writing the cockpit camera position
    datarefs directly (a direct write does not ease).

    Saving is X-Plane's own (Ctrl+Numpad / sim/view/quick_look_N_mem) -- this
    script does not save. Recall reads the saved view from <aircraft>_prefs.txt.

    Commands appear in X-Plane's Settings -> Keyboard / Joystick UI
    (search "quicklook"):
        FlyWithLua/quicklook/recall_1 .. _20   jump instantly to saved view N
    Command N maps to X-Plane "location #N" = stock slot (N-1).

    Restores head position + look angle (instant). Per-view zoom is handled only
    for ZOOM_SLOTS, via X-Plane's stock quick-look (see below).

    Author: built with Claude. License: do anything.
]]

local NUM_SLOTS = 20

-- ZOOM for the few views that need it (zero-C method). The cockpit zoom
-- (zoom_rat) has no writable dataref, so for ZOOM_SLOTS we let X-Plane's STOCK
-- quick-look restore zoom natively, then instantly override position + look angle
-- for a brief window so those snap while only the zoom glides (~0.5s). All native
-- physics/effects are retained. Slots NOT listed are fully instant, zoom untouched.
--   Example:  local ZOOM_SLOTS = { [2] = true, [5] = true }
local ZOOM_SLOTS = { [2] = true }

-- How long to hold the instant position/angle override while zoom glides.
-- Should be >= X-Plane's quick-look transition (~0.5s).
local OVERRIDE_SECS = 0.7

-- Writable camera datarefs we snap (DataRefs.txt marks these 'y' = writable).
local DR_X   = "sim/graphics/view/pilots_head_x"      -- head position vs CG, m
local DR_Y   = "sim/graphics/view/pilots_head_y"
local DR_Z   = "sim/graphics/view/pilots_head_z"
local DR_PSI = "sim/graphics/view/pilots_head_psi"    -- heading, deg
local DR_THE = "sim/graphics/view/pilots_head_the"    -- pitch, deg

local CMD_3D_COCKPIT = "sim/view/3d_cockpit_cmnd_look"

-- ---------------------------------------------------------------------------
-- Reading X-Plane's native saved views from <aircraft>_prefs.txt
-- ---------------------------------------------------------------------------

local function prefs_file_path()
    local dir = AIRCRAFT_PATH or ""
    local sep = dir:sub(-1)
    if sep ~= "/" and sep ~= "\\" then dir = dir .. "/" end
    local base = (AIRCRAFT_FILENAME or ""):gsub("%.[Aa][Cc][Ff]$", "")
    return dir .. base .. "_prefs.txt"
end

-- Parse stock slot index (0..19) from the prefs file. Returns a pose or nil.
local function read_prefs_slot(stock)
    local f = io.open(prefs_file_path(), "r")
    if not f then return nil end
    local kv = {}
    for line in f:lines() do
        local k, v = line:match("^(%S+)%s+(%S+)")
        if k then kv[k] = v end
    end
    f:close()

    local function num(name)
        local s = kv["_iql_" .. name .. "_" .. stock]
        return s and tonumber(s)
    end

    local x, y, z = num("pe_x"), num("pe_y"), num("pe_z")
    local psi, the = num("look_os_psi"), num("look_os_the")
    if not (x and y and z and psi and the) then return nil end
    return { x = x, y = y, z = z, psi = psi, the = the }
end

-- ---------------------------------------------------------------------------
-- Instant snap + the zoom-glide override
-- ---------------------------------------------------------------------------

local function snap_to(pose)
    command_once(CMD_3D_COCKPIT)         -- make sure we're in the 3-D cockpit
    set(DR_X, pose.x)
    set(DR_Y, pose.y)
    set(DR_Z, pose.z)
    set(DR_PSI, pose.psi)
    set(DR_THE, pose.the)
end

-- While an override is active we slam position/angle to the target every frame,
-- beating X-Plane's quick-look ease (so they look instant) while zoom glides.
local ovr_pose = nil
local ovr_until = 0

function instant_quicklook_hold()
    if not ovr_pose then return end
    if os.clock() >= ovr_until then ovr_pose = nil; return end
    set(DR_X, ovr_pose.x)
    set(DR_Y, ovr_pose.y)
    set(DR_Z, ovr_pose.z)
    set(DR_PSI, ovr_pose.psi)
    set(DR_THE, ovr_pose.the)
end

do_every_frame("instant_quicklook_hold()")

function instant_quicklook_recall(n)
    local pose = read_prefs_slot(n - 1)
    if not pose then
        logMsg(string.format("instant_quicklook: slot %d is empty", n))
        return
    end
    if ZOOM_SLOTS[n] then
        -- Let stock quick-look restore zoom (and pos/angle) natively, then
        -- override pos/angle so they snap while only zoom glides.
        command_once(string.format("sim/view/quick_look_%d", n - 1))
        ovr_pose = pose
        ovr_until = os.clock() + OVERRIDE_SECS
    else
        -- Fully instant, zoom untouched.
        ovr_pose = nil
        snap_to(pose)
    end
end

-- ---------------------------------------------------------------------------
-- Command registration (appears in X-Plane's binding UI)
-- ---------------------------------------------------------------------------

for n = 1, NUM_SLOTS do
    create_command(
        string.format("FlyWithLua/quicklook/recall_%d", n),
        string.format("Instant quick-look: jump instantly to saved view %d", n),
        string.format("instant_quicklook_recall(%d)", n),
        "", "")
end

logMsg("instant_quicklook: ready for " .. (AIRCRAFT_FILENAME or "?")
    .. "  (prefs: " .. prefs_file_path() .. ")")
