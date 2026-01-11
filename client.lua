local meanSeaLevel = 40.0

local currentWeather = nil
local currentWindDirection = 0.0
local snowOnGround = false
local syncEnabled = true

local forecastIsDisplayed = false
local adminUiIsOpen = false

local currentTimescale = Config.timescale

local baseNetworkTime = 0
local baseGameTime = 0
local timeIsFrozen = false

local debugMode = false
local debugStats = {
    lastWeatherSync = 0,
    lastTimeSync = 0,
    weatherSyncCount = 0,
    timeSyncCount = 0,
    lastWindSync = 0,
    windSyncCount = 0
}

RegisterNetEvent("weathersync:changeWeather")
RegisterNetEvent("weathersync:changeTime")
RegisterNetEvent("weathersync:changeTimescale")
RegisterNetEvent("weathersync:changeWind")
RegisterNetEvent("weathersync:toggleForecast")
RegisterNetEvent("weathersync:updateForecast")
RegisterNetEvent("weathersync:openAdminUi")
RegisterNetEvent("weathersync:updateAdminUi")
RegisterNetEvent("weathersync:toggleSync")
RegisterNetEvent("weathersync:setSyncEnabled")
RegisterNetEvent("weathersync:setMyTime")
RegisterNetEvent("weathersync:setMyWeather")
RegisterNetEvent("weathersync:syncBaseTime")

local function setWeather(weatherType, transitionTime)
    Citizen.InvokeNative(0x59174F1AFE095B5A, GetHashKey(weatherType), true, false, true, transitionTime, false) -- SET_WEATHER_TYPE
end

local function setSnowCoverageTypeDirect(coverageType)
    Citizen.InvokeNative(0xF02A9C330BBFC5C7, coverageType) -- _SET_SNOW_COVERAGE_TYPE
end

local function setTime(hour, minute, second, transitionTime, freeze)
    Citizen.InvokeNative(0x669E223E64B1903C, hour, minute, second, transitionTime, true) -- _NETWORK_CLOCK_TIME_OVERRIDE
    print('set tiem called')
end

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

local function translateWeatherForRegion(weather, x, y, z)
    local temp = GetTemperatureAtCoords(x, y, z)

    if weather == "rain" then
        if isInSnowyRegion(x, y, z) then
            return "snow"
        elseif isInNorthernRegion(x, y, z) and temp < 0.0 then
            return "snow"
        elseif isInDesertRegion(x, y, z) then
            return "thunder"
        end
    elseif weather == "thunderstorm" then
        if isInSnowyRegion(x, y, z) then
            return "blizzard"
        elseif isInNorthernRegion(x, y, z) and temp < 0.0 then
            return "blizzard"
        elseif isInDesertRegion(x, y, z) then
            return "rain"
        end
    elseif weather == "hurricane" then
        if isInSnowyRegion(x, y, z) then
            return "whiteout"
        elseif isInNorthernRegion(x, y, z) and temp < 0.0 then
            return "whiteout"
        elseif isInDesertRegion(x, y, z) then
            return "sandstorm"
        end
    elseif weather == "drizzle" then
        if isInSnowyRegion(x, y, z) then
            return "snowlight"
        elseif isInNorthernRegion(x, y, z) and temp < 0.0 then
            return "snowlight"
        elseif isInDesertRegion(x, y, z) then
            return "sunny"
        end
    elseif weather == "shower" then
        if isInSnowyRegion(x, y, z) then
            return "groundblizzard"
        elseif isInNorthernRegion(x, y, z) and temp < 0.0 then
            return "groundblizzard"
        elseif isInDesertRegion(x, y, z) then
            return "sunny"
        end
    elseif weather == "fog" then
        if isInSnowyRegion(x, y, z) then
            return "snowlight"
        end
    elseif weather == "misty" then
        if isInSnowyRegion(x, y, z) then
            return "snowlight"
        end
    elseif weather == "snow" then
        if isInGuarma(x, y, z) then
            return "sunny"
        end
    elseif weather == "snowlight" then
        if isInGuarma(x, y, z) then
            return "sunny"
        end
    elseif weather == "blizzard" then
        if isInGuarma(x, y, z) then
            return "sunny"
        end
    end

    return weather
