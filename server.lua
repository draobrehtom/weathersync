local currentWeather = Config.weather
local currentTimescale = Config.timescale
local weatherPattern = Config.weatherPattern
local weatherInterval = Config.weatherInterval
local timeIsFrozen = Config.timeIsFrozen
local weatherIsFrozen = Config.weatherIsFrozen
local maxForecast = Config.maxForecast
local syncDelay = Config.syncDelay
local currentWindDirection = Config.windDirection
local currentWindSpeed = Config.windSpeed
local windIsFrozen = Config.windIsFrozen
local permanentSnow = Config.permanentSnow

local weatherTicks = 0
local weatherForecast = {}

local dayLength = 86400
local weekLength = 604800

local baseServerTime = GetGameTimer()
local baseGameTime = 0
local currentTime = 0

-- Initialize time based on config
if Config.timescale == 0 then
    -- When using real-time sync, initialize baseGameTime from real server time
    local now = os.date("*t", os.time() + Config.realTimeOffset)
    baseGameTime = now.sec + now.min * 60 + now.hour * 3600 + (now.wday - 1) * dayLength
    currentTime = baseGameTime
else
    baseGameTime = 0
    currentTime = 0
end

local debugMode = true
local syncStats = {
    weatherChanges = 0,
    timeChanges = 0,
    timescaleChanges = 0,
    windChanges = 0,
    playerInits = 0,
    lastWeatherChange = 0,
    lastPlayerInit = 0
}

local logColors = {
    ["default"] = "\x1B[0m",
    ["error"] = "\x1B[31m",
    ["success"] = "\x1B[32m",
    ["info"] = "\x1B[36m",
    ["warning"] = "\x1B[33m"
}

RegisterNetEvent("weathersync:init")
RegisterNetEvent("weathersync:requestUpdatedForecast")
RegisterNetEvent("weathersync:requestUpdatedAdminUi")
RegisterNetEvent("weathersync:setTime")
RegisterNetEvent("weathersync:resetTime")
RegisterNetEvent("weathersync:setTimescale")
RegisterNetEvent("weathersync:resetTimescale")
RegisterNetEvent("weathersync:setWeather")
RegisterNetEvent("weathersync:resetWeather")
RegisterNetEvent("weathersync:setWeatherPattern")
RegisterNetEvent("weathersync:resetWeatherPattern")
RegisterNetEvent("weathersync:setWind")
RegisterNetEvent("weathersync:resetWind")
RegisterNetEvent("weathersync:setSyncDelay")
RegisterNetEvent("weathersync:resetSyncDelay")

local function nextWeather(weather)
    if weatherIsFrozen then
        return weather
    end

    local choices = weatherPattern[weather]

    if not choices then
        return weather
    end

    local c = 0
    local r = math.random(1, 100)

    for weatherType, chance in pairs(choices) do
        c = c + chance
        if r <= c then
            return weatherType
        end
    end

    return weather
end

local function nextWindDirection(direction)
    if windIsFrozen then
        return direction
    end

    return ((direction + math.random(0, 90) - 45) % 360) * 1.0
end

-- ============================================================================
-- FORECAST MANAGEMENT
-- Handles weather forecast queue generation and advancement
-- ============================================================================

local function generateForecast()
    local weather = nextWeather(currentWeather)
    local wind = nextWindDirection(currentWindDirection)

    weatherForecast = {{weather = weather, wind = wind}}

    for i = 2, maxForecast do
        weather = nextWeather(weather)
        wind = nextWindDirection(wind)
        weatherForecast[i] = {weather = weather, wind = wind}
    end
end

