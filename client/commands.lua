-- ============================================================================
-- Luman Weather - client commands
--
-- Diagnostics and local-only commands. Everything here is read-only or
-- affects only this client; server state is changed via server commands.
-- ============================================================================

local function chatMessage(color, ...)
    TriggerEvent("chat:addMessage", {color = color, args = {...}})
end

-- ============================================================================
-- /synccheck
-- Compares the authoritative server state against everything computed and
-- applied locally. All checks should report OK on a healthy server.
-- ============================================================================

RegisterCommand("synccheck", function(source, args, raw)
    CreateThread(function()
        local state = LumanWeather.getState()

        chatMessage({100, 200, 255}, L("synccheck.title"))

        if not state.syncEnabled then
            chatMessage({255, 255, 0}, L("synccheck.warning"), L("synccheck.syncDisabled"))
        end

        if not state.initialized then
            chatMessage({255, 80, 80}, L("synccheck.warning"), L("synccheck.noInit"))
        elseif state.baseNetworkTime == 0 then
            chatMessage({255, 80, 80}, L("synccheck.warning"), L("synccheck.noBaseTime"))
        end

        local server = LumanWeather.fetchServerState(3000)

        if not server then
            chatMessage({255, 80, 80}, L("synccheck.fail"), L("synccheck.noResponse"))
            return
        end

        local function report(label, passed, detail)
            local status = passed and L("synccheck.ok") or L("synccheck.fail")
            chatMessage(passed and {50, 255, 50} or {255, 80, 80}, label, status .. " — " .. detail)
            print(string.format("[synccheck] %s: %s — %s", label, status, detail))
        end

        -- Client clock ticks once a second and events have latency, so allow
        -- up to ~2 ticks of drift
        local scale = server.timescale == 0 and 1 or server.timescale
        local tolerance = scale * 2 + 5

        -- 1. Locally computed game time vs authoritative server time
        local localTime = LumanWeather.computeLocalTime()
        local diff = WrapDiff(localTime, server.time, WEEK_SECONDS)

        report(L("synccheck.time"), diff <= tolerance,
            L("synccheck.detailTime", FormatTime(server.time), FormatTime(localTime), diff, tolerance))

        -- 2. The actual in-game clock vs what we computed (checks the override applied)
        local clockTime = GetClockHours() * 3600 + GetClockMinutes() * 60 + GetClockSeconds()
        local clockDiff = WrapDiff(clockTime, localTime % DAY_SECONDS, DAY_SECONDS)

        report(L("synccheck.clock"), clockDiff <= tolerance,
            L("synccheck.detailClock", GetClockHours(), GetClockMinutes(), GetClockSeconds(), FormatTime(localTime), clockDiff))

        -- 3. Last weather received from the server vs the server's actual state
        report(L("synccheck.weatherEvent"), state.serverWeather == server.weather,
            L("synccheck.detailWeatherEvent", server.weather, tostring(state.serverWeather)))

        -- 4. Weather actually applied vs what should be applied in this region
        local x, y, z = table.unpack(GetEntityCoords(PlayerPedId()))
        local expectedWeather = LumanWeather.translateWeatherForRegion(server.weather, x, y, z)

        report(L("synccheck.weatherApplied"), state.weather == expectedWeather,
            L("synccheck.detailWeatherApplied", expectedWeather, tostring(state.weather)))

        -- 5. Wind, timescale, freeze flag
        report(L("synccheck.wind"), state.serverWindDirection == server.windDirection and state.serverWindSpeed == server.windSpeed,
            L("synccheck.detailWind", server.windDirection, server.windSpeed,
                state.serverWindDirection and string.format("%.1f°", state.serverWindDirection) or L("synccheck.none"), state.serverWindSpeed))

        report(L("synccheck.timescale"), state.timescale == server.timescale,
            L("synccheck.detailTimescale", server.timescale, state.timescale))

        report(L("synccheck.timeFrozen"), state.timeFrozen == server.frozen,
            L("synccheck.detailTimeFrozen", tostring(server.frozen), tostring(state.timeFrozen)))
    end)
end, false)

-- ============================================================================
-- /weatherstatus
-- ============================================================================

RegisterCommand("weatherstatus", function(source, args, raw)
    local state = LumanWeather.getState()

    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local x, y, z = table.unpack(pos)

    local metric = ShouldUseMetricTemperature()
    local temp = metric and math.floor(GetTemperatureAtCoords(x, y, z)) or math.floor(GetTemperatureAtCoords(x, y, z) * 9 / 5 + 32)
    local tempUnit = metric and "C" or "F"

    local windSpeed = metric and math.floor(GetWindSpeed() * 3.6) or math.floor(GetWindSpeed() * 3.6 * 0.621371)
    local windUnit = metric and L("units.kph") or L("units.mph")

    local metres = L("units.metres")

    chatMessage({100, 200, 255}, L("status.title"))
    chatMessage({255, 255, 255}, L("status.syncEnabled"), tostring(state.syncEnabled))
    chatMessage({255, 255, 255}, L("status.weather"), state.weather or L("status.unknown"))
    chatMessage({255, 255, 255}, L("status.time"), FormatTime(LumanWeather.computeLocalTime()))
    chatMessage({255, 255, 255}, L("status.timescale"), string.format("%.2f", state.timescale))
    chatMessage({255, 255, 255}, L("status.timeFrozen"), tostring(state.timeFrozen))
    chatMessage({255, 255, 255}, L("status.temperature"), string.format("%d °%s", temp, tempUnit))
    chatMessage({255, 255, 255}, L("status.wind"), string.format("%d %s %s", windSpeed, windUnit, GetCardinalLabel(state.windDirection)))
    chatMessage({255, 255, 255}, L("status.altitudeSea"), string.format("%d%s", math.floor(pos.z - LumanWeather.MEAN_SEA_LEVEL), metres))
    chatMessage({255, 255, 255}, L("status.altitudeGround"), string.format("%d%s", math.floor(GetEntityHeightAboveGround(ped)), metres))
    chatMessage({255, 255, 255}, L("status.snowOnGround"), tostring(state.snowOnGround))
    chatMessage({255, 255, 255}, L("status.region"), LMap("regions", LumanWeather.getRegionName(x, y, z)))
    chatMessage({255, 255, 255}, L("status.position"), string.format("%.1f, %.1f, %.1f", x, y, z))

    local stats = LumanWeather.getDebugStats()

    chatMessage({100, 200, 255}, L("status.eventsTitle"))
    chatMessage({255, 255, 255}, L("status.weatherSyncs"), tostring(stats.weatherSyncCount))
    chatMessage({255, 255, 255}, L("status.timeSyncs"), tostring(stats.timeSyncCount))
    chatMessage({255, 255, 255}, L("status.windSyncs"), tostring(stats.windSyncCount))
end, false)

