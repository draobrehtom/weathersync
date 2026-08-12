-- ============================================================================
-- Luman Weather - client core
--
-- Keeps the local clock, applies server weather/wind and translates them for
-- the player's region and altitude. The clock advances entirely locally from
-- the shared network clock - the server only sends events when something
-- changes (weather change, admin command, this player joining).
--
-- The LumanWeather table exposes state and helpers to the other client files
-- (interface.lua, commands.lua, tests.lua).
-- ============================================================================

LumanWeather = {}

local MEAN_SEA_LEVEL = 40.0

-- ============================================================================
-- STATE
-- ============================================================================

-- What is currently applied in the game
local currentWeather = nil
local currentWindDirection = 0.0
local snowOnGround = false

-- Raw (untranslated) state received from the server, kept so region/altitude
-- translation can be re-applied locally as the player moves around the map
local serverWeather = nil
local serverPermanentSnow = false
local serverWindDirection = nil
local serverWindSpeed = 0.0
local appliedWindDirection = nil
local appliedWindSpeed = nil

-- Local clock anchor: game time = baseGameTime + elapsed network time * scale
local baseNetworkTime = 0
local baseGameTime = 0
local currentTimescale = Config.timescale
local timeIsFrozen = false

local syncEnabled = true
local initialized = false

-- Personal overrides (setMyTime/setMyWeather). Stored so the local loops keep
-- re-asserting them while sync is off: a one-shot native call is silently lost
-- if made before the session is live (e.g. a zone firing during character
-- select) or clobbered by a session transition.
local myTimeOverride = nil    -- {h, m, s, holdUntil}
local myWeatherOverride = nil -- {weather, permanentSnow}

-- When set, the next syncCheckResult is delivered to this callback
-- (used by /synccheck and the test suite) instead of being ignored
local pendingSyncCheck = nil

local debugMode = false
local debugStats = {
    lastWeatherSync = 0,
    lastTimeSync = 0,
    weatherSyncCount = 0,
    timeSyncCount = 0,
    lastWindSync = 0,
    windSyncCount = 0
}

-- ============================================================================
-- LOGGING
-- ============================================================================

local function debugLog(message)
    if debugMode then
        print(string.format("^3[Luman Weather Debug]^7 %s", message))
    end
end

LumanWeather.debugLog = debugLog

function LumanWeather.toggleDebug()
    debugMode = not debugMode
    return debugMode
end

-- ============================================================================
-- NATIVES
-- ============================================================================

local function setWeatherNative(weatherType, transitionTime)
    Citizen.InvokeNative(0x59174F1AFE095B5A, GetHashKey(weatherType), true, false, true, transitionTime, false) -- SET_WEATHER_TYPE
end

local function setSnowCoverage(coverageType)
    Citizen.InvokeNative(0xF02A9C330BBFC5C7, coverageType) -- _SET_SNOW_COVERAGE_TYPE
end

local function setTimeNative(hour, minute, second, transitionTime)
    -- The clock is always frozen (last arg true): the tick loop below drives
    -- it, otherwise the game would advance time on its own between updates
    Citizen.InvokeNative(0x669E223E64B1903C, hour, minute, second, transitionTime, true) -- _NETWORK_CLOCK_TIME_OVERRIDE
end

LumanWeather.setWeatherNative = setWeatherNative
LumanWeather.setSnowCoverage = setSnowCoverage

-- ============================================================================
-- REGIONS
-- Weather is translated per region so e.g. rain in the mountains becomes
-- snow. Region checks are simple bounding boxes on the RDR3 map.
-- ============================================================================

local function isInSnowyRegion(x, y, z)
    return (x <= -700.0 and y >= 1090.0) or (x <= -500.0 and y >= 2388.0)
end

local function isInDesertRegion(x, y, z)
    return x <= -2050 and y <= -1750
end

local function isInNorthernRegion(x, y, z)
    return y >= 1050
end

local function isInGuarma(x, y, z)
    return x >= 0 and y <= -4096
end

local function getRegionName(x, y, z)
    if isInSnowyRegion(x, y, z) then
        return "Snowy"
    elseif isInDesertRegion(x, y, z) then
        return "Desert"
    elseif isInNorthernRegion(x, y, z) then
        return "Northern"
    elseif isInGuarma(x, y, z) then
        return "Guarma"
    else
        return "Normal"
    end
end

