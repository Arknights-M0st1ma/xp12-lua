--[[
    Nearby METAR & Time for X-Plane 12  (FlyWithLua NG)
    --------------------------------------------------
    Bind a key to "FlyWithLua/nearby_weather/toggle" (X-Plane: Settings ->
    Keyboard -> search for "nearby weather") and press it to pop up a compact
    panel in the top left corner of the screen:

      * the METAR report of the three nearest usable airports, taken from
        X-Plane's own weather system,
      * the time zone at the aircraft's position, plus Zulu (GMT) and local time.

    The panel is a real X-Plane floating window with the simulator's own window
    frame: drag it by its title bar, resize it by its edges, close it with the
    cross - or just press your key again.  Its contents are drawn with ImGui,
    which is what makes the text scale with your display.

    Heliports, seaplane bases, private/backcountry strips and airports whose
    longest paved runway is shorter than MIN_PAVED_RUNWAY_FT are filtered out.

    Where the data comes from (all of it from inside the simulator):
      * METAR text  : XPLMGetMETARForAirport() - the last METAR X-Plane itself
                      downloaded for that ICAO code, i.e. the same data the
                      "Real Weather" mode is built from.  Nothing is fetched
                      from the internet by this script.  If Real Weather has
                      never been used, the simulator reports empty strings and
                      the panel says so.
      * Airports    : <X-Plane>/Resources/default scenery/default apt dat/
                      Earth nav data/apt.dat (apt.dat 12.00, X-Plane's own
                      airport database).  It is streamed in small slices in the
                      background, so it never stalls the simulator.
      * Times       : sim/time/zulu_time_sec and sim/time/local_time_sec.

    Author: built with Claude.  License: do anything you want with it.
]]

-- ===========================================================================
--  1. Settings - everything you may want to change lives here
-- ===========================================================================

local CFG = {
    -- The window ----------------------------------------------------------
    -- It is a real X-Plane floating window: X-Plane draws its frame and title
    -- bar, you drag it with the mouse and resize it by its edges.
    window_width   = 600,     -- logical size; multiplied by text_scale below
    window_height  = 340,
    margin_left    = 30,      -- where it appears: from the left screen edge
    margin_top     = 30,      -- ... and from the top edge of the screen
    text_scale     = 0,       -- 0 = automatic (bigger on big displays),
                              -- or a fixed number such as 1.4 / 1.8 / 2.4
    start_visible  = false,   -- false: hidden until you press your key
    resizable      = true,    -- let the window be resized by its edges

    -- Airports ------------------------------------------------------------
    airport_count        = 3,     -- how many airports to list
    min_paved_runway_ft  = 2000,  -- drop fields with nothing longer than this
    require_icao_code    = true,  -- only 4-character ICAO codes (KSEA, EGLL)
    search_radius_nm     = 150,   -- ignore airports farther away than this
    candidate_limit      = 10,    -- stations examined when looking for reports
    prefer_reporting     = true,  -- prefer airports that actually report METAR

    -- Timing / background work -------------------------------------------
    scan_on_load         = true,  -- build the airport database right away
    scan_max_lines       = 4000,  -- apt.dat lines parsed per frame
    scan_budget_sec      = 0.004, -- ... but never more than this per frame
    repick_seconds       = 45,    -- re-rank the nearest airports this often
    repick_distance_nm   = 20,    -- ... or after flying this far
    metar_refresh_sec    = 300,   -- re-read METARs from X-Plane this often
    metar_retry_sec      = 30,    -- ... and this often while nothing came back
    zone_table           = true,  -- show a coarse region next to the UTC offset
    debug                = false, -- extra lines in Log.txt
}

local APT_DAT = "Resources/default scenery/default apt dat/Earth nav data/apt.dat"

-- ===========================================================================
--  2. Colours - dark panel, light text, X-Plane 12 style
-- ===========================================================================

-- ImGui wants packed 0xAABBGGRR colours (the order of its own IM_COL32 macro),
-- so build them from ordinary R, G, B, A bytes.
local function rgb(r, g, b, a)
    return (a or 255) * 0x1000000 + b * 0x10000 + g * 0x100 + r
end

local COL = {
    panel      = rgb(13, 15, 18, 238),      -- window background
    border     = rgb(255, 255, 255, 36),    -- window border
    accent     = rgb(97, 176, 245),         -- the title
    text       = rgb(236, 240, 244),
    dim        = rgb(160, 170, 180),
    faint      = rgb(115, 124, 135),
    vfr        = rgb(61, 205, 96),
    mvfr       = rgb(66, 156, 242),
    ifr        = rgb(242, 81, 71),
    lifr       = rgb(201, 92, 218),
}

