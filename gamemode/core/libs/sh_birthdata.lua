--[[
    Birth Data Library (framework)

    Generic Gregorian-calendar math for character birth dates: month names, days-per-month,
    leap years, day validation/clamping, and date formatting. Consumed by the appearance
    plugin's birth-date vars + picker and the permadeath memorial, so it lives in core/libs
    and loads before plugins.

    A schema overrides the setting-specific bits after load (see the Colony schema's
    libs/sh_birthdata.lua):
      - ws.birthdata.CURRENT_YEAR  -- the in-game year (Colony sets 2200)
      - ws.birthdata.locations     -- the birth-place list
]]--

ws.birthdata = ws.birthdata or {}

-- In-game year for birth-year math + date display. Generic default (the real year); a schema
-- overrides it. (The framework also derives a year via ws.date/ws.config -- unifying the two is
-- a possible follow-up; kept separate here to preserve existing behavior.)
ws.birthdata.CURRENT_YEAR = ws.birthdata.CURRENT_YEAR or tonumber(os.date("%Y")) or 2000

-- Month names
ws.birthdata.months = ws.birthdata.months or {
    "January", "February", "March", "April",
    "May", "June", "July", "August",
    "September", "October", "November", "December"
}

-- Days in each month (non-leap year)
ws.birthdata.daysInMonth = ws.birthdata.daysInMonth or {
    31, 28, 31, 30, 31, 30,
    31, 31, 30, 31, 30, 31
}

-- Birth-place options. Generic default; a schema overrides with its setting's list.
ws.birthdata.locations = ws.birthdata.locations or {
    "Unspecified"
}

-- Check if a year is a leap year
function ws.birthdata.IsLeapYear(year)
    return (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
end

-- Get the maximum days for a given month and birth year
function ws.birthdata.GetMaxDay(month, age)
    month = tonumber(month) or 1
    age = tonumber(age) or 25

    local birthYear = ws.birthdata.CURRENT_YEAR - age
    local maxDays = ws.birthdata.daysInMonth[month] or 31

    -- February leap year check
    if month == 2 and ws.birthdata.IsLeapYear(birthYear) then
        maxDays = 29
    end

    return maxDays
end

-- Calculate birth year from age
function ws.birthdata.GetBirthYear(age)
    return ws.birthdata.CURRENT_YEAR - (tonumber(age) or 25)
end

-- Format a birth date for display
function ws.birthdata.FormatDate(month, day, age)
    month = tonumber(month) or 1
    day = tonumber(day) or 1
    age = tonumber(age) or 25

    local monthName = ws.birthdata.months[month] or "January"
    local year = ws.birthdata.GetBirthYear(age)

    return string.format("%s %d, %d", monthName, day, year)
end

-- Validate (clamp) a day value for a given month and age
function ws.birthdata.ValidateDay(month, day, age)
    local maxDay = ws.birthdata.GetMaxDay(month, age)
    return math.Clamp(tonumber(day) or 1, 1, maxDay)
end

-- Get month name from number
function ws.birthdata.GetMonthName(month)
    return ws.birthdata.months[tonumber(month) or 1] or "January"
end

-- Check if a location is valid (against the current locations list)
function ws.birthdata.IsValidLocation(location)
    for _, loc in ipairs(ws.birthdata.locations) do
        if loc == location then
            return true
        end
    end
    return false
end

-- Get the current in-game date (real month/day, in-game year)
function ws.birthdata.GetCurrentDate()
    local realDate = os.date("*t")
    local monthName = ws.birthdata.months[realDate.month]
    return string.format("%s %d, %d", monthName, realDate.day, ws.birthdata.CURRENT_YEAR)
end