-- Wet weather becomes snow in cold regions, storms become sandstorms in the
-- desert, and snow never falls on Guarma
local regionWeatherRules = {
    ["rain"]         = {snowy = "snow",           cold = "snow",           desert = "thunder"},
    ["thunderstorm"] = {snowy = "blizzard",       cold = "blizzard",       desert = "rain"},
    ["hurricane"]    = {snowy = "whiteout",       cold = "whiteout",       desert = "sandstorm"},
    ["drizzle"]      = {snowy = "snowlight",      cold = "snowlight",      desert = "sunny"},
    ["shower"]       = {snowy = "groundblizzard", cold = "groundblizzard", desert = "sunny"},
    ["fog"]          = {snowy = "snowlight"},
    ["misty"]        = {snowy = "snowlight"},
    ["snow"]         = {guarma = "sunny"},
    ["snowlight"]    = {guarma = "sunny"},
    ["blizzard"]     = {guarma = "sunny"}
}

local function translateWeatherForRegion(weather, x, y, z)
    local rules = regionWeatherRules[weather]

    if not rules then
        return weather
    end

    if rules.snowy and isInSnowyRegion(x, y, z) then
        return rules.snowy
    end

    if rules.cold and isInNorthernRegion(x, y, z) and GetTemperatureAtCoords(x, y, z) < 0.0 then
        return rules.cold
    end

    if rules.desert and isInDesertRegion(x, y, z) then
        return rules.desert
    end

    if rules.guarma and isInGuarma(x, y, z) then
        return rules.guarma
    end

    return weather
end

local function isSnowyWeather(weather)
    return weather == "blizzard" or weather == "groundblizzard" or weather == "snow"
        or weather == "whiteout" or weather == "snowlight"
end

LumanWeather.translateWeatherForRegion = translateWeatherForRegion
LumanWeather.getRegionName = getRegionName
LumanWeather.isSnowyWeather = isSnowyWeather
LumanWeather.MEAN_SEA_LEVEL = MEAN_SEA_LEVEL

-- Wind shifts direction and gains speed with altitude
local function translateWindForAltitude(direction, speed)
    local ped = PlayerPedId()
    local altitudeSea = GetEntityCoords(ped).z - MEAN_SEA_LEVEL
    local altitudeTerrain = GetEntityHeightAboveGround(ped)

    local directionMultiplier = math.floor(altitudeSea / Config.windShearInterval)
    local speedMultiplier = math.floor(altitudeTerrain / Config.windShearInterval)

    direction = (direction + directionMultiplier * Config.windShearDirection) % 360
    speed = speed + speedMultiplier * Config.windShearSpeed

    return direction, speed
end

-- ============================================================================
-- APPLYING SERVER STATE
-- ============================================================================

-- Apply the current server weather locally, translating it for the player's
-- region. Safe to call repeatedly: only invokes natives when something changes.
local function applyServerWeather(transitionTime)
    if not serverWeather then
        return
    end

    local x, y, z = table.unpack(GetEntityCoords(PlayerPedId()))
    local translatedWeather = translateWeatherForRegion(serverWeather, x, y, z)

    if not currentWeather then
        -- First application after join or re-enabling sync: snap in quickly,
        -- unless the caller explicitly asked for an instant (0) transition
        -- (photo/preview restore needs no visible weather fade).
        if transitionTime > 0.0 then
            transitionTime = 1.0
        end
        setSnowCoverage(0)
        snowOnGround = false
    end

    if serverPermanentSnow or (Config.dynamicSnow and (isInSnowyRegion(x, y, z) or isSnowyWeather(translatedWeather))) then
        if not snowOnGround then
            snowOnGround = true
            setSnowCoverage(3)
        end
    else
        if snowOnGround then
            snowOnGround = false
            setSnowCoverage(0)
        end
    end

    if translatedWeather ~= currentWeather then
        debugLog(string.format("Applying weather: %s -> %s (server: %s, transition: %.1fs)", tostring(currentWeather), translatedWeather, serverWeather, transitionTime))
        setWeatherNative(translatedWeather, transitionTime)
        currentWeather = translatedWeather
    end
end

-- Apply the current server wind locally, translating it for the player's
-- altitude. Safe to call repeatedly: only invokes natives when something changes.
local function applyServerWind()
    if not serverWindDirection then
        return
    end

    local direction, speed = translateWindForAltitude(serverWindDirection, serverWindSpeed)

    if direction ~= appliedWindDirection or speed ~= appliedWindSpeed then
        debugLog(string.format("Applying wind: %.1f° speed %.1f (server: %.1f° speed %.1f)", direction, speed, serverWindDirection, serverWindSpeed))
        SetWindDirection(direction)
        SetWindSpeed(speed)
        appliedWindDirection = direction
        appliedWindSpeed = speed
        currentWindDirection = direction
    end
end

-- ============================================================================
-- LOCAL CLOCK
-- ============================================================================