local function advanceForecast()
    -- Remove current forecast entry and get last entry
    local next = table.remove(weatherForecast, 1)
    local last = weatherForecast[#weatherForecast]

    -- Generate and append new forecast entry
    table.insert(weatherForecast, {
        weather = nextWeather(last.weather),
        wind = nextWindDirection(last.wind)
    })

    return next
end

-- ============================================================================
-- WEATHER SYNCHRONIZATION
-- Handles weather state changes and client broadcasting
-- ============================================================================

local function applyWeatherChange(newWeather, newWind)
    local weatherChanged = (currentWeather ~= newWeather)
    local windChanged = (currentWindDirection ~= newWind)

    -- Update server state
    currentWeather = newWeather
    currentWindDirection = newWind

    -- Only broadcast if something changed
    if weatherChanged or windChanged then
        syncStats.weatherChanges = syncStats.weatherChanges + 1
        syncStats.lastWeatherChange = os.time()
        debugLog(string.format("Weather change to %s (%.1f°) - broadcasting to all players", currentWeather, currentWindDirection))

        local players = GetPlayers()
        local transition = weatherInterval / (currentTimescale > 0 and currentTimescale or 1) / 4

        for _, playerId in pairs(players) do
            if weatherChanged then
                TriggerClientEvent("weathersync:changeWeather", playerId, currentWeather, transition, permanentSnow)
            end
            if windChanged then
                TriggerClientEvent("weathersync:changeWind", playerId, currentWindDirection, currentWindSpeed)
            end
        end

        return true -- Changed
    else
        debugLog(string.format("Weather tick - no change (still %s)", currentWeather))
        return false -- Not changed
    end
end

-- ============================================================================
-- TIME MANAGEMENT
-- Handles time progression (real-time and timescale modes)
-- ============================================================================

local function updateTime()
    if timeIsFrozen then
        return
    end

    currentTime = getCurrentTime(baseServerTime, currentTimescale, dayLength, weekLength, baseGameTime)
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function contains(t, x)
    for _, v in pairs(t) do
        if v == x then
            return true
        end
    end
    return false
end

local function printMessage(target, message)
    if target and target > 0 then
        TriggerClientEvent("chat:addMessage", target, message)
    else
        print(table.concat(message.args, ": "))
    end
end

local function setWeather(weather, transition, freeze, permSnow, broadcastToAll)
    if broadcastToAll == nil then
        broadcastToAll = true
    end

    syncStats.weatherChanges = syncStats.weatherChanges + 1
    syncStats.lastWeatherChange = os.time()
    debugLog(string.format("Setting weather to %s (transition: %.1fs, frozen: %s, snow: %s, broadcast: %s)", weather, transition, tostring(freeze), tostring(permSnow), tostring(broadcastToAll)))

    if broadcastToAll then
        local players = GetPlayers()
        for _, playerId in pairs(players) do
            TriggerClientEvent("weathersync:changeWeather", playerId, weather, transition, permSnow)
        end
    end

    currentWeather = weather
    weatherIsFrozen = freeze
    permanentSnow = permSnow
    generateForecast()
end

local function getWeather()
    return currentWeather
end

local function resetWeather()
    currentWeather = Config.weather
    weatherIsFrozen = Config.weatherIsFrozen
    permanentSnow = Config.permanentSnow
    generateForecast()
end

function log(label, message)
    local color = logColors[label]

    if not color then
        color = logColors.default
    end

    print(string.format("%s[%s]%s %s", color, label, logColors.default, message))
end

function debugLog(message)
    if debugMode then
        log("info", message)
    end
end

local function validateWeatherPattern(pattern)
    for weather, choices in pairs(pattern) do
        if not pattern[weather] then
            log("error", weather .. " is missing from the weather pattern table")
        end

        local sum = 0

        for nextWeather, chance in pairs(choices) do
            sum = sum + chance
        end

        if sum ~= 100 then
            log("error", weather .. " next stages do not add up to 100")
        end
    end
end

local function setWeatherPattern(pattern)
    validateWeatherPattern(pattern)
    weatherPattern = pattern
    generateForecast()
end

local function resetWeatherPattern()
    weatherPattern = Config.weatherPattern
    generateForecast()
end

local function setTime(d, h, m, s, t, f)
    syncStats.timeChanges = syncStats.timeChanges + 1
    debugLog(string.format("Setting time to %s %.2d:%.2d:%.2d (frozen: %s)", GetDayOfWeek(d), h, m, s, tostring(f)))

    currentTime = DHMSToTime(d, h, m, s)
    timeIsFrozen = f
    baseServerTime = GetGameTimer()
    baseGameTime = currentTime

    local players = GetPlayers()
    for _, playerId in pairs(players) do
        TriggerClientEvent("weathersync:changeTime", playerId, d, h, m, s, t, f)
    end
end

local function getTime()
    local d, h, m, s = TimeToDHMS(currentTime)
    return {day = d, hour = h, minute = m, second = s}
end

local function setTimescale(scale)
    syncStats.timescaleChanges = syncStats.timescaleChanges + 1
    debugLog(string.format("Setting timescale to %.2f", scale))

    currentTimescale = scale
    baseServerTime = GetGameTimer()
    baseGameTime = currentTime

    local players = GetPlayers()
    for _, playerId in pairs(players) do
        TriggerClientEvent("weathersync:changeTimescale", playerId, scale)
    end
end

local function resetTimescale()
    currentTimescale = Config.timescale
end

local function setSyncDelay(delay)
    syncDelay = delay
end

local function resetSyncDelay()
    syncDelay = Config.syncDelay
end

local function setWind(direction, speed, frozen, broadcastToAll)
    if broadcastToAll == nil then
        broadcastToAll = true
    end

    syncStats.windChanges = syncStats.windChanges + 1
    debugLog(string.format("Setting wind to %.1f° speed %.1f (frozen: %s, broadcast: %s)", direction, speed, tostring(frozen), tostring(broadcastToAll)))

    if broadcastToAll then
        local players = GetPlayers()
        for _, playerId in pairs(players) do
            TriggerClientEvent("weathersync:changeWind", playerId, direction, speed)
        end
    end

    currentWindDirection = direction
    currentWindSpeed = speed
    windIsFrozen = frozen
    generateForecast()
end

local function resetWind()
    currentWindDirection = Config.windDirection
    currentWindSpeed = Config.windSpeed
    windIsFrozen = Config.windIsFrozen
    generateForecast()
end

local function getWind()
    return {direction = currentWindDirection, speed = currentWindSpeed}
end

local function createForecast()
    local forecast = {}

    for i = 0, #weatherForecast do
        local d, h, m, s, weather, wind

        if i == 0 then
            d, h, m, s = TimeToDHMS(currentTime)
            weather = currentWeather
            wind = currentWindDirection
        else
            local time = (timeIsFrozen and currentTime or (currentTime + weatherInterval * i) % weekLength)
            d, h, m, s = TimeToDHMS(time - time % weatherInterval)
            weather = weatherForecast[i].weather
            wind = weatherForecast[i].wind
        end

        table.insert(forecast, {day = d, hour = h, minute = m, second = s, weather = weather, wind = wind})
    end

    return forecast
end

local function syncTime(player)
    local day, hour, minute, second = TimeToDHMS(currentTime)
    TriggerClientEvent("weathersync:changeTime", player, day, hour, minute, second, 0, timeIsFrozen)
end

local function syncTimescale(player)
    TriggerClientEvent("weathersync:changeTimescale", player, currentTimescale)
end

local function syncWeather(player)
    local scale = currentTimescale > 0 and currentTimescale or 1
    TriggerClientEvent("weathersync:changeWeather", player, currentWeather, weatherInterval / scale / 4, permanentSnow)
end

local function syncWind(player)
    TriggerClientEvent("weathersync:changeWind", player, currentWindDirection, currentWindSpeed)
end

local function syncBaseTime(player)
    TriggerClientEvent("weathersync:syncBaseTime", player, baseServerTime, baseGameTime, currentTimescale, timeIsFrozen)
end

exports("getTime", getTime)
exports("setTime", setTime)
exports("resetTime", resetTime)
exports("setTimescale", setTimescale)
exports("resetTimescale", resetTimescale)
exports("getWeather", getWeather)
exports("setWeather", function(weather, transition, freeze, permSnow)
    setWeather(weather, transition, freeze, permSnow, true)
end)
exports("resetWeather", resetWeather)
exports("setWeatherPattern", setWeatherPattern)
exports("resetWeatherPattern", resetWeatherPattern)
exports("getWind", getWind)
exports("setWind", function(direction, speed, frozen)
    setWind(direction, speed, frozen, true)
end)
exports("resetWind", resetWind)
exports("setSyncDelay", setSyncDelay)
exports("resetSyncDelay", resetSyncDelay)
exports("getForecast", createForecast)

AddEventHandler("weathersync:setWeather", function(weather, transition, freeze, permSnow)
    setWeather(weather, transition, freeze, permSnow, true)
end)
AddEventHandler("weathersync:resetWeather", resetWeather)
AddEventHandler("weathersync:setWeatherPattern", setWeatherPattern)
AddEventHandler("weathersync:resetWeatherPattern", resetWeatherPattern)
AddEventHandler("weathersync:setTime", setTime)
AddEventHandler("weathersync:resetTime", resetTime)
AddEventHandler("weathersync:setTimescale", setTimescale)
AddEventHandler("weathersync:resetTimescale", resetTimescale)
AddEventHandler("weathersync:setSyncDelay", setSyncDelay)
AddEventHandler("weathersync:resetSyncDelay", resetSyncDelay)
AddEventHandler("weathersync:setWind", function(direction, speed, frozen)
    setWind(direction, speed, frozen, true)
end)
AddEventHandler("weathersync:resetWind", resetWind)

AddEventHandler("weathersync:requestUpdatedForecast", function()
    TriggerClientEvent("weathersync:updateForecast", source, createForecast())
end)

AddEventHandler("weathersync:requestUpdatedAdminUi", function()
    TriggerClientEvent("weathersync:updateAdminUi", source, currentWeather, currentTime, currentTimescale, currentWindDirection, currentWindSpeed, syncDelay)
end)

AddEventHandler("weathersync:init", function()
    syncStats.playerInits = syncStats.playerInits + 1
    syncStats.lastPlayerInit = os.time()
    debugLog(string.format("Player %d initialized weather sync", source))

    syncBaseTime(source)
    syncWeather(source)
    syncWind(source)
    syncTimescale(source)
end)

RegisterCommand("weather", function(source, args, raw)
    local weather = args[1] and args[1] or currentWeather
    local transition = tonumber(args[2]) or 10.0
    local freeze = args[3] == "1"
    local permanentSnow = args[4] == "1"

    if transition <= 0.0 then
        transition = 0.1
    end

    if contains(Config.weatherTypes, weather) then
        setWeather(weather, transition + 0.0, freeze, permanentSnow, true)
    else
        printMessage(source, {color = {255, 0, 0}, args = {"Error", "Unknown weather type: " .. weather}})
    end
end, true)

RegisterCommand("time", function(source, args, raw)
    if #args > 0 then
        local d = tonumber(args[1]) or 0
        local h = tonumber(args[2]) or 0
        local m = tonumber(args[3]) or 0
        local s = tonumber(args[4]) or 0
        local t = tonumber(args[5]) or 0
        local f = args[6] == "1"

        setTime(d, h, m, s, t, f)
    else
        local d, h, m, s = TimeToDHMS(currentTime)
        printMessage(source, {color = {255, 255, 128}, args = {"Time", string.format("%s %.2d:%.2d:%.2d", GetDayOfWeek(d), h, m, s)}})
    end
end, true)

RegisterCommand("timescale", function(source, args, raw)
    if args[1] then
        setTimescale(tonumber(args[1]) + 0.0)
    else
        printMessage(source, {color = {255, 255, 128}, args = {"Timescale", currentTimescale}})
    end
end, true)

RegisterCommand("syncdelay", function(source, args, raw)
    if args[1] then
        setSyncDelay(tonumber(args[1]))
    else
        printMessage(source, {color = {255, 255, 128}, args = {"Sync delay", SyncDelay}})
    end
end, true)

RegisterCommand("wind", function(source, args, raw)
    if #args > 0 then
        local direction = tonumber(args[1]) + 0.0 or 0.0
        local speed = tonumber(args[2]) + 1.0 or 0.0
        local frozen = args[3] == "1"
        setWind(direction, speed, frozen, true)
    end
end, true)

RegisterCommand("forecast", function(source, args, raw)
    if source and source > 0 then
        TriggerClientEvent("weathersync:toggleForecast", source)
    else
        local forecast = createForecast()
        printMessage(source, {args = {"WEATHER FORECAST"}})
        printMessage(source, {args = {"================"}})
        for i = 1, #forecast do
            local time = string.format("%s %.2d:%.2d", GetDayOfWeek(forecast[i].day), forecast[i].hour, forecast[i].minute)
            printMessage(source, {args = {time, forecast[i].weather}})
        end
        printMessage(source, {args = {"================"}})
    end
end, true)

RegisterCommand("weatherui", function(source, args, raw)
    TriggerClientEvent("weathersync:openAdminUi", source, currentWeather, currentTime, currentTimescale, currentWindDirection, currentWindSpeed, syncDelay)
end, true)

RegisterCommand("weathersync", function(source, args, raw)
    TriggerClientEvent("weathersync:toggleSync", source)
end, true)

RegisterCommand("mytime", function(source, args, raw)
    local h = (args[1] and tonumber(args[1]) or 0)
    local m = (args[2] and tonumber(args[2]) or 0)
    local s = (args[3] and tonumber(args[3]) or 0)
    local t = (args[4] and tonumber(args[4]) or 0)
    TriggerClientEvent("weathersync:setMyTime", source, h, m, s, t)
end, true)

RegisterCommand("myweather", function(source, args, raw)
    local weather = (args[1] and args[1] or currentWeather)
    local transition = (args[2] and tonumber(args[2]) or 5.0)
    local permanentSnow = args[3] == "1"
    TriggerClientEvent("weathersync:setMyWeather", source, weather, transition, permanentSnow)
end, true)

RegisterCommand("weatherdebug_sv", function(source, args, raw)
    debugMode = not debugMode
    local message = string.format("Server weather debug: %s", debugMode and "enabled" or "disabled")
    log(debugMode and "success" or "default", message)
    printMessage(source, {color = {255, 255, 128}, args = {"WeatherSync", message}})
end, true)

RegisterCommand("weatherstats", function(source, args, raw)
    local d, h, m, s = TimeToDHMS(currentTime)
    local timeStr = string.format("%s %.2d:%.2d:%.2d", GetDayOfWeek(d), h, m, s)

    printMessage(source, {color = {100, 200, 255}, args = {"=== Server Weather Stats ==="}})
    printMessage(source, {color = {255, 255, 255}, args = {"Current Weather", currentWeather}})
    printMessage(source, {color = {255, 255, 255}, args = {"Current Time", timeStr}})
    printMessage(source, {color = {255, 255, 255}, args = {"Timescale", string.format("%.2f", currentTimescale)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Time Frozen", tostring(timeIsFrozen)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Weather Frozen", tostring(weatherIsFrozen)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Wind Frozen", tostring(windIsFrozen)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Wind Direction", string.format("%.1f° %s", currentWindDirection, GetCardinalDirection(currentWindDirection))}})
    printMessage(source, {color = {255, 255, 255}, args = {"Wind Speed", string.format("%.1f", currentWindSpeed)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Permanent Snow", tostring(permanentSnow)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Sync Delay", string.format("%dms", syncDelay)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Weather Interval", string.format("%ds", weatherInterval)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Connected Players", #GetPlayers()}})

    printMessage(source, {color = {100, 200, 255}, args = {"=== Sync Statistics ==="}})
    printMessage(source, {color = {255, 255, 255}, args = {"Weather Changes", tostring(syncStats.weatherChanges)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Time Changes", tostring(syncStats.timeChanges)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Timescale Changes", tostring(syncStats.timescaleChanges)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Wind Changes", tostring(syncStats.windChanges)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Player Inits", tostring(syncStats.playerInits)}})

    if syncStats.lastWeatherChange > 0 then
        local timeSince = os.time() - syncStats.lastWeatherChange
        printMessage(source, {color = {255, 255, 255}, args = {"Last Weather Change", string.format("%ds ago", timeSince)}})
    end

    if syncStats.lastPlayerInit > 0 then
        local timeSince = os.time() - syncStats.lastPlayerInit
        printMessage(source, {color = {255, 255, 255}, args = {"Last Player Init", string.format("%ds ago", timeSince)}})
    end
end, true)

RegisterCommand("testforecast", function(source, args, raw)
    local forecast = createForecast()
    printMessage(source, {color = {100, 200, 255}, args = {"=== WEATHER FORECAST (TEST) ==="}})

    for i = 1, #forecast do
        local time = string.format("%s %.2d:%.2d", GetDayOfWeek(forecast[i].day), forecast[i].hour, forecast[i].minute)
        local wind = string.format("%s %.1f°", GetCardinalDirection(forecast[i].wind), forecast[i].wind)
        printMessage(source, {color = {255, 255, 255}, args = {time, forecast[i].weather, wind}})
    end
end, true)

CreateThread(function()
    validateWeatherPattern(weatherPattern)

    generateForecast()

    log("success", "WeatherSync initialized successfully")
    log("info", string.format("Initial weather: %s, time: %s", currentWeather, FormatTime(currentTime)))
    log("info", string.format("Timescale: %.2f, sync delay: %dms", currentTimescale, syncDelay))

    while true do
        -- Calculate tick size based on timescale
        local tick = currentTimescale == 0
            and syncDelay / 1000
            or currentTimescale * (syncDelay / 1000)

        -- Update time (handles both real-time and timescale modes)
        updateTime()

        -- Handle weather progression
        if not weatherIsFrozen then
            weatherTicks = weatherTicks + tick

            if weatherTicks >= weatherInterval then
                -- Advance forecast queue and get next weather state
                local nextState = advanceForecast()

                -- Apply weather change (broadcasts only if changed)
                applyWeatherChange(nextState.weather, nextState.wind)

                weatherTicks = 0
            end
        end

        Wait(syncDelay)
    end
end)