end

local function isSnowyWeather(weather)
    return weather == "blizzard" or weather == "groundblizzard" or weather == "snow" or weather == "whiteout" or weather == "snowlight"
end

local function translateWindForAltitude(direction, speed)
    local ped = PlayerPedId()
    local altitudeSea = GetEntityCoords(ped).z - meanSeaLevel
    local altitudeTerrain = GetEntityHeightAboveGround(ped)

    local directionMultiplier = math.floor(altitudeSea / Config.windShearInterval)
    local speedMultiplier = math.floor(altitudeTerrain / Config.windShearInterval)

    direction = (direction + directionMultiplier * Config.windShearDirection) % 360
    speed = speed + speedMultiplier * Config.windShearSpeed

    return direction, speed
end

local function updateForecast(forecast)
    local h24 = ShouldUse_24HourClock()

    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local x, y, z = table.unpack(pos)

    for i = 1, #forecast do
        if h24 then
            forecast[i].time = string.format(
                "%.2d:%.2d",
                forecast[i].hour,
                forecast[i].minute)
        else
            local h = forecast[i].hour % 12
            forecast[i].time = string.format(
                "%d:%.2d %s",
                h == 0 and 12 or h,
                forecast[i].minute,
                forecast[i].hour > 12 and "PM" or "AM")
        end

        forecast[i].weather = translateWeatherForRegion(forecast[i].weather, x, y, z)
        forecast[i].wind = GetCardinalDirection(forecast[i].wind)
    end

    -- Get local temperature
    local metric = ShouldUseMetricTemperature()
    local temperature
    local temperatureUnit
    local windSpeed
    local windSpeedUnit
    local tempStr

    if metric then
        temperature = math.floor(GetTemperatureAtCoords(x, y, z))
        temperatureUnit = "C"
    else
        temperature = math.floor(GetTemperatureAtCoords(x, y, z) * 9/5 + 32)
        temperatureUnit = "F"
    end

    tempStr = string.format("%d °%s", temperature, temperatureUnit)

    if metric then
        windSpeed = math.floor(GetWindSpeed() * 3.6)
        windSpeedUnit = "kph"
    else
        windSpeed = math.floor(GetWindSpeed() * 3.6 * 0.621371)
        windSpeedUnit = "mph"
    end

    local windStr = string.format("🌬️ %d %s %s", windSpeed, windSpeedUnit, GetCardinalDirection(currentWindDirection))

    local altitudeSea = string.format("%d", math.floor(pos.z - meanSeaLevel))
    local altitudeTerrain = string.format("%d", math.floor(GetEntityHeightAboveGround(ped)))

    SendNUIMessage({
        action = "updateForecast",
        forecast = json.encode(forecast),
        temperature = tempStr,
        wind = windStr,
        syncEnabled = syncEnabled,
        altitudeSea = altitudeSea,
        altitudeTerrain = altitudeTerrain
    })
end