-- Game time as computed by the local clock. Timescale 0 means real time (1:1).
local function computeLocalTime()
    local scale = currentTimescale == 0 and 1 or currentTimescale

    if not timeIsFrozen and baseNetworkTime > 0 and scale > 0 then
        return math.floor(baseGameTime + (GetNetworkTime() - baseNetworkTime) / 1000 * scale) % WEEK_SECONDS
    end

    return baseGameTime
end

LumanWeather.computeLocalTime = computeLocalTime

-- ============================================================================
-- SYNC TOGGLING & LOCAL OVERRIDES
-- ============================================================================

local function toggleSync()
    currentWeather = nil

    syncEnabled = not syncEnabled

    if syncEnabled then
        -- Re-request the full state from the server: local overrides may have
        -- desynced us, and no periodic sync exists to catch us up
        myTimeOverride = nil
        myWeatherOverride = nil
        TriggerServerEvent("luman-weather:init")
    end

    if Config.Notify then
        TriggerEvent("chat:addMessage", {
            color = {255, 255, 128},
            args = {L("prefix"), syncEnabled and L("sync.on") or L("sync.off")}
        })
    end
end

local function setSyncEnabled(toggle)
    if syncEnabled ~= toggle then
        toggleSync()
    end
end

local function setMyWeather(weather, transition, permanentSnow)
    if syncEnabled then
        toggleSync()
    end

    myWeatherOverride = { weather = weather, permanentSnow = permanentSnow }

    if transition <= 0.0 then
        transition = 0.1
    end

    setWeatherNative(weather, transition)

    if permanentSnow then
        setSnowCoverage(3)
        snowOnGround = true
    else
        setSnowCoverage(0)
        snowOnGround = false
    end
end

local function setMyTime(h, m, s, t)
    if syncEnabled then
        toggleSync()
    end

    -- holdUntil: don't let the re-assert loop (transition 0) snap the clock
    -- while the requested transition is still animating
    myTimeOverride = { h = h, m = m, s = s, holdUntil = GetGameTimer() + (t or 0) }

    setTimeNative(h, m, s, t)
end

LumanWeather.toggleSync = toggleSync
LumanWeather.setSyncEnabled = setSyncEnabled
LumanWeather.setMyWeather = setMyWeather
LumanWeather.setMyTime = setMyTime

exports("toggleSync", toggleSync)
exports("setSyncEnabled", setSyncEnabled)
exports("setMyWeather", setMyWeather)
exports("setMyTime", setMyTime)

exports("isSnowOnGround", function()
    return snowOnGround or IsNextWeatherType("XMAS")
end)

-- ============================================================================
-- STATE ACCESS (for interface.lua, commands.lua, tests.lua)
-- ============================================================================

function LumanWeather.getState()
    return {
        syncEnabled = syncEnabled,
        initialized = initialized,
        weather = currentWeather,
        serverWeather = serverWeather,
        serverPermanentSnow = serverPermanentSnow,
        snowOnGround = snowOnGround,
        windDirection = currentWindDirection,
        serverWindDirection = serverWindDirection,
        serverWindSpeed = serverWindSpeed,
        timescale = currentTimescale,
        timeFrozen = timeIsFrozen,
        baseGameTime = baseGameTime,
        baseNetworkTime = baseNetworkTime
    }
end

function LumanWeather.getDebugStats()
    return debugStats
end

-- Request the authoritative server state and await the answer.
-- Returns nil if the server does not answer within the timeout.
function LumanWeather.fetchServerState(timeout)
    local p = promise.new()
    local done = false

    pendingSyncCheck = function(state)
        if not done then
            done = true
            p:resolve(state)
        end
    end

    TriggerServerEvent("luman-weather:requestSyncCheck")

    SetTimeout(timeout or 3000, function()
        if not done then
            done = true
            pendingSyncCheck = nil
            p:resolve(nil)
        end
    end)

    return Citizen.Await(p)
end

-- ============================================================================
-- NETWORK EVENTS
-- ============================================================================

RegisterNetEvent("luman-weather:changeWeather", function(weather, transitionTime, permanentSnow)
    if not syncEnabled then
        return
    end

    debugStats.weatherSyncCount = debugStats.weatherSyncCount + 1
    debugStats.lastWeatherSync = GetGameTimer()
    debugLog(string.format("Weather change: %s (transition: %.1fs, snow: %s)", weather, transitionTime, tostring(permanentSnow)))

    serverWeather = weather
    serverPermanentSnow = permanentSnow

    applyServerWeather(transitionTime)
end)

