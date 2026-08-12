-- ============================================================================
-- Luman Weather - server commands
--
-- Admin commands are registered as restricted (ace permissions), see
-- permissions.cfg. Player commands (/forecast, /mytime, ...) are granted to
-- everyone there.
-- ============================================================================

local printMessage = LumanWeather.printMessage

RegisterCommand("weather", function(source, args, raw)
    local weather = args[1] and args[1] or LumanWeather.getWeather()
    local transition = tonumber(args[2]) or 10.0
    local freeze = args[3] == "1"
    local permanentSnow = args[4] == "1"

    if transition <= 0.0 then
        transition = 0.1
    end

    if TableContains(Config.weatherTypes, weather) then
        LumanWeather.setWeather(weather, transition + 0.0, freeze, permanentSnow)
    else
        printMessage(source, {color = {255, 0, 0}, args = {L("error.label"), L("error.unknownWeatherType", weather)}})
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

        LumanWeather.setTime(d, h, m, s, t, f)
    else
        printMessage(source, {color = {255, 255, 128}, args = {L("server.time"), FormatTime(LumanWeather.getTimeSeconds())}})
    end
end, true)

RegisterCommand("timescale", function(source, args, raw)
    local scale = tonumber(args[1])

    if scale then
        LumanWeather.setTimescale(scale + 0.0)
    else
        printMessage(source, {color = {255, 255, 128}, args = {L("server.timescale"), LumanWeather.getState().timescale}})
    end
end, true)

RegisterCommand("syncdelay", function(source, args, raw)
    local delay = tonumber(args[1])

    if delay and delay >= 100 then
        LumanWeather.setSyncDelay(delay)
    else
        printMessage(source, {color = {255, 255, 128}, args = {L("server.syncDelay"), string.format("%d%s", LumanWeather.getState().syncDelay, L("units.ms"))}})
    end
end, true)

RegisterCommand("wind", function(source, args, raw)
    if #args > 0 then
        local direction = (tonumber(args[1]) or 0.0) + 0.0
        local speed = (tonumber(args[2]) or 0.0) + 0.0
        local frozen = args[3] == "1"

        LumanWeather.setWind(direction, speed, frozen)
    end
end, true)

RegisterCommand("forecast", function(source, args, raw)
    if source and source > 0 then
        TriggerClientEvent("luman-weather:toggleForecast", source)
    else
        local forecast = LumanWeather.getForecast()

        printMessage(source, {args = {L("forecast.title")}})
        printMessage(source, {args = {L("forecast.separator")}})
        for i = 1, #forecast do
            local time = string.format("%s %.2d:%.2d", GetDayLabel(forecast[i].day), forecast[i].hour, forecast[i].minute)
            printMessage(source, {args = {time, GetWeatherLabel(forecast[i].weather)}})
        end
        printMessage(source, {args = {L("forecast.separator")}})
    end
end, true)

RegisterCommand("weatherui", function(source, args, raw)
    if source and source > 0 then
        local state = LumanWeather.getState()
        TriggerClientEvent("luman-weather:openAdminUi", source, state.weather, state.time, state.timescale, state.windDirection, state.windSpeed, state.syncDelay)
    end
end, true)

RegisterCommand("weathersync", function(source, args, raw)
    if source and source > 0 then
        TriggerClientEvent("luman-weather:toggleSync", source)
    end
end, true)

RegisterCommand("mytime", function(source, args, raw)
    if source and source > 0 then
        local h = tonumber(args[1]) or 0
        local m = tonumber(args[2]) or 0
        local s = tonumber(args[3]) or 0
        local t = tonumber(args[4]) or 0

        TriggerClientEvent("luman-weather:setMyTime", source, h, m, s, t)
    end
end, true)

RegisterCommand("myweather", function(source, args, raw)
    if source and source > 0 then
        local weather = args[1] and args[1] or LumanWeather.getWeather()
        local transition = tonumber(args[2]) or 5.0
        local permanentSnow = args[3] == "1"

        TriggerClientEvent("luman-weather:setMyWeather", source, weather, transition, permanentSnow)
    end
end, true)

RegisterCommand("weatherdebug_sv", function(source, args, raw)
    local enabled = LumanWeather.toggleDebug()
    local message = L("debug.server", enabled and L("debug.on") or L("debug.off"))

    LumanWeather.log(enabled and "success" or "default", message)
    printMessage(source, {color = {255, 255, 128}, args = {L("prefix"), message}})
end, true)

RegisterCommand("weatherstats", function(source, args, raw)
    local state = LumanWeather.getState()
    local stats = LumanWeather.getStats()

    printMessage(source, {color = {100, 200, 255}, args = {L("stats.title")}})
    printMessage(source, {color = {255, 255, 255}, args = {L("stats.weather"), state.weather}})
    printMessage(source, {color = {255, 255, 255}, args = {L("stats.time"), FormatTime(state.time)}})
    printMessage(source, {color = {255, 255, 255}, args = {L("stats.timescale"), string.format("%.2f", state.timescale)}})
    printMessage(source, {color = {255, 255, 255}, args = {L("stats.timeFrozen"), tostring(state.timeFrozen)}})
    printMessage(source, {color = {255, 255, 255}, args = {L("stats.weatherFrozen"), tostring(state.weatherFrozen)}})
    printMessage(source, {color = {255, 255, 255}, args = {L("stats.windFrozen"), tostring(state.windFrozen)}})
    printMessage(source, {color = {255, 255, 255}, args = {L("stats.windDirection"), string.format("%.1f° %s", state.windDirection, GetCardinalLabel(state.windDirection))}})
    printMessage(source, {color = {255, 255, 255}, args = {L("stats.windSpeed"), string.format("%.1f", state.windSpeed)}})
    printMessage(source, {color = {255, 255, 255}, args = {L("stats.permanentSnow"), tostring(state.permanentSnow)}})
    printMessage(source, {color = {255, 255, 255}, args = {L("stats.syncDelay"), string.format("%d%s", state.syncDelay, L("units.ms"))}})
    printMessage(source, {color = {255, 255, 255}, args = {L("stats.weatherInterval"), string.format("%d%s", state.weatherInterval, L("units.s"))}})
    printMessage(source, {color = {255, 255, 255}, args = {L("stats.players"), #GetPlayers()}})

    printMessage(source, {color = {100, 200, 255}, args = {L("stats.syncTitle")}})
    printMessage(source, {color = {255, 255, 255}, args = {L("stats.weatherChanges"), tostring(stats.weatherChanges)}})
    printMessage(source, {color = {255, 255, 255}, args = {L("stats.timeChanges"), tostring(stats.timeChanges)}})
    printMessage(source, {color = {255, 255, 255}, args = {L("stats.timescaleChanges"), tostring(stats.timescaleChanges)}})
    printMessage(source, {color = {255, 255, 255}, args = {L("stats.windChanges"), tostring(stats.windChanges)}})
    printMessage(source, {color = {255, 255, 255}, args = {L("stats.playerInits"), tostring(stats.playerInits)}})

    if stats.lastWeatherChange > 0 then
        printMessage(source, {color = {255, 255, 255}, args = {L("stats.lastWeather"), L("stats.ago", os.time() - stats.lastWeatherChange)}})
    end

    if stats.lastPlayerInit > 0 then
        printMessage(source, {color = {255, 255, 255}, args = {L("stats.lastPlayerInit"), L("stats.ago", os.time() - stats.lastPlayerInit)}})
    end
end, true)