local function toggleSync()
    currentWeather = nil

    syncEnabled = not syncEnabled

    if Config.Notify then
        TriggerEvent("chat:addMessage", {
            color = {255, 255, 128},
            args = {"Weather Sync", syncEnabled and "on" or "off"}
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

    if transition <= 0.0 then
        transition = 0.1
    end

    setWeather(weather, transition)

    if permanentSnow then
        setSnowCoverageTypeDirect(3)
        snowOnGround = true
    else
        setSnowCoverageTypeDirect(0)
        snowOnGround = false
    end
end

local function setMyTime(h, m, s, t)
    if syncEnabled then
        toggleSync()
    end

    setTime(h, m, s, t, true)
end

exports("toggleSync", toggleSync)
exports("setSyncEnabled", setSyncEnabled)
exports("setMyWeather", setMyWeather)
exports("setMyTime", setMyTime)

exports("isSnowOnGround", function()
    return snowOnGround or IsNextWeatherType("XMAS")
end)

function debugLog(message)
    if debugMode then
        print(string.format("^3[WeatherSync Debug]^7 %s", message))
    end
end

AddEventHandler("weathersync:changeWeather", function(weather, transitionTime, permanentSnow)
    if not syncEnabled then
        return
    end

    debugStats.weatherSyncCount = debugStats.weatherSyncCount + 1
    debugStats.lastWeatherSync = GetGameTimer()
    debugLog(string.format("Weather change: %s (transition: %.1fs, snow: %s)", weather, transitionTime, tostring(permanentSnow)))

    local x, y, z = table.unpack(GetEntityCoords(PlayerPedId()))

    local translatedWeather = translateWeatherForRegion(weather, x, y, z)

    if not currentWeather then
        transitionTime = 1.0
        setSnowCoverageTypeDirect(0)
        snowOnGround = false
    end

    local inSnowyRegion = isInSnowyRegion(x, y, z)

    if permanentSnow or (Config.dynamicSnow and (inSnowyRegion or isSnowyWeather(translatedWeather))) then
        if not snowOnGround then
            snowOnGround = true
            setSnowCoverageTypeDirect(3)
        end
    else
        if snowOnGround then
            snowOnGround = false
            setSnowCoverageTypeDirect(0)
        end
    end

    if translatedWeather ~= currentWeather then
        setWeather(translatedWeather, transitionTime)
        currentWeather = translatedWeather
    end
end)

AddEventHandler("weathersync:changeTime", function(day, hour, minute, second, transitionTime, freezeTime)
    if not syncEnabled then
        return
    end

    debugStats.timeSyncCount = debugStats.timeSyncCount + 1
    debugStats.lastTimeSync = GetGameTimer()
    debugLog(string.format("Time change: %s %.2d:%.2d:%.2d (transition: %dms, frozen: %s)", GetDayOfWeek(day), hour, minute, second, transitionTime, tostring(freezeTime)))

    timeIsFrozen = freezeTime

    -- Update base time to prevent the tick loop from overriding this change
    baseGameTime = DHMSToTime(day, hour, minute, second)
    baseNetworkTime = GetNetworkTime()

    setTime(hour, minute, second, transitionTime, freezeTime)
end)

AddEventHandler("weathersync:syncBaseTime", function(serverTime, gameTime, timescale, frozen)
    print('set base time ,sync enabled', syncEnabled)
    if not syncEnabled then
        return
    end

    baseNetworkTime = GetNetworkTime()
    baseGameTime = gameTime
    currentTimescale = timescale
    timeIsFrozen = frozen

    local d, hour, minute, second = TimeToDHMS(baseGameTime)
    setTime(hour, minute, second, 0, false)
end)

AddEventHandler("weathersync:changeTimescale", function(scale)
    currentTimescale = scale
    baseNetworkTime = GetNetworkTime()
    local d, h, m, s = TimeToDHMS(baseGameTime)
    baseGameTime = DHMSToTime(d, h, m, s)
end)

AddEventHandler("weathersync:changeWind", function(direction, speed)
    debugStats.windSyncCount = debugStats.windSyncCount + 1
    debugStats.lastWindSync = GetGameTimer()

    local originalDirection = direction
    local originalSpeed = speed
    direction, speed = translateWindForAltitude(direction, speed)

    debugLog(string.format("Wind change: %.1f° -> %.1f°, speed: %.1f -> %.1f", originalDirection, direction, originalSpeed, speed))

    SetWindDirection(direction)
    currentWindDirection = direction
    SetWindSpeed(speed)
end)

AddEventHandler("weathersync:toggleForecast", function()
    forecastIsDisplayed = not forecastIsDisplayed

    CreateThread(function()
        while forecastIsDisplayed do
            TriggerServerEvent("weathersync:requestUpdatedForecast")
            Wait(1000)
        end
    end)

    SendNUIMessage({
        action = "toggleForecast"
    })
end)

AddEventHandler("weathersync:updateForecast", updateForecast)

AddEventHandler("weathersync:openAdminUi", function(weather, time, timescale, windDirection, windSpeed, syncDelay)
    adminUiIsOpen = true

    local d, h, m, s = TimeToDHMS(time)

    SetNuiFocus(true, true)

    SendNUIMessage({
        action = "openAdminUi",
        weatherTypes = json.encode(Config.weatherTypes),
        weather = weather,
        day = d,
        hour = h,
        min = m,
        sec = s,
        timescale = timescale,
        windSpeed = windSpeed,
        windDirection = windDirection,
        syncDelay = syncDelay
    })

    CreateThread(function()
        while adminUiIsOpen do
            TriggerServerEvent("weathersync:requestUpdatedAdminUi")
            Wait(1000)
        end
    end)
end)

AddEventHandler("weathersync:updateAdminUi", function(weather, time, timescale, windDirection, windSpeed, syncDelay)
    local d, h, m, s = TimeToDHMS(time)

    SendNUIMessage({
        action = "updateAdminUi",
        weatherTypes = json.encode(Config.weatherTypes),
        weather = weather,
        day = d,
        hour = h,
        min = m,
        sec = s,
        timescale = timescale,
        windSpeed = windSpeed,
        windDirection = windDirection,
        syncDelay = syncDelay
    })
end)

RegisterNUICallback("getGameName", function(data, cb)
    cb({gameName = Config.isRDR and "rdr3" or "gta5"})
end)

RegisterNUICallback("setTime", function(data, cb)
    TriggerServerEvent("weathersync:setTime", data.day, data.hour, data.min, data.sec, data.transition, data.freeze)
    cb({})
end)

RegisterNUICallback("setTimescale", function(data, cb)
    TriggerServerEvent("weathersync:setTimescale", data.timescale * 1.0)
    cb({})
end)

RegisterNUICallback("setWeather", function(data, cb)
    TriggerServerEvent("weathersync:setWeather", data.weather, data.transition * 1.0, data.freeze, data.permanentSnow)
    cb({})
end)

RegisterNUICallback("setWind", function(data, cb)
    TriggerServerEvent("weathersync:setWind", data.windDirection * 1.0, data.windSpeed * 1.0, data.freeze)
    cb({})
end)

RegisterNUICallback("setSyncDelay", function(data, cb)
    TriggerServerEvent("weathersync:setSyncDelay", data.syncDelay)
    cb({})
end)

RegisterNUICallback("closeAdminUi", function(data, cb)
    SetNuiFocus(false, false)
    adminUiIsOpen = false
    cb({})
end)

AddEventHandler("weathersync:setSyncEnabled", setSyncEnabled)
AddEventHandler("weathersync:toggleSync", toggleSync)
AddEventHandler("weathersync:setMyWeather", setMyWeather)
AddEventHandler("weathersync:setMyTime", setMyTime)

function init()
    SetNuiFocus(false, false)

    TriggerEvent("chat:addSuggestion", "/forecast", "Toggle display of weather forecast", {})

    TriggerEvent("chat:addSuggestion", "/syncdelay", "Change how often time/weather are synced.", {
        {name = "delay", help = "The time in milliseconds between syncs"}
    })

    TriggerEvent("chat:addSuggestion", "/time", "Change the time", {
        {name = "day", help = "0 = Sun, 1 = Mon, 2 = Tue, 3 = Wed, 4 = Thu, 5 = Fri, 6 = Sat"},
        {name = "hour", help = "0-23"},
        {name = "minute", help = "0-59"},
        {name = "second", help = "0-59"},
        {name = "transition", help = "Transition time in milliseconds"},
        {name = "freeze", help = "0 = don\"t freeze time, 1 = freeze time"}
    })

    TriggerEvent("chat:addSuggestion", "/timescale", "Change the rate at which time passes", {
        {name = "scale", help = "Number of in-game seconds per real-time second"}
    })

    TriggerEvent("chat:addSuggestion", "/weather", "Change the weather", {
        {name = "type", help = "The type of weather to change to"},
        {name = "transition", help = "Transition time in seconds"},
        {name = "freeze", help = "0 = don\"t freeze weather, 1 = freeze weather"},
        {name = "snow", help = "0 = temporary snow coverage, 1 = permanent snow coverage"}
    })

    TriggerEvent("chat:addSuggestion", "/weatherui", "Open weather admin UI", {})

    TriggerEvent("chat:addSuggestion", "/wind", "Change wind direction and speed", {
        {name = "direction", help = "Direction of the wind in degrees"},
        {name = "speed", help = "Minimum wind speed"},
        {name = "freeze", help = "0 don\"t freeze wind, 1 = freeze wind"}
    })

    TriggerEvent("chat:addSuggestion", "/weathersync", "Enable/disable weather and time sync", {})

    TriggerEvent("chat:addSuggestion", "/mytime", "Change local time (if weathersync is off)", {
        {name = "hour", help = "0-23"},
        {name = "minute", help = "0-59"},
        {name = "second", help = "0-59"},
        {name = "transition", help = "Transition time in milliseconds"}
    })

    TriggerEvent("chat:addSuggestion", "/myweather", "Change local weather (if weathersync is off)", {
        {name = "type", help = "The type of weather to change to"},
        {name = "transition", help = "Transition time in seconds"},
        {name = "snow", help = "0 = no snow on ground, 1 = snow on ground"}
    })

    TriggerEvent("chat:addSuggestion", "/weatherdebug", "Toggle weather sync debug mode", {})

    TriggerEvent("chat:addSuggestion", "/weatherstatus", "Display current weather/time sync status", {})

    TriggerEvent("chat:addSuggestion", "/testweather", "Test weather transition", {
        {name = "weather", help = "Weather type to test"}
    })

    TriggerServerEvent("weathersync:init")

    CreateThread(function()
        while true do
            if syncEnabled and currentTimescale > 0 and not timeIsFrozen then
                local networkTimeDiff = (GetNetworkTime() - baseNetworkTime) / 1000
                local calculatedGameTime = baseGameTime + (networkTimeDiff * currentTimescale)
                local d, h, m, s = TimeToDHMS(math.floor(calculatedGameTime) % 604800)

                setTime(h, m, s, 0, false)
            end
            Wait(1000)
        end
    end)
end

AddEventHandler('RSGCore:Client:OnPlayerLoaded', function()
    init()
end)
CreateThread(function()
    if LocalPlayer.state['isLoggedIn'] then
        init()
    end
end)

RegisterCommand("weatherdebug", function(source, args, raw)
    debugMode = not debugMode
    TriggerEvent("chat:addMessage", {
        color = {255, 255, 128},
        args = {"WeatherSync Debug", debugMode and "Enabled" or "Disabled"}
    })
end, false)

RegisterCommand("weatherstatus", function(source, args, raw)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local x, y, z = table.unpack(pos)

    local d, h, m, s = TimeToDHMS(baseGameTime)
    local timeStr = string.format("%s %.2d:%.2d:%.2d", GetDayOfWeek(d), h, m, s)

    local metric = ShouldUseMetricTemperature()
    local temp = metric and math.floor(GetTemperatureAtCoords(x, y, z)) or math.floor(GetTemperatureAtCoords(x, y, z) * 9/5 + 32)
    local tempUnit = metric and "C" or "F"

    local windSpeed = metric and math.floor(GetWindSpeed() * 3.6) or math.floor(GetWindSpeed() * 3.6 * 0.621371)
    local windUnit = metric and "kph" or "mph"

    local altitudeSea = math.floor(pos.z - meanSeaLevel)
    local altitudeTerrain = math.floor(GetEntityHeightAboveGround(ped))

    local translatedWeather = translateWeatherForRegion(currentWeather or "unknown", x, y, z)

    TriggerEvent("chat:addMessage", {color = {100, 200, 255}, args = {"=== Weather Sync Status ==="}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Sync Enabled", tostring(syncEnabled)}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Weather", translatedWeather or "unknown"}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Time", timeStr}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Timescale", string.format("%.2f", currentTimescale)}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Time Frozen", tostring(timeIsFrozen)}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Temperature", string.format("%d °%s", temp, tempUnit)}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Wind", string.format("%d %s %s", windSpeed, windUnit, GetCardinalDirection(currentWindDirection))}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Altitude (Sea)", string.format("%dm", altitudeSea)}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Altitude (Ground)", string.format("%dm", altitudeTerrain)}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Snow on Ground", tostring(snowOnGround)}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Position", string.format("%.1f, %.1f, %.1f", x, y, z)}})

    if isInSnowyRegion(x, y, z) then
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Region", "Snowy"}})
    elseif isInDesertRegion(x, y, z) then
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Region", "Desert"}})
    elseif isInNorthernRegion(x, y, z) then
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Region", "Northern"}})
    elseif isInGuarma(x, y, z) then
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Region", "Guarma"}})
    else
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Region", "Normal"}})
    end

    if debugMode then
        TriggerEvent("chat:addMessage", {color = {100, 200, 255}, args = {"=== Debug Stats ==="}})
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Weather Syncs", tostring(debugStats.weatherSyncCount)}})
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Time Syncs", tostring(debugStats.timeSyncCount)}})
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Wind Syncs", tostring(debugStats.windSyncCount)}})

        local timeSinceWeatherSync = (GetGameTimer() - debugStats.lastWeatherSync) / 1000
        local timeSinceTimeSync = (GetGameTimer() - debugStats.lastTimeSync) / 1000
        local timeSinceWindSync = (GetGameTimer() - debugStats.lastWindSync) / 1000

        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Last Weather Sync", string.format("%.1fs ago", timeSinceWeatherSync)}})
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Last Time Sync", string.format("%.1fs ago", timeSinceTimeSync)}})
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Last Wind Sync", string.format("%.1fs ago", timeSinceWindSync)}})
    end