-- ============================================================================
-- /weatherdebug and /testweather
-- ============================================================================

RegisterCommand("weatherdebug", function(source, args, raw)
    local enabled = LumanWeather.toggleDebug()
    chatMessage({255, 255, 128}, L("debug.label"), enabled and L("debug.enabled") or L("debug.disabled"))
end, false)

-- Locally preview a weather type with region translation applied
RegisterCommand("testweather", function(source, args, raw)
    if not args[1] then
        chatMessage({255, 0, 0}, L("error.label"), L("error.noWeatherType"))
        return
    end

    if not TableContains(Config.weatherTypes, args[1]) then
        chatMessage({255, 0, 0}, L("error.label"), L("error.invalidWeatherType", args[1]))
        chatMessage({255, 255, 128}, L("error.availableTypes"), table.concat(Config.weatherTypes, ", "))
        return
    end

    local x, y, z = table.unpack(GetEntityCoords(PlayerPedId()))
    local translatedWeather = LumanWeather.translateWeatherForRegion(args[1], x, y, z)

    chatMessage({100, 255, 100}, L("test.label"), L("test.running", args[1], translatedWeather))

    LumanWeather.setWeatherNative(translatedWeather, 5.0)

    if LumanWeather.isSnowyWeather(translatedWeather) then
        LumanWeather.setSnowCoverage(3)
    end
end, false)

-- ============================================================================
-- CHAT SUGGESTIONS
-- ============================================================================

AddEventHandler("luman-weather:clientReady", function()
    TriggerEvent("chat:addSuggestion", "/forecast", L("suggestions.forecast.desc"), {})

    TriggerEvent("chat:addSuggestion", "/syncdelay", L("suggestions.syncdelay.desc"), {
        {name = "delay", help = L("suggestions.syncdelay.delay")}
    })

    TriggerEvent("chat:addSuggestion", "/time", L("suggestions.time.desc"), {
        {name = "day", help = L("suggestions.time.day")},
        {name = "hour", help = L("suggestions.time.hour")},
        {name = "minute", help = L("suggestions.time.minute")},
        {name = "second", help = L("suggestions.time.second")},
        {name = "transition", help = L("suggestions.time.transition")},
        {name = "freeze", help = L("suggestions.time.freeze")}
    })

    TriggerEvent("chat:addSuggestion", "/timescale", L("suggestions.timescale.desc"), {
        {name = "scale", help = L("suggestions.timescale.scale")}
    })

    TriggerEvent("chat:addSuggestion", "/weather", L("suggestions.weather.desc"), {
        {name = "type", help = L("suggestions.weather.type")},
        {name = "transition", help = L("suggestions.weather.transition")},
        {name = "freeze", help = L("suggestions.weather.freeze")},
        {name = "snow", help = L("suggestions.weather.snow")}
    })

    TriggerEvent("chat:addSuggestion", "/weatherui", L("suggestions.weatherui.desc"), {})

    TriggerEvent("chat:addSuggestion", "/wind", L("suggestions.wind.desc"), {
        {name = "direction", help = L("suggestions.wind.direction")},
        {name = "speed", help = L("suggestions.wind.speed")},
        {name = "freeze", help = L("suggestions.wind.freeze")}
    })

    TriggerEvent("chat:addSuggestion", "/weathersync", L("suggestions.weathersync.desc"), {})

    TriggerEvent("chat:addSuggestion", "/mytime", L("suggestions.mytime.desc"), {
        {name = "hour", help = L("suggestions.mytime.hour")},
        {name = "minute", help = L("suggestions.mytime.minute")},
        {name = "second", help = L("suggestions.mytime.second")},
        {name = "transition", help = L("suggestions.mytime.transition")}
    })

    TriggerEvent("chat:addSuggestion", "/myweather", L("suggestions.myweather.desc"), {
        {name = "type", help = L("suggestions.myweather.type")},
        {name = "transition", help = L("suggestions.myweather.transition")},
        {name = "snow", help = L("suggestions.myweather.snow")}
    })

    TriggerEvent("chat:addSuggestion", "/synccheck", L("suggestions.synccheck.desc"), {})
    TriggerEvent("chat:addSuggestion", "/weatherstatus", L("suggestions.weatherstatus.desc"), {})
    TriggerEvent("chat:addSuggestion", "/weatherdebug", L("suggestions.weatherdebug.desc"), {})

    TriggerEvent("chat:addSuggestion", "/testweather", L("suggestions.testweather.desc"), {
        {name = "weather", help = L("suggestions.testweather.weather")}
    })
end)