-- ===========================================================================
--  3. Small helpers
-- ===========================================================================

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function collapse(s)
    return trim(tostring(s or ""):gsub("%s+", " "))
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function commas(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

local RAD = math.pi / 180

-- Great circle distance in nautical miles.
local function distance_nm(lat1, lon1, lat2, lon2)
    local dlat = (lat2 - lat1) * RAD
    local dlon = (lon2 - lon1) * RAD
    local a = math.sin(dlat / 2) ^ 2
              + math.cos(lat1 * RAD) * math.cos(lat2 * RAD) * math.sin(dlon / 2) ^ 2
    return 2 * 6371.0 / 1.852 * math.asin(math.min(1, math.sqrt(a)))
end

-- Initial true bearing from point 1 to point 2, in degrees.
local function bearing_deg(lat1, lon1, lat2, lon2)
    local p1, p2 = lat1 * RAD, lat2 * RAD
    local dl = (lon2 - lon1) * RAD
    local y = math.sin(dl) * math.cos(p2)
    local x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return (math.deg(math.atan2(y, x)) + 360) % 360
end

-- X-Plane's LuaJIT has math.atan2, but be safe on other builds.
if not math.atan2 then
    math.atan2 = function(y, x) return math.atan(y, x) end
end

-- Wrap a string into lines that fit into max_w pixels.  Only call this while
-- the ImGui panel is being built: CalcTextSize() then knows the font scale.
local function wrap_text(text, max_w)
    local lines, cur = {}, ""
    for word in tostring(text):gmatch("%S+") do
        local candidate = (cur == "") and word or (cur .. " " .. word)
        if cur ~= "" and imgui.CalcTextSize(candidate) > max_w then
            lines[#lines + 1] = cur
            cur = word
        else
            cur = candidate
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    if #lines == 0 then lines[1] = "" end
    return lines
end

-- ===========================================================================
--  4. apt.dat - X-Plane's airport database
-- ===========================================================================

-- Surface codes: 1/2 are the classic asphalt/concrete codes, 20-38 and 50-57
-- are the asphalt and concrete shades introduced with apt.dat 12.00, see the
-- official "Airport Data (apt.dat) 12.00 File Format Specification".
local function surface_paved(code)
    return code == 1 or code == 2
        or (code >= 20 and code <= 38)
        or (code >= 50 and code <= 57)
end

local function surface_name(code)
    if code == 1 or (code >= 20 and code <= 38) then return "asphalt" end
    if code == 2 or (code >= 50 and code <= 57) then return "concrete" end
    if code == 3 then return "grass" end
    if code == 4 then return "dirt" end
    if code == 5 then return "gravel" end
    if code == 12 then return "dry lakebed" end
    if code == 13 then return "water" end
    if code == 14 then return "snow/ice" end
    if code == 15 then return "hard surface" end
    return "paved"
end

local function icao_like(id)
    return id ~= nil and id:match("^[A-Z][A-Z0-9][A-Z0-9][A-Z0-9]$") ~= nil
end

-- One airport header line: "1   21 1 0 KBFI Boeing Field King Co Intl"
-- (rows 1, 16 and 17 share this layout; use a token scan so that the two
--  deprecated fields cannot break the parse).
local function parse_header(line)
    local t = {}
    for word in line:gmatch("%S+") do t[#t + 1] = word end
    local elev = tonumber(t[2])
    local idx
    for i = 3, math.min(#t, 6) do
        if t[i]:find("%a") and t[i]:match("^[A-Za-z0-9][A-Za-z0-9%-_]*$") then
            idx = i
            break
        end
    end
    if not idx then return nil end
    local name = {}
    for i = idx + 1, #t do name[#name + 1] = t[i] end
    return {
        id    = t[idx]:upper(),
        name  = trim(table.concat(name, " ")),
        elev  = elev or 0,
        yards = {},
    }
end

-- Land runway row: "100 <width> <surface> <shoulder> <smooth> <cl> <edge>
--                    <signs> <rwy1> <lat1> <lon1> ... <rwy2> <lat2> <lon2> ..."
local function parse_runway(apt, line)
    local t = {}
    for word in line:gmatch("%S+") do t[#t + 1] = word end
    -- Sanity check on the row layout before trusting any offset: the runway
    -- designator always sits at field 9 ("04L", "13", "08W", ...).
    if not (t[9] and t[9]:match("^%d%d[LRCWST]?$")) then return end
    local surface = tonumber(t[3])
    if not (surface and surface_paved(surface)) then return end

    local lat1, lon1 = tonumber(t[10]), tonumber(t[11])
    local lat2, lon2 = tonumber(t[19]), tonumber(t[20])
    if not (lat1 and lon1 and lat2 and lon2) then return end
    if math.abs(lat1) > 90 or math.abs(lon1) > 180 then return end
    if math.abs(lat2) > 90 or math.abs(lon2) > 180 then return end

    local length_ft = distance_nm(lat1, lon1, lat2, lon2) * 6076.12
    if not apt.best_ft or length_ft > apt.best_ft then
        apt.best_ft   = length_ft
        apt.best_surf = surface
        apt.best_lat  = (lat1 + lat2) / 2
        apt.best_lon  = (lon1 + lon2) / 2
    end
end

-- Row 1302 carries the real ICAO code of an airport ("1302 icao_id KSEA ...").
local function parse_metadata(apt, line)
    local tokens = {}
    for word in line:gmatch("%S+") do tokens[#tokens + 1] = word end
    for i = 2, #tokens - 1 do
        if tokens[i] == "icao_id" or tokens[i] == "icao_code" then
            local code = tokens[i + 1]:upper()
            if code:match("^[A-Z0-9][A-Z0-9%-]*$") then apt.icao = code end
            return
        end
    end
end

-- Turn the accumulated airport into a database entry, or throw it away.
local function accept_airport(apt)
    if not apt.best_ft or apt.best_ft < CFG.min_paved_runway_ft then return nil end
    local id = apt.icao or apt.id
    if not id then return nil end
    if CFG.require_icao_code and not icao_like(id) then return nil end
    return {
        id   = id,
        lat  = apt.best_lat,
        lon  = apt.best_lon,
        ft   = apt.best_ft,
        surf = apt.best_surf,
        elev = apt.elev,
        name = apt.name,
    }
end

local function scan_coroutine(path)
    return coroutine.create(function()
        local file = io.open(path, "r")
        if not file then return { error = "apt.dat not found: " .. path } end

        local list   = {}
        local cur    = nil        -- airport being collected (false = skipping)
        local lines     = 0
        local bytes     = 0
        local last_slice = 0
        local t0        = os.clock()
        local budget    = CFG.scan_budget_sec

        for line in file:lines() do
            lines = lines + 1
            bytes = bytes + #line + 1

            -- Cheap gate: every row we care about starts with a digit, and the
            -- airport/runway rows are all in the "1..." family.
            if line:byte(1) == 49 then
                local code = tonumber(line:match("^(%d+)"))
                if code == 1 or code == 16 or code == 17 then
                    if cur then
                        local apt = accept_airport(cur)
                        if apt then list[#list + 1] = apt end
                    end
                    cur = (code == 1) and parse_header(line) or false
                elseif cur then
                    if code == 100 then
                        parse_runway(cur, line)
                    elseif code == 1302 then
                        parse_metadata(cur, line)
                    end
                end
            end

            if lines % 256 == 0 then
                if (lines - last_slice) >= CFG.scan_max_lines or (os.clock() - t0) >= budget then
                    last_slice = lines
                    t0 = os.clock()
                    coroutine.yield(lines, bytes)
                end
            end
        end

        file:close()
        if cur then
            local apt = accept_airport(cur)
            if apt then list[#list + 1] = apt end
        end
        return { list = list, lines = lines, bytes = bytes }
    end)
end

-- ===========================================================================
--  5. METAR from X-Plane itself (XPLMGetMETARForAirport through LuaJIT FFI)
-- ===========================================================================

local XPLM_CDEF = [[
typedef struct { char buffer[150]; } FWL_NEARBY_WX_METAR_t;
void XPLMGetMETARForAirport(const char * airport_id, FWL_NEARBY_WX_METAR_t * outMETAR);
]]

local function init_metar_source()
    local ok, ffi = pcall(require, "ffi")
    if not ok or type(ffi) ~= "table" then
        return nil, "LuaJIT FFI is not available in this FlyWithLua build"
    end

    -- Every script shares one Lua state, so another script may have declared
    -- this already - a failed cdef is not fatal.
    pcall(ffi.cdef, XPLM_CDEF)

    local libs = {}
    if SYSTEM == "IBM" then
        libs = { "XPLM_64", "XPLM" }
    elseif SYSTEM == "LIN" then
        libs = { "Resources/plugins/XPLM_64.so", "Resources/plugins/XPLM.so" }
    elseif SYSTEM == "APL" then
        libs = { "Resources/plugins/XPLM.framework/XPLM" }
    end

    local symbol
    for _, name in ipairs(libs) do
        local loaded, lib = pcall(ffi.load, name)
        if loaded and lib then
            local found, fn = pcall(function() return lib.XPLMGetMETARForAirport end)
            if found and fn then
                symbol = fn
                if CFG.debug then logMsg("nearby_weather: using XPLM library '" .. name .. "'") end
                break
            end
        end
    end
    if not symbol then
        -- On macOS/Linux the XPLM symbols are already in the process.
        local found, fn = pcall(function() return ffi.C.XPLMGetMETARForAirport end)
        if found and fn then symbol = fn end
    end
    if not symbol then
        return nil, "XPLMGetMETARForAirport not found (is this X-Plane 12?)"
    end

    local buffer = ffi.new("FWL_NEARBY_WX_METAR_t")
    local function fetch(icao)
        buffer.buffer[0] = 0
        local called = pcall(symbol, icao, buffer)
        if not called then return nil end
        -- Read the C string without ever running past the 150 byte buffer.
        local n = 0
        while n < 150 and buffer.buffer[n] ~= 0 do n = n + 1 end
        if n == 0 then return "" end
        return ffi.string(buffer.buffer, n)
    end
    return fetch
end

-- ===========================================================================
--  6. METAR decoding (flight category + observation age)
-- ===========================================================================

local BAD_CEILING_FT = 99999

local function metar_category(vis_sm, ceiling_ft)
    if vis_sm < 1 or ceiling_ft < 500 then return "LIFR", COL.lifr end
    if vis_sm < 3 or ceiling_ft < 1000 then return "IFR", COL.ifr end
    if vis_sm <= 5 or ceiling_ft <= 3000 then return "MVFR", COL.mvfr end
    return "VFR", COL.vfr
end

local function parse_metar(raw)
    local report = collapse(raw)
    if report == "" or report:upper() == "NIL" then return nil end

    -- Drop the report type and the station ident, the airport ident shows them.
    local speci = report:match("^SPECI%s") ~= nil
    report = report:gsub("^SPECI%s+", ""):gsub("^METAR%s+", "")
    local first, rest = report:match("^(%S+)%s+(.*)$")
    if first and icao_like(first) and rest:match("^%d%d%d%d%d%dZ") then
        report = rest
    end

    local tokens = {}
    for word in report:gmatch("%S+") do tokens[#tokens + 1] = word end

    local obs_day, obs_hour, obs_min
    local vis_sm, vis_sm_set = 10, false
    local ceiling_ft = BAD_CEILING_FT

    for i, token in ipairs(tokens) do
        -- observation time, e.g. 241953Z
        if not obs_day then
            local d, h, m = token:match("^(%d%d)(%d%d)(%d%d)Z$")
            if d then obs_day, obs_hour, obs_min = tonumber(d), tonumber(h), tonumber(m) end
        end

        -- visibility in statute miles: 10SM, P6SM, M1/4SM, 1/2SM, 1 1/2SM
        if not vis_sm_set then
            local v = token:match("^[MP]?([%d%.]+)SM$")
            if v then
                vis_sm = tonumber(v)
                vis_sm_set = true
            else
                local num, den = token:match("^[MP]?([%d]+)/([%d]+)SM$")
                if num then
                    local whole = tokens[i - 1]
                    local add = (whole and whole:match("^%d+$")) and tonumber(whole) or 0
                    vis_sm = add + tonumber(num) / tonumber(den)
                    vis_sm_set = true
                end
            end
        end

        -- visibility in metres, e.g. 8000 or 9999
        if not vis_sm_set and token:match("^%d%d%d%d$") and i > 2 then
            vis_sm = tonumber(token) * 0.000621371
            vis_sm_set = true
        end

        -- ceiling: lowest broken/overcast layer, or vertical visibility.
        -- Cloud layers are three letters (FEW/SCT/BKN/OVC), the vertical
        -- visibility group is only two letters (VV002 = 200 ft).
        local layer, base = token:match("^(%a%a%a)(%d%d%d)$")
        if not layer then
            local vv = token:match("^VV(%d%d%d)$")
            if vv then layer, base = "VV", vv end
        end
        if layer and (layer == "BKN" or layer == "OVC" or layer == "VV") then
            local ft = tonumber(base) * 100
            if ft < ceiling_ft then ceiling_ft = ft end
        end
    end

    if report:find("CAVOK") then
        vis_sm, ceiling_ft = 10, BAD_CEILING_FT
    end

    local category, colour = metar_category(vis_sm, ceiling_ft)
    return {
        text    = report,
        speci   = speci,
        day     = obs_day,
        hour    = obs_hour,
        minute  = obs_min,
        vis_sm  = vis_sm,
        ceiling = ceiling_ft,
        category = category,
        colour  = colour,
    }
end

-- Minutes since the observation, using the simulator's own Zulu clock.
local function observation_age_min(parsed)
    if not (parsed and parsed.hour and xpnw_zulu_sec) then return nil end
    local obs = parsed.hour * 3600 + parsed.minute * 60
    local delta = xpnw_zulu_sec - obs
    if delta < -43200 then delta = delta + 86400 end
    if delta > 43200 then delta = delta - 86400 end
    return delta / 60
end

-- ===========================================================================
--  7. Coarse time zone labels (always validated against the simulator's own
--     UTC offset, so the label can never contradict the clocks shown)
-- ===========================================================================

local ZONES = {
    -- label,                 lat_min, lat_max, lon_min, lon_max,  UTC offsets
    { "Hawaii",                    18,   23,  -161,  -154, { -10 } },
    { "Alaska",                    51,   72,  -170,  -129, { -9, -8 } },
    { "US Pacific",                32,   49,  -125,  -114, { -8, -7 } },
    { "US Mountain",               31,   49,  -114,  -102, { -7, -6 } },
    { "US Central",                24,   49,  -102,   -85, { -6, -5 } },
    { "US Eastern",                24,   48,   -85,   -66, { -5, -4 } },
    { "Atlantic Canada",           43,   53,   -67,   -52, { -4, -3.5, -3, -2.5 } },
    { "Iceland",                   63,   67,   -25,   -13, { 0 } },
    { "Azores",                    36,   40,   -32,   -24, { -1, 0 } },
    { "UK & Ireland",              49,   61,   -11,     2, { 0, 1 } },
    { "Western Europe",            36,   55,   -10,     8, { 0, 1, 2 } },
    { "Central Europe",            42,   56,     8,    24, { 1, 2 } },
    { "Eastern Europe",            44,   62,    24,    45, { 2, 3 } },
    { "Turkey & Caucasus",         36,   45,    26,    50, { 2, 3 } },
    { "Iran",                      25,   40,    44,    64, { 3.5 } },
    { "Arabia",                    12,   35,    34,    60, { 2, 3, 3.5 } },
    { "West Africa",                4,   25,   -18,    15, { 0, 1 } },
    { "Central & East Africa",    -12,   25,    15,    52, { 2, 3 } },
    { "Southern Africa",          -35,  -22,    16,    33, { 2 } },
    { "Pakistan",                  23,   37,    60,    76, { 5 } },
    { "India",                      6,   35,    68,    90, { 5.5 } },
    { "Indochina",                  0,   24,    92,   110, { 7 } },
    { "China",                     18,   54,    73,   135, { 8 } },
    { "Japan & Korea",             30,   46,   126,   146, { 9 } },
    { "Western Australia",        -35,  -10,   112,   129, { 8 } },
    { "Central Australia",        -35,  -10,   129,   138, { 9.5 } },
    { "Eastern Australia",        -45,  -10,   138,   154, { 10, 11 } },
    { "New Zealand",              -48,  -33,   165,   179, { 12, 13 } },
    { "Peru & Colombia",          -19,   12,   -82,   -66, { -5 } },
    { "Bolivia & Venezuela",      -23,   12,   -70,   -57, { -4 } },
    { "Brazil",                   -34,    5,   -74,   -34, { -3 } },
    { "Argentina & Chile",        -56,  -20,   -76,   -53, { -3, -4 } },
}

local function zone_label(lat, lon, offset_hours)
    if not CFG.zone_table then return nil end
    for _, zone in ipairs(ZONES) do
        if lat >= zone[2] and lat <= zone[3] and lon >= zone[4] and lon <= zone[5] then
            for _, candidate in ipairs(zone[6]) do
                if math.abs(candidate - offset_hours) < 0.01 then return zone[1] end
            end
        end
    end
    return nil
end

-- ===========================================================================
--  8. State
-- ===========================================================================

dataref("xpnw_zulu_sec",  "sim/time/zulu_time_sec",  "readonly")
dataref("xpnw_local_sec", "sim/time/local_time_sec", "readonly")

xpnw_visible = xpnw_visible or CFG.start_visible

-- The airport database is kept in a global: FlyWithLua re-runs every script
-- when the aircraft or the airport changes, and re-parsing apt.dat each time
-- would be a waste.  The data itself never changes during a session.
local DB_VERSION = 1
if type(xpnw_db) ~= "table" or xpnw_db.version ~= DB_VERSION then xpnw_db = nil end

local S = {
    db          = xpnw_db,
    scan        = nil,
    scan_error  = nil,
    scan_total  = 0,
    scan_bytes  = 0,
    candidates  = {},
    metar       = {},
    display     = {},
    pick_time   = 0,
    pick_lat    = nil,
    pick_lon    = nil,
    fetch_time  = 0,
    fetch_ok    = 0,
    status      = "starting up",
    force_update = false,
    -- the panel window (reused when FlyWithLua re-runs this script)
    wnd         = xpnw_wnd,
    wnd_failed  = false,
    scale       = nil,
    pos_x       = nil,
    pos_y       = nil,
    window_w    = 0,
    window_h    = 0,
}

local metar_fetch, metar_error = init_metar_source()
S.metar_error = metar_error
if metar_error then
    logMsg("nearby_weather: " .. metar_error)
end

-- ===========================================================================
--  9. Background scan of apt.dat
-- ===========================================================================

local function apt_dat_path()
    local sep = DIRECTORY_SEPARATOR or "/"
    local base = SYSTEM_DIRECTORY or ""
    if base ~= "" and base:sub(-1) ~= sep and base:sub(-1) ~= "/" and base:sub(-1) ~= "\\" then
        base = base .. sep
    end
    return base .. APT_DAT
end

local function file_size(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local size = file:seek("end")
    file:close()
    return size
end

local function start_scan()
    local path = apt_dat_path()
    S.scan_total = file_size(path)
    S.scan_lines = 0
    S.scan_bytes = 0
    S.scan       = scan_coroutine(path)
    S.status     = "reading X-Plane's airport database"
    if CFG.debug then logMsg("nearby_weather: scanning " .. path) end
end

local function scan_progress()
    if S.scan_total and S.scan_total > 0 then
        return clamp(S.scan_bytes / S.scan_total * 100, 0, 100)
    end
    return nil
end

function nwp_step()
    if S.scan then
        local ok, lines, bytes = coroutine.resume(S.scan)
        if not ok then
            S.scan = nil
            S.scan_error = "apt.dat scan failed: " .. tostring(lines)
            S.status = "airport database error"
            logMsg("nearby_weather: " .. S.scan_error)
        else
            if lines then
                S.scan_bytes = bytes or S.scan_bytes
            end
            if coroutine.status(S.scan) == "dead" then
                local result = lines
                S.scan = nil
                if type(result) == "table" and result.error then
                    S.scan_error = result.error
                    S.status = "airport database missing"
                    logMsg("nearby_weather: " .. result.error)
                else
                    xpnw_db = { version = DB_VERSION, list = result.list }
                    S.db = xpnw_db
                    S.status = "ready"
                    logMsg(string.format("nearby_weather: airport database ready - %s usable airports (%s lines read)",
                        commas(#result.list), commas(result.lines)))
                    S.force_update = true
                end
            end
        end
    end

    -- A freshly opened panel should be filled in right away instead of waiting
    -- for the next do_often() tick.
    if S.force_update then
        S.force_update = false
        nwp_update()
    end
end

-- ===========================================================================
-- 10. Choosing the nearest airports and reading their METARs
-- ===========================================================================

local function pick_candidates()
    local lat, lon = LATITUDE, LONGITUDE
    if not (lat and lon and S.db) then return end

    local near = {}
    for _, apt in ipairs(S.db.list) do
        local dist = distance_nm(lat, lon, apt.lat, apt.lon)
        if dist <= CFG.search_radius_nm then
            near[#near + 1] = { apt = apt, dist = dist }
        end
    end
    table.sort(near, function(a, b) return a.dist < b.dist end)

    -- Keep only the nearest few airports, then add bearing for the panel.
    local limit = math.min(#near, CFG.candidate_limit)
    local candidates = {}
    for i = 1, limit do
        local entry = near[i]
        entry.brg = bearing_deg(lat, lon, entry.apt.lat, entry.apt.lon)
        candidates[i] = entry
    end
    S.candidates = candidates
    S.pick_lat, S.pick_lon = lat, lon
    S.pick_time = os.time()
end

local function refresh_metars()
    if not metar_fetch then return end
    local now = os.time()
    -- While X-Plane has no report for us yet (start of the session, Real
    -- Weather still downloading, ...) come back sooner than the usual interval.
    local wait = (S.fetch_ok > 0) and CFG.metar_refresh_sec or CFG.metar_retry_sec
    if now - S.fetch_time < wait then return end
    S.fetch_time = now
    S.fetch_ok = 0
    for _, entry in ipairs(S.candidates) do
        local cached = S.metar[entry.apt.id]
        local raw = metar_fetch(entry.apt.id)
        if raw == nil then
            S.metar_error = "calling XPLMGetMETARForAirport failed"
            logMsg("nearby_weather: calling XPLMGetMETARForAirport failed")
        elseif raw ~= "" then
            S.fetch_ok = S.fetch_ok + 1
            if not cached or cached.raw ~= raw then
                S.metar[entry.apt.id] = { raw = raw, parsed = parse_metar(raw) }
            end
        else
            -- The sim has no report for this station (yet): do not show an
            -- outdated one.
            S.metar[entry.apt.id] = nil
        end
    end
end

local function build_display()
    local chosen, chosen_ids = {}, {}
    local function add(entry)
        if #chosen >= CFG.airport_count then return end
        if chosen_ids[entry.apt.id] then return end
        local report = S.metar[entry.apt.id]
        local has_report = report ~= nil and report.parsed ~= nil
        if CFG.prefer_reporting and not has_report and #S.candidates > CFG.airport_count then
            return
        end
        chosen_ids[entry.apt.id] = true
        chosen[#chosen + 1] = {
            apt    = entry.apt,
            dist   = entry.dist,
            brg    = entry.brg,
            parsed = has_report and report.parsed or nil,
        }
    end

    for _, entry in ipairs(S.candidates) do add(entry) end
    -- If not enough airports reported weather, fill up with the closest ones.
    for _, entry in ipairs(S.candidates) do
        if #chosen >= CFG.airport_count then break end
        if not chosen_ids[entry.apt.id] then
            chosen_ids[entry.apt.id] = true
            chosen[#chosen + 1] = { apt = entry.apt, dist = entry.dist, brg = entry.brg }
        end
    end
    S.display = chosen
end

local function update_status()
    if S.scan then
        local progress = scan_progress()
        S.status = progress and string.format("scanning airports %.0f%%", progress)
                             or "scanning airports"
    elseif S.scan_error then
        S.status = "airport database unavailable"
    elseif S.metar_error and S.fetch_ok == 0 then
        S.status = "METAR source unavailable"
    elseif S.fetch_ok == 0 then
        S.status = "no METAR data (Real Weather off?)"
    else
        S.status = ""
    end
end

function nwp_update()
    if not S.db and not S.scan and not S.scan_error and CFG.scan_on_load then
        start_scan()
    end

    if not S.db then
        update_status()
        return
    end

    local lat, lon = LATITUDE, LONGITUDE
    local moved = (not S.pick_lat) and 1e9 or distance_nm(lat, lon, S.pick_lat, S.pick_lon)
    if #S.candidates == 0 or moved > CFG.repick_distance_nm or (os.time() - S.pick_time) > CFG.repick_seconds then
        pick_candidates()
    end
    refresh_metars()
    build_display()
    update_status()
end

-- ===========================================================================
-- 11. The panel: a real X-Plane floating window, drawn with ImGui
-- ===========================================================================

local function seconds_to_clock(seconds)
    if not seconds then return "--:--:--" end
    local s = math.floor(seconds) % 86400
    return string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60)
end

local function offset_label(offset_hours)
    if not offset_hours then return "UTC?" end
    local sign = "+"
    if offset_hours < 0 then sign = "-"; offset_hours = -offset_hours end
    local hours = math.floor(offset_hours)
    local minutes = math.floor((offset_hours - hours) * 60 + 0.5)
    if minutes == 60 then hours, minutes = hours + 1, 0 end
    if minutes == 0 then return string.format("UTC%s%02d:00", sign, hours) end
    return string.format("UTC%s%02d:%02d", sign, hours, minutes)
end

-- X-Plane measures floating windows in "boxels" (device independent pixels),
-- so the same font size looks half as big on a 4K display as on a 1080p one.
-- Scale the whole panel - window size, text and padding - with the screen
-- height, unless a fixed factor was set in the settings above.
local function ui_scale()
    if CFG.text_scale and CFG.text_scale > 0 then return CFG.text_scale end
    local _, height = XPLMGetScreenSize()
    return clamp((height or SCREEN_HIGHT or 1080) / 1000, 1.25, 2.6)
end

-- Window positions are offsets from the lower left corner of the desktop.
local function desktop_bounds()
    if type(XPLMGetScreenBoundsGlobal) == "function" then
        local left, top, right, bottom = XPLMGetScreenBoundsGlobal()
        if left and bottom then return left, top, right, bottom end
    end
    return 0, SCREEN_HIGHT or 1080, SCREEN_WIDTH or 1920, 0
end

local function default_position(width, height)
    local _, top, _, bottom = desktop_bounds()
    return CFG.margin_left, (top - bottom) - CFG.margin_top - height
end

-- ---- ImGui helpers --------------------------------------------------------

local PAD_X, PAD_Y = 16, 12        -- logical padding inside the window

-- Coloured text.  TextUnformatted() is used on purpose: Text() and
-- TextColored() are printf style, and a '%' in a METAR remark would be read as
-- a format specifier.
local function panel_text(text, colour)
    imgui.PushStyleColor(imgui.constant.Col.Text, colour)
    imgui.TextUnformatted(text)
    imgui.PopStyleColor()
end

local function panel_same_line(x)
    imgui.SameLine(x, 0)              -- 0: do not add the style item spacing
end

local function age_text(parsed)
    local age = observation_age_min(parsed)
    if not age then return nil end
    if age < -1 then return "ahead of clock" end   -- sim clock moved into the past
    if age > 720 then return "stale" end
    if age < 90 then return string.format("%d min ago", math.floor(age + 0.5)) end
    return string.format("%.1f h ago", age / 60)
end

-- ---- the window itself ----------------------------------------------------

local function create_window()
    if S.wnd_failed then return nil end
    if SUPPORTS_FLOATING_WINDOWS == nil or type(imgui) ~= "table"
        or type(float_wnd_create) ~= "function"
        or type(float_wnd_set_imgui_builder) ~= "function" then
        S.wnd_failed = true
        logMsg("nearby_weather: this FlyWithLua build has no ImGui floating windows - " ..
               "the panel needs FlyWithLua NG+ 2.8.x for X-Plane 12")
        return nil
    end

    local scale  = ui_scale()
    local width  = math.floor(CFG.window_width * scale)
    local height = math.floor(CFG.window_height * scale)
    local created, wnd = pcall(float_wnd_create, width, height, 1, true)
    if not created or wnd == nil then
        S.wnd_failed = true
        logMsg("nearby_weather: could not create the panel window: " .. tostring(wnd))
        return nil
    end

    S.wnd, S.scale, S.window_w, S.window_h = wnd, scale, width, height
    xpnw_wnd = wnd

    pcall(float_wnd_set_title, wnd, "Nearby METAR & Time")
    pcall(float_wnd_set_imgui_builder, wnd, "nwp_build")
    pcall(float_wnd_set_onclose, wnd, "nwp_onclose")
    if CFG.resizable ~= false and type(float_wnd_set_resizing_limits) == "function" then
        pcall(float_wnd_set_resizing_limits, wnd,
              math.floor(width * 0.6), math.floor(height * 0.5),
              SCREEN_WIDTH or 1920, SCREEN_HIGHT or 1080)
    end
    local pos_x, pos_y = S.pos_x, S.pos_y
    if not pos_x then pos_x, pos_y = default_position(width, height) end
    pcall(float_wnd_set_position, wnd, pos_x, pos_y)

    logMsg(string.format("nearby_weather: panel window %dx%d boxels, text scale %.2f",
                         width, height, scale))
    return wnd
end

function nwp_show()
    local adopted = S.wnd ~= nil
    local wnd = S.wnd or create_window()
    if not wnd then return end
    if adopted then
        -- The window survived a reload of this script, so point it at the
        -- callbacks of the current run of the script.
        pcall(float_wnd_set_imgui_builder, wnd, "nwp_build")
        pcall(float_wnd_set_onclose, wnd, "nwp_onclose")
    end
    pcall(float_wnd_set_visible, wnd, 1)
    if type(float_wnd_bring_to_front) == "function" then
        pcall(float_wnd_bring_to_front, wnd)
    end
    xpnw_visible = true
    S.force_update = true
end

function nwp_hide()
    local wnd = S.wnd
    S.wnd, xpnw_wnd, xpnw_visible = nil, nil, false
    if not wnd then return end
    -- Remember where the window was, so showing it again does not make it jump.
    local got, left, _, _, bottom = pcall(float_wnd_get_geometry, wnd)
    if got and left then
        local desk_left, _, _, desk_bottom = desktop_bounds()
        S.pos_x, S.pos_y = left - desk_left, bottom - desk_bottom
    end
    pcall(float_wnd_destroy, wnd)
end

-- FlyWithLua calls this when the window is closed (the cross in the title bar).
-- Drawing and creating windows is not allowed here, so only bookkeeping.
function nwp_onclose(wnd)
    S.wnd, xpnw_wnd, xpnw_visible = nil, nil, false
end

-- ---- the contents ---------------------------------------------------------

function nwp_build(wnd, x, y)
    local u     = S.scale or ui_scale()
    local pad_x = PAD_X * u
    local pad_y = PAD_Y * u

    if type(imgui.SetWindowFontScale) == "function" then
        imgui.SetWindowFontScale(u)
    elseif S.scale_missing == nil then
        S.scale_missing = true
        logMsg("nearby_weather: imgui.SetWindowFontScale() is missing - the text will be small")
    end

    -- Paint the panel ourselves: ImGui fills its window background before the
    -- builder is called, so a colour pushed here would only reach child
    -- windows.  Drawing into the window's own draw list is the reliable way to
    -- get an opaque panel with an accent line and a visible border.
    local win_w, win_h = imgui.GetWindowSize()
    imgui.DrawList_AddRectFilled(0, 0, win_w, win_h, COL.panel, 0, 0)
    local accent_h = math.max(2, math.floor(2 * u))
    imgui.DrawList_AddRectFilled(0, 0, win_w, accent_h, COL.accent, 0, 0)
    imgui.DrawList_AddRect(0, 0, win_w - 1, win_h - 1, COL.border, 0, 1, 0)

    imgui.PushStyleVar_2(imgui.constant.StyleVar.WindowPadding, pad_x, pad_y)
    imgui.PushStyleVar_2(imgui.constant.StyleVar.ItemSpacing, 6 * u, 5 * u)

    -- header ---------------------------------------------------------------
    local row_w = imgui.GetContentRegionAvail()
    panel_text("NEARBY METAR & TIME", COL.accent)
    if S.status and S.status ~= "" then
        panel_same_line(pad_x + row_w - imgui.CalcTextSize(S.status))
        panel_text(S.status, COL.faint)
    end
    imgui.Separator()

    -- one block per airport -------------------------------------------------
    for index, entry in ipairs(S.display) do
        local apt  = entry.apt
        local name = apt.name or ""
        if #name > 34 then name = name:sub(1, 33) .. "..." end
        local dist = string.format("%.1f NM  %03.0f", entry.dist, entry.brg or 0)
        row_w = imgui.GetContentRegionAvail()

        panel_text(apt.id, COL.text)
        panel_same_line(pad_x + imgui.CalcTextSize(apt.id) + 8 * u)
        panel_text(name, COL.dim)
        panel_same_line(pad_x + row_w - imgui.CalcTextSize(dist))
        panel_text(dist, COL.dim)

        local detail = string.format("RWY %s ft %s    elev %s ft",
                                     commas(apt.ft), surface_name(apt.surf), commas(apt.elev))
        if entry.parsed then
            local chip   = entry.parsed.category .. (entry.parsed.speci and " SPECI" or "")
            local body_x = imgui.CalcTextSize(chip) + 10 * u
            local body   = wrap_text(entry.parsed.text, row_w - body_x)
            panel_text(chip, entry.parsed.colour)
            panel_same_line(pad_x + body_x)
            panel_text(body[1], COL.text)
            for i = 2, #body do
                imgui.Indent(body_x)
                panel_text(body[i], COL.text)
                imgui.Unindent(body_x)
            end
            local age = age_text(entry.parsed)
            if age then detail = age .. "    " .. detail end
        else
            panel_text("--", COL.faint)
            panel_same_line(pad_x + 70 * u)
            panel_text("no METAR reported by X-Plane for this station", COL.faint)
        end
        panel_text(detail, COL.faint)

        if index < #S.display then imgui.Separator() end
    end

    if #S.display == 0 then
        local message
        if S.scan_error then
            message = "airport database unavailable - see Log.txt"
        elseif S.scan or not S.db then
            message = "reading X-Plane's airport database, please wait"
        else
            message = string.format("no usable airport within %.0f NM", CFG.search_radius_nm)
        end
        panel_text(message, COL.faint)
    elseif #S.display < CFG.airport_count then
        panel_text(string.format("no further usable airport within %.0f NM", CFG.search_radius_nm),
                   COL.faint)
    end

    -- clocks ---------------------------------------------------------------
    imgui.Separator()
    local label_x = 118 * u
    local function clock_row(label, value)
        panel_text(label, COL.dim)
        panel_same_line(pad_x + label_x)
        panel_text(value, COL.text)
    end

    local zulu_clock  = seconds_to_clock(xpnw_zulu_sec)
    local local_clock = seconds_to_clock(xpnw_local_sec)
    local offset_hours
    if xpnw_zulu_sec and xpnw_local_sec then
        local delta = (xpnw_local_sec - xpnw_zulu_sec) % 86400
        if delta > 50400 then delta = delta - 86400 end   -- keep it in -12h..+14h
        offset_hours = delta / 3600
    end
    local offset_text = offset_label(offset_hours)
    local zone = ""
    if offset_hours and CFG.zone_table then
        local label = zone_label(LATITUDE or 0, LONGITUDE or 0, offset_hours)
        if label then zone = "  " .. label end
    end

    clock_row("Zulu (UTC)", zulu_clock .. "Z")
    clock_row("Local", local_clock)
    clock_row("Zone", offset_text .. zone)

    imgui.PopStyleVar(2)
end

-- ===========================================================================
-- 12. Key binding, FlyWithLua menu entry and callbacks
-- ===========================================================================

function nwp_toggle()
    if S.wnd then nwp_hide() else nwp_show() end
end

create_command(
    "FlyWithLua/nearby_weather/toggle",
    "Nearby METAR & time: show/hide the weather panel",
    "nwp_toggle()",
    "", ""
)

add_macro("Nearby METAR & time: show/hide", "nwp_toggle()")

do_every_frame("nwp_step()")
do_often("nwp_update()")

if CFG.scan_on_load then
    start_scan()
end

-- The window is gone after a reload, so open it again if it was open before.
if xpnw_visible then
    nwp_show()
end

logMsg("nearby_weather: ready - bind a key to FlyWithLua/nearby_weather/toggle")