RegisterNetEvent("luman-weather:changeTime", function(day, hour, minute, second, transitionTime, freezeTime)
    if not syncEnabled then
        return
    end

    debugStats.timeSyncCount = debugStats.timeSyncCount + 1
    debugStats.lastTimeSync = GetGameTimer()
    debugLog(string.format("Time change: %s %.2d:%.2d:%.2d (transition: %sms, frozen: %s)", GetDayOfWeek(day), hour, minute, second, tostring(transitionTime), tostring(freezeTime)))

    timeIsFrozen = freezeTime

    -- Re-anchor so the tick loop continues from the new time
    baseGameTime = DHMSToTime(day, hour, minute, second)
    baseNetworkTime = GetNetworkTime()

    setTimeNative(hour, minute, second, transitionTime)
end)

RegisterNetEvent("luman-weather:syncBaseTime", function(gameTime, timescale, frozen)
    if not syncEnabled then
        return
    end

    -- The server sends its *current* game time; anchor our clock to it
    baseNetworkTime = GetNetworkTime()
    baseGameTime = gameTime
    currentTimescale = timescale
    timeIsFrozen = frozen

    local d, hour, minute, second = TimeToDHMS(baseGameTime)
    setTimeNative(hour, minute, second, 0)
end)

RegisterNetEvent("luman-weather:changeTimescale", function(scale)
    if not syncEnabled then
        return
    end

    -- Rebase to the current computed game time under the old timescale,
    -- otherwise the clock would jump back to the previous anchor point
    if not timeIsFrozen and baseNetworkTime > 0 then
        local oldScale = currentTimescale == 0 and 1 or currentTimescale
        local elapsed = (GetNetworkTime() - baseNetworkTime) / 1000
        baseGameTime = math.floor(baseGameTime + elapsed * oldScale) % WEEK_SECONDS
    end

    baseNetworkTime = GetNetworkTime()
    currentTimescale = scale
end)

RegisterNetEvent("luman-weather:changeWind", function(direction, speed)
    debugStats.windSyncCount = debugStats.windSyncCount + 1
    debugStats.lastWindSync = GetGameTimer()
    debugLog(string.format("Wind change: %.1f°, speed: %.1f", direction, speed))

    serverWindDirection = direction
    serverWindSpeed = speed

    applyServerWind()
end)

RegisterNetEvent("luman-weather:syncCheckResult", function(svTime, svWeather, svWindDirection, svWindSpeed, svTimescale, svFrozen)
    if pendingSyncCheck then
        local deliver = pendingSyncCheck
        pendingSyncCheck = nil
        deliver({
            time = svTime,
            weather = svWeather,
            windDirection = svWindDirection,
            windSpeed = svWindSpeed,
            timescale = svTimescale,
            frozen = svFrozen
        })
    end
end)

RegisterNetEvent("luman-weather:toggleSync", toggleSync)
RegisterNetEvent("luman-weather:setSyncEnabled", setSyncEnabled)
RegisterNetEvent("luman-weather:setMyWeather", setMyWeather)
RegisterNetEvent("luman-weather:setMyTime", setMyTime)

-- ============================================================================
-- INITIALIZATION & LOCAL LOOPS
-- ============================================================================

local function init()
    if initialized then
        return
    end
    initialized = true

    SetNuiFocus(false, false)

    TriggerServerEvent("luman-weather:init")

    -- Local clock: advances game time from the shared network clock without
    -- any server communication. With sync off it keeps re-asserting the
    -- personal override instead — the clock override does not survive session
    -- transitions on its own.
    CreateThread(function()
        while true do
            if not syncEnabled then
                if myTimeOverride and GetGameTimer() >= myTimeOverride.holdUntil then
                    setTimeNative(myTimeOverride.h, myTimeOverride.m, myTimeOverride.s, 0)
                end
            elseif not timeIsFrozen and baseNetworkTime > 0 then
                local scale = currentTimescale == 0 and 1 or currentTimescale

                if scale > 0 then
                    local time = computeLocalTime()
                    local d, h, m, s = TimeToDHMS(time)

                    setTimeNative(h, m, s, 0)
                end
            end
            Wait(1000)
        end
    end)

    -- Region/altitude monitor: re-applies the last known server weather and
    -- wind as the player moves, entirely locally (no network traffic).
    -- With sync off, re-asserts the personal weather override the same way.
    CreateThread(function()
        while true do
            Wait(5000)
            if syncEnabled then
                applyServerWeather(10.0)
                applyServerWind()
            elseif myWeatherOverride then
                setWeatherNative(myWeatherOverride.weather, 10.0)
                setSnowCoverage(myWeatherOverride.permanentSnow and 3 or 0)
            end
        end
    end)

    -- Lets commands.lua and tests.lua register their chat suggestions
    TriggerEvent("luman-weather:clientReady")
end

-- Framework-independent: initialize as soon as the network session is up
CreateThread(function()
    while not NetworkIsSessionStarted() do
        Wait(500)
    end

    init()
end)
