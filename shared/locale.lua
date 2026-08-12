-- ============================================================================
-- Luman Weather - localization
--
-- Locale files register themselves into Locales; Config.locale picks the one
-- in use, with DEFAULT_LOCALE as a per-key fallback so a partial translation
-- never leaves a blank string.
-- ============================================================================

Locales = {}

DEFAULT_LOCALE = "en"

local function lookup(dict, key)
    local node = dict

    for part in string.gmatch(key, "[^%.]+") do
        if type(node) ~= "table" then
            return nil
        end

        node = node[part]
    end

    return node
end

-- Raw locale value (string or table) for a dotted key
function LGet(key)
    local value = lookup(Locales[Config and Config.locale or DEFAULT_LOCALE], key)

    if value == nil then
        value = lookup(Locales[DEFAULT_LOCALE], key)
    end

    return value
end

-- Translated string; extra arguments are passed to string.format
function L(key, ...)
    local value = LGet(key)

    if type(value) ~= "string" then
        return key
    end

    if select("#", ...) > 0 then
        return string.format(value, ...)
    end

    return value
end

-- Translated entry of a locale lookup table (weather types, regions, ...),
-- falling back to the raw key so identifiers stay readable when untranslated
function LMap(tableKey, key)
    local dict = LGet(tableKey)

    return (type(dict) == "table" and dict[key]) or key
end
