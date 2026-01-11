const gtaWeatherIcons = {
    blizzard:       "❄️",
    clear:          "☀️",
    clearing:       "🌦️",
    clouds:         "⛅",
    extrasunny:     "☀️",
    foggy:          "🌫️",
    halloween:      "🎃",
    neutral:        "🌧️",
    overcast:       "☁️",
    rain:           "🌧️",
    smog:           "🌫️",
    snow:           "🌨️",
    snowlight:      "🌨️",
    thunder:        "⛈️",
    xmas:           "🌨️"
};

const rdrWeatherIcons = {
    blizzard:       "❄️",
    clouds:         "⛅",
    drizzle:        "🌦️",
    fog:            "🌫️",
    groundblizzard: "❄️",
    hail:           "🌨️",
    highpressure:   "☀️",
    hurricane:      "🌀",
    misty:          "🌫️",
    overcast:       "☁️",
    overcastdark:   "☁️",
    rain:           "🌧️",
    sandstorm:      "🌪️",
    shower:         "🌧️",
    sleet:          "🌧️",
    snow:           "🌨️",
    snowlight:      "🌨️",
    sunny:          "☀️",
    thunder:        "🌩️",
    thunderstorm:   "⛈️",
    whiteout:       "❄️"
};



function weatherApp() {
    return {
        // State
        isRDR: false,
        weatherIcons: {},
        forecastVisible: false,
        adminUiVisible: false,

        // Forecast data
        forecast: [],
        temperature: '',
        wind: '',
        syncEnabled: false,
        altitudeSea: 0,
        altitudeTerrain: 0,

        // Current values (readonly)
        current: {
            dayName: '',
            hour: 0,
            min: 0,
            sec: 0,
            timescale: 0,
            weather: '',
            weatherDisplay: '',
            windDirection: 0,
            windSpeed: 0
        },

        // New values to set
        newTime: {
            day: 0,
            hour: 0,
            min: 0,
            sec: 0,
            transition: 5000,
            freeze: false
        },
        newTimescale: 0,
        newWeather: {
            type: 'sunny',
            transition: 5,
            freeze: false,
            permanentSnow: false
        },
        newWind: {
            direction: 0,
            speed: 0,
            freeze: false
        },
        syncDelay: 5000,
        weatherTypes: [],

        // Initialization
        async init() {
            try {
                const resp = await fetch(`https://${GetParentResourceName()}/getGameName`);
                const data = await resp.json();

                if (data.gameName === "rdr3") {
                    this.isRDR = true;
                    this.weatherIcons = rdrWeatherIcons;
                } else {
                    this.isRDR = false;
                    this.weatherIcons = gtaWeatherIcons;
                }
            } catch (error) {
                console.error('Failed to get game name:', error);
                this.isRDR = false;
                this.weatherIcons = gtaWeatherIcons;
            }

            // Only add event listeners once
            if (!window._weatherAppInitialized) {
                window._weatherAppInitialized = true;

                // Listen for messages from game
                window.addEventListener('message', (event) => {
                    this.handleMessage(event.data);
                });

                // Listen for ESC key
                window.addEventListener('keydown', (event) => {
                    if (event.key === 'Escape' && this.adminUiVisible) {
                        this.closeAdminUi();
                    }
                });
            }

            // Initialize custom dropdowns after Alpine is ready
            this.$nextTick(() => {
                if (typeof CustomDropdown !== 'undefined') {
                    CustomDropdown.init();
                }
            });
        },

        // Message handler
        handleMessage(data) {
            switch (data.action) {
                case 'toggleForecast':
                    this.toggleForecast();
                    break;
                case 'updateForecast':
                    this.updateForecast(data);
                    break;
                case 'openAdminUi':
                    this.openAdminUi(data);
                    break;
                case 'updateAdminUi':
                    this.updateAdminUi(data);
                    break;
            }
        },

        // Utility functions
        dayOfWeek(day) {
            return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][day];
        },

        getWeatherIcon(weather) {
            return this.weatherIcons[weather] || weather;
        },

        // Forecast methods
        toggleForecast() {
            this.forecastVisible = !this.forecastVisible;
        },

        updateForecast(data) {
            const forecastData = JSON.parse(data.forecast);

            let prevDay = null;
            this.forecast = forecastData.map(item => {
                const showDay = item.day !== prevDay;
                prevDay = item.day;
                return {
                    ...item,
                    showDay
                };
            });

            this.temperature = data.temperature;
            this.wind = data.wind;
            this.altitudeSea = data.altitudeSea;
            this.altitudeTerrain = data.altitudeTerrain;
            this.syncEnabled = data.syncEnabled;
        },

        // Admin UI methods
        openAdminUi(data) {
            // Pre-load data before showing UI to avoid lag during transition
            if (data && data.weatherTypes) {
                this.updateAdminUi(data);
            }

            // Show UI after data is ready
            this.adminUiVisible = true;

            // Initialize dropdowns when admin UI opens
            this.$nextTick(() => {
                if (typeof CustomDropdown !== 'undefined') {
                    CustomDropdown.init();
                }
            });
        },

        updateAdminUi(data) {
            const weatherTypes = JSON.parse(data.weatherTypes);

            this.current.dayName = this.dayOfWeek(data.day);
            this.current.hour = data.hour;
            this.current.min = data.min;
            this.current.sec = data.sec;
            this.current.timescale = data.timescale;
            this.current.weather = data.weather;
            this.current.weatherDisplay = this.getWeatherIcon(data.weather) + ' ' + data.weather;
            this.current.windDirection = data.windDirection;
            this.current.windSpeed = data.windSpeed;
            this.syncDelay = data.syncDelay;

            // Populate weather types if not already done
            if (this.weatherTypes.length === 0) {
                this.weatherTypes = weatherTypes;
                this.newWeather.type = weatherTypes[0];

                // Wait for Alpine to render options, then initialize dropdown
                this.$nextTick(() => {
                    setTimeout(() => {
                        if (typeof CustomDropdown !== 'undefined') {
                            const select = document.getElementById('weather-type-select');
                            if (select && select.options.length > 0) {
                                CustomDropdown.refresh('#weather-type-select');
                            }
                        }
                    }, 150);
                });
            }
        },

        async closeAdminUi() {
            this.adminUiVisible = false;

            await fetch(`https://${GetParentResourceName()}/closeAdminUi`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: '{}'
            });
        },

        // Apply methods
        async applyTime() {
            await fetch(`https://${GetParentResourceName()}/setTime`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    day: parseInt(this.newTime.day),
                    hour: parseInt(this.newTime.hour),
                    min: parseInt(this.newTime.min),
                    sec: parseInt(this.newTime.sec),
                    transition: parseInt(this.newTime.transition),
                    freeze: this.newTime.freeze
                })
            });
        },

        async applyTimescale() {
            await fetch(`https://${GetParentResourceName()}/setTimescale`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    timescale: parseFloat(this.newTimescale)
                })
            });
        },

        async applyWeather() {
            await fetch(`https://${GetParentResourceName()}/setWeather`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    weather: this.newWeather.type,
                    transition: parseFloat(this.newWeather.transition),
                    freeze: this.newWeather.freeze,
                    permanentSnow: this.newWeather.permanentSnow
                })
            });
        },

        async applyWind() {
            await fetch(`https://${GetParentResourceName()}/setWind`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    windSpeed: parseFloat(this.newWind.speed),
                    windDirection: parseFloat(this.newWind.direction),
                    freeze: this.newWind.freeze
                })
            });
        },

        async applySyncDelay() {
            await fetch(`https://${GetParentResourceName()}/setSyncDelay`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    syncDelay: parseInt(this.syncDelay)
                })
            });
        }
    };
}