end, false)

RegisterCommand("testweather", function(source, args, raw)
    if not args[1] then
        TriggerEvent("chat:addMessage", {
            color = {255, 0, 0},
            args = {"Error", "Please specify a weather type"}
        })
        return
    end

    local testWeather = args[1]
    local found = false

    for _, weatherType in pairs(Config.weatherTypes) do
        if weatherType == testWeather then
            found = true
            break
        end
    end

    if not found then
        TriggerEvent("chat:addMessage", {
            color = {255, 0, 0},
            args = {"Error", "Invalid weather type: " .. testWeather}
        })
        TriggerEvent("chat:addMessage", {
            color = {255, 255, 128},
            args = {"Available types", table.concat(Config.weatherTypes, ", ")}
        })
        return
    end

    local ped = PlayerPedId()
    local x, y, z = table.unpack(GetEntityCoords(ped))
    local translatedWeather = translateWeatherForRegion(testWeather, x, y, z)

    TriggerEvent("chat:addMessage", {
        color = {100, 255, 100},
        args = {"Test Weather", string.format("Testing %s -> %s", testWeather, translatedWeather)}
    })

    setWeather(translatedWeather, 5.0)

    if isSnowyWeather(translatedWeather) then
        setSnowCoverageTypeDirect(3)
    end
end, false)


