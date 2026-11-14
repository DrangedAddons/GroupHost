---------------------------------------------------------
--  GroupHost - realm table
--  Author: Dranged
---------------------------------------------------------
-- WoW Forever hides realms from players, but every group finder listing's
-- party GUID carries the realm ID it lives on ("Party-6801-1-..."). A realm's
-- own name says which datacenter it is in: "CAMWOW AU1 Realm 2 PvP" -> AU1.
--
-- The client only names the realm you are on, so this table is short. It grows
-- in game: each player's addon learns its own realm and shares it with group
-- and guild members who run GroupHost.

local ADDON, NS = ...

-- Realm ID -> datacenter code and realm name. Only realms seen in a client's
-- own login log go here.
NS.KNOWN = {
    [6801] = { dc = "AU1", name = "CAMWOW AU1 Realm 2 PvP" },
    [6936] = { dc = "US2", name = "CAMWOW US2 Realm 10 RP PvP" },
}

-- A realm with no entry takes the location of the closest known realm ID, if
-- one is this close. IDs come in blocks per datacenter (the AU1 and US2 realms
-- above are 135 apart), so near neighbours are very likely the same place.
-- Guesses are marked with a "?" wherever they show.
NS.GUESS_RANGE = 12

-- Location = the letters of the datacenter code.
NS.LOCATION_NAMES = {
    AU = "Australia",
    US = "North America",
    EU = "Europe",
    KR = "Korea",
    TW = "Taiwan",
    BR = "Brazil",
    SA = "South America",
}

-- Filter key for realms with no known or guessed location.
NS.UNKNOWN = "?"
