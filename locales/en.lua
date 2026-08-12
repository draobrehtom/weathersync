Locales["en"] = {
    prefix = "Luman Weather",

    days = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"},

    cardinals = {
        N  = "N",
        NE = "NE",
        E  = "E",
        SE = "SE",
        S  = "S",
        SW = "SW",
        W  = "W",
        NW = "NW"
    },

    regions = {
        Snowy    = "Snowy",
        Desert   = "Desert",
        Northern = "Northern",
        Guarma   = "Guarma",
        Normal   = "Normal"
    },

    units = {
        metres = "m",
        ms     = "ms",
        s      = "s",
        kph    = "kph",
        mph    = "mph"
    },

    weather = {
        blizzard       = "Blizzard",
        clouds         = "Clouds",
        drizzle        = "Drizzle",
        fog            = "Fog",
        groundblizzard = "Ground blizzard",
        hail           = "Hail",
        highpressure   = "High pressure",
        hurricane      = "Hurricane",
        misty          = "Misty",
        overcast       = "Overcast",
        overcastdark   = "Dark overcast",
        rain           = "Rain",
        sandstorm      = "Sandstorm",
        shower         = "Shower",
        sleet          = "Sleet",
        snow           = "Snow",
        snowlight      = "Light snow",
        sunny          = "Sunny",
        thunder        = "Thunder",
        thunderstorm   = "Thunderstorm",
        whiteout       = "Whiteout"
    },

    sync = {
        on  = "on",
        off = "off"
    },

    error = {
        label              = "Error",
        noWeatherType      = "Please specify a weather type",
        invalidWeatherType = "Invalid weather type: %s",
        unknownWeatherType = "Unknown weather type: %s",
        availableTypes     = "Available types"
    },

    debug = {
        label    = "Luman Weather Debug",
        enabled  = "Enabled",
        disabled = "Disabled",
        server   = "Server weather debug: %s",
        on       = "enabled",
        off      = "disabled"
    },

    test = {
        label   = "Test Weather",
        running = "Testing %s -> %s"
    },

    -- /weatherstatus
    status = {
        title          = "=== Weather Sync Status ===",
        syncEnabled    = "Sync Enabled",
        weather        = "Weather",
        unknown        = "unknown",
        time           = "Time",
        timescale      = "Timescale",
        timeFrozen     = "Time Frozen",
        temperature    = "Temperature",
        wind           = "Wind",
        altitudeSea    = "Altitude (Sea)",
        altitudeGround = "Altitude (Ground)",
        snowOnGround   = "Snow on Ground",
        region         = "Region",
        position       = "Position",
        eventsTitle    = "=== Sync Events Received ===",
        weatherSyncs   = "Weather Syncs",
        timeSyncs      = "Time Syncs",
        windSyncs      = "Wind Syncs"
    },

    -- /synccheck
    synccheck = {
        title                = "=== Sync Check ===",
        warning              = "WARNING",
        fail                 = "FAIL",
        ok                   = "OK",
        syncDisabled         = "sync is disabled (/weathersync) — all checks below are expected to fail",
        noInit               = "client init() never ran",
        noBaseTime           = "init() ran but no syncBaseTime received from the server yet",
        noResponse           = "no response from the server within 3s",
        time                 = "TIME",
        clock                = "GAME CLOCK",
        weatherEvent         = "WEATHER EVENT",
        weatherApplied       = "WEATHER APPLIED",
        wind                 = "WIND",
        timescale            = "TIMESCALE",
        timeFrozen           = "TIME FROZEN",
        detailTime           = "server %s, client %s, diff %ds (tolerance %ds)",
        detailClock          = "in-game %.2d:%.2d:%.2d, computed %s, diff %ds",
        detailWeatherEvent   = "server %s, received %s",
        detailWeatherApplied = "expected %s, applied %s (region monitor updates every 5s)",
        detailWind           = "server %.1f°/%.1f, received %s/%.1f",
        detailTimescale      = "server %.2f, client %.2f",
        detailTimeFrozen     = "server %s, client %s",
        none                 = "none"
    },

    -- Server console / admin command replies
    server = {
        time      = "Time",
        timescale = "Timescale",
        syncDelay = "Sync delay"
    },

    forecast = {
        title     = "WEATHER FORECAST",
        separator = "================"
    },

    -- /weatherstats
    stats = {
        title            = "=== Server Weather Stats ===",
        weather          = "Current Weather",
        time             = "Current Time",
        timescale        = "Timescale",
        timeFrozen       = "Time Frozen",
        weatherFrozen    = "Weather Frozen",
        windFrozen       = "Wind Frozen",
        windDirection    = "Wind Direction",
        windSpeed        = "Wind Speed",
        permanentSnow    = "Permanent Snow",
        syncDelay        = "Sync Delay",
        weatherInterval  = "Weather Interval",
        players          = "Connected Players",
        syncTitle        = "=== Sync Statistics ===",
        weatherChanges   = "Weather Changes",
        timeChanges      = "Time Changes",
        timescaleChanges = "Timescale Changes",
        windChanges      = "Wind Changes",
        playerInits      = "Player Inits",
        lastWeather      = "Last Weather Change",
        lastPlayerInit   = "Last Player Init",
        ago              = "%ds ago"
    },

    suggestions = {
        forecast = {
            desc = "Toggle display of weather forecast"
        },
        syncdelay = {
            desc  = "Change the server tick interval",
            delay = "The time in milliseconds between server ticks"
        },
        time = {
            desc       = "Change the time",
            day        = "0 = Sun, 1 = Mon, 2 = Tue, 3 = Wed, 4 = Thu, 5 = Fri, 6 = Sat",
            hour       = "0-23",
            minute     = "0-59",
            second     = "0-59",
            transition = "Transition time in milliseconds",
            freeze     = "0 = don't freeze time, 1 = freeze time"
        },
        timescale = {
            desc  = "Change the rate at which time passes",
            scale = "In-game seconds per real second (0 = real time)"
        },
        weather = {
            desc       = "Change the weather",
            type       = "The type of weather to change to",
            transition = "Transition time in seconds",
            freeze     = "0 = don't freeze weather, 1 = freeze weather",
            snow       = "0 = temporary snow coverage, 1 = permanent snow coverage"
        },
        weatherui = {
            desc = "Open weather admin UI"
        },
        wind = {
            desc      = "Change wind direction and speed",
            direction = "Direction of the wind in degrees",
            speed     = "Minimum wind speed",
            freeze    = "0 = don't freeze wind, 1 = freeze wind"
        },
        weathersync = {
            desc = "Enable/disable weather and time sync"
        },
        mytime = {
            desc       = "Change local time (disables sync)",
            hour       = "0-23",
            minute     = "0-59",
            second     = "0-59",
            transition = "Transition time in milliseconds"
        },
        myweather = {
            desc       = "Change local weather (disables sync)",
            type       = "The type of weather to change to",
            transition = "Transition time in seconds",
            snow       = "0 = no snow on ground, 1 = snow on ground"
        },
        synccheck = {
            desc = "Compare local weather/time state with the server"
        },
        weatherstatus = {
            desc = "Display current weather/time sync status"
        },
        weatherdebug = {
            desc = "Toggle weather sync debug mode"
        },
        testweather = {
            desc    = "Locally preview a weather type",
            weather = "Weather type to test"
        }
    },

    -- Forecast widget and admin UI (sent to NUI on load)
    ui = {
        sync             = "Sync",
        time             = "Time",
        currentTime      = "Current time:",
        day              = "Day:",
        hour             = "Hour:",
        minute           = "Minute:",
        second           = "Second:",
        transition       = "Transition:",
        freezeTime       = "Freeze time:",
        apply            = "Apply",
        timescale        = "Timescale",
        currentTimescale = "Current timescale:",
        setTimescale     = "Set timescale:",
        weather          = "Weather",
        currentType      = "Current type:",
        setType          = "Set type:",
        freezeWeather    = "Freeze weather:",
        permanentSnow    = "Permanent snow:",
        wind             = "Wind",
        currentDirection = "Current direction:",
        currentSpeed     = "Current speed:",
        setDirection     = "Set direction:",
        setSpeed         = "Set speed:",
        freezeWind       = "Freeze wind:",
        close            = "Close"
    }
}
