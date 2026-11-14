---------------------------------------------------------
--  GroupHost - core
--  Author: Dranged
---------------------------------------------------------
-- Reads the realm ID out of each listing's party GUID, turns it into a host
-- location, tags the listing with it and drops listings from locations the
-- player has unticked.

local ADDON, NS = ...

local PREFIX = "GroupHost"
local SHARE_EVERY = 120   -- seconds between shares to the group
local SHARE_MAX = 10      -- realms sent per share
local SRC_RANK = { shared = 1, self = 2, manual = 3 }

local db, cdb

function NS.Print(msg) print("|cff66ccffGroupHost|r: " .. tostring(msg)) end

---------------------------------------------------------
--  SECTION: Reading values that may be secret
---------------------------------------------------------
local function Secret(v) return issecretvalue and issecretvalue(v) or false end

local function Readable(t)
    return type(t) == "table" and not Secret(t) and not (canaccesstable and not canaccesstable(t))
end

-- realm ID out of "Player-6801-..." or "Party-6801-..."
local function GuidRealm(guid)
    if Secret(guid) or type(guid) ~= "string" then return nil end
    return tonumber(guid:match("^%a+%-(%d+)%-"))
end

---------------------------------------------------------
--  SECTION: Realm lookup
---------------------------------------------------------
-- "AU1" -> "AU"
local function LocOf(dc) return dc and dc:match("^(%a+)") end

-- "CAMWOW AU1 Realm 2 PvP" -> "AU1"
function NS.DcFromName(name)
    if Secret(name) or type(name) ~= "string" then return nil end
    local dc = name:match("(%a+%d+)%s+Realm%s+%d+")
    return dc and dc:upper() or nil
end

function NS.LocationLabel(loc)
    if loc == NS.UNKNOWN then return "Unknown host" end
    local name = NS.LOCATION_NAMES[loc]
    return name and (name .. " (" .. loc .. ")") or loc
end

local cache = {}
function NS.ClearCache() wipe(cache) end

-- What we know about a realm ID, or nil.
-- { id, loc, sure, dc (when sure), near (the datacenter a guess came from), name }
function NS.Lookup(id)
    local e = cache[id]
    if e ~= nil then return e or nil end
    local k = db.learned[id] or NS.KNOWN[id]
    if k then
        e = { id = id, dc = k.dc, loc = LocOf(k.dc), sure = true, name = k.name }
    elseif db.guess then
        local best, bestD
        local function Near(kid, v)
            local d = math.abs(kid - id)
            if d <= NS.GUESS_RANGE and (not bestD or d < bestD) then best, bestD = v, d end
        end
        for kid, v in pairs(NS.KNOWN) do Near(kid, v) end
        for kid, v in pairs(db.learned) do Near(kid, v) end
        if best then e = { id = id, loc = LocOf(best.dc), sure = false, near = best.dc } end
    end
    cache[id] = e or false
    return e
end

-- Stores a realm. A weaker source never replaces a stronger one (your own
-- label beats your own realm's name beats what another player sent).
function NS.Learn(id, dc, name, src)
    local old = db.learned[id]
    if old then
        if SRC_RANK[old.src] > SRC_RANK[src] then return false end
        if old.dc == dc and old.src == src and (not name or old.name == name) then return false end
    elseif src == "shared" and NS.KNOWN[id] then
        return false
    end
    db.learned[id] = { dc = dc, name = name or (old and old.name) or nil, src = src }
    NS.ClearCache()
    return true
end

function NS.Forget(id)
    if not db.learned[id] then return false end
    db.learned[id] = nil
    NS.ClearCache()
    return true
end

-- The realm we are on. Its name is the one realm name the client gives us.
local function LearnSelf()
    local id = GetRealmID and GetRealmID()
    if Secret(id) or type(id) ~= "number" then return end
    NS.myRealm = id
    local name = GetRealmName and GetRealmName()
    local dc = NS.DcFromName(name)
    if dc then NS.Learn(id, dc, name, "self") end
    local e = NS.Lookup(id)
    NS.myLoc = e and e.loc or nil
end

---------------------------------------------------------
--  SECTION: Listings
---------------------------------------------------------
-- The realm ID a listing is hosted on; nil when it can't be read.
function NS.ResultRealm(resultID)
    if resultID == nil or Secret(resultID) then return nil end
    local info = C_LFGList.GetSearchResultInfo(resultID)
    if not Readable(info) then return nil end
    return GuidRealm(info.partyGUID)
end

-- The filter key of a realm ID: its location, or NS.UNKNOWN.
function NS.LocKey(id)
    local e = NS.Lookup(id)
    return e and e.loc or NS.UNKNOWN
end

-- Tag text and colour for a listing: green for your own location, orange for
-- another, grey for unknown. Guesses end in "?" and are dimmer.
function NS.TagOf(resultID)
    local id = NS.ResultRealm(resultID)
    if not id then return nil end
    local e = NS.Lookup(id)
    if not e then return "#" .. id, 0.6, 0.6, 0.6 end
    local r, g, b = 1, 0.82, 0
    if NS.myLoc then
        if e.loc == NS.myLoc then r, g, b = 0.3, 0.9, 0.4 else r, g, b = 1, 0.5, 0.3 end
    end
    if e.sure then return e.dc, r, g, b end
    return e.loc .. "?", r * 0.7, g * 0.7, b * 0.7
end

-- One sentence for tooltips and the realm list.
function NS.HostLine(id)
    local e = NS.Lookup(id)
    if not e then return "unknown (realm " .. id .. ")" end
    if e.sure then
        return e.dc .. ", " .. NS.LocationLabel(e.loc) .. (id == NS.myRealm and " (your realm)" or "")
    end
    return "probably " .. NS.LocationLabel(e.loc) .. " (realm " .. id .. ", close to " .. e.near .. ")"
end

---------------------------------------------------------
--  SECTION: Filter
---------------------------------------------------------
NS.hidden = 0

function NS.FilterActive() return next(cdb.hide) ~= nil end

local function SearchPanel() return LFGListFrame and LFGListFrame.SearchPanel end

-- After the game builds its result list, drop listings from unticked
-- locations. A listing whose realm can't be read always stays.
local function OnResultList(panel)
    NS.hidden = 0
    local res = panel.results
    if NS.FilterActive() and type(res) == "table" then
        local kept = {}
        for i = 1, #res do
            local rid = res[i]
            local id = NS.ResultRealm(rid)
            if not id or not cdb.hide[NS.LocKey(id)] then kept[#kept + 1] = rid end
        end
        NS.hidden = #res - #kept
        if NS.hidden > 0 then
            panel.results = kept
            panel.totalResults = #kept
        end
    end
    if NS.UpdateFilterButton then NS.UpdateFilterButton() end
end

local rowTag = setmetatable({}, { __mode = "k" })

-- Width of a font string's text, capped to the string's own box.
local function TextWidth(fs)
    local w, box = fs:GetStringWidth() or 0, fs:GetWidth() or 0
    if box > 1 then w = math.min(w, box) end
    return w
end

---------------------------------------------------------
--  SECTION: Forever's browse list (LFGBrowseFrame)
---------------------------------------------------------
-- Forever's "Looking For Group" window is the classic-style browse frame, not
-- retail's LFGListFrame. Blizzard's code for it isn't on disk, so everything
-- here goes through the generic ScrollBox calls and checks what it finds.
local browseBox      -- LFGBrowseFrameScrollBox
local browseLists    -- the frame has UpdateResultList (its results table is filtered there)
local pruning

-- result ID out of a ScrollBox element (a plain table or a tree node)
local function ElementResult(data)
    if Secret(data) or type(data) ~= "table" then return nil end
    if type(data.GetData) == "function" then
        local ok, d = pcall(data.GetData, data)
        data = ok and d or nil
    end
    if not Readable(data) then return nil end
    local id = data.resultID
    if type(id) ~= "number" or Secret(id) then return nil end
    return id
end

local function RowResult(row)
    local id = row.resultID
    if type(id) == "number" and not Secret(id) then return id end
    if row.GetElementData then
        local ok, data = pcall(row.GetElementData, row)
        if ok then return ElementResult(data) end
    end
end

-- The row's activity line ("Uldaman"), so the tag can sit right after it.
local function ActivityString(row, resultID)
    local fs = row.ActivityName
    if fs and fs.GetStringWidth then return fs end
    local info = C_LFGList.GetSearchResultInfo(resultID)
    local acts = Readable(info) and info.activityIDs
    local act = Readable(acts) and acts[1]
    local ai = act and not Secret(act) and C_LFGList.GetActivityInfoTable(act)
    if not Readable(ai) then return nil end
    local full, short = ai.fullName, ai.shortName
    if Secret(full) then full = nil end
    if Secret(short) then short = nil end
    for _, r in ipairs({ row:GetRegions() }) do
        if r:GetObjectType() == "FontString" and r:IsShown() then
            local t = r:GetText()
            if t and not Secret(t) and t ~= "" and (t == full or t == short) then return r end
        end
    end
end

local function TagBrowseRow(row)
    if not row or (row.IsForbidden and row:IsForbidden()) then return end
    local fs = rowTag[row]
    local id = db.tags and not row.CategoryLabel and RowResult(row)
    local tag, r, g, b
    if id then tag, r, g, b = NS.TagOf(id) end
    if not tag then
        if fs then fs:Hide() end
        return
    end
    if not fs then
        fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rowTag[row] = fs
    end
    fs:SetText(tag)
    fs:SetTextColor(r, g, b)
    fs:ClearAllPoints()
    local anchor = ActivityString(row, id)
    if anchor then
        fs:SetPoint("LEFT", anchor, "LEFT", TextWidth(anchor) + 8, 0)
    else
        fs:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -12, 8)
    end
    fs:Show()
end

local function TagAllBrowse()
    if not (browseBox and browseBox:IsVisible()) then return end
    browseBox:ForEachFrame(function(row) pcall(TagBrowseRow, row) end)
end

-- Takes listings from unticked locations out of a ScrollBox data provider.
-- Returns how many went.
local function Prune(dp)
    if pruning or not NS.FilterActive() or type(dp) ~= "table" then return 0 end
    if type(dp.RemoveByPredicate) ~= "function" then
        NS.noPrune = true
        return 0
    end
    local hits = 0
    local function Unwanted(data)
        local id = ElementResult(data)
        local realm = id and NS.ResultRealm(id)
        if realm and cdb.hide[NS.LocKey(realm)] then
            hits = hits + 1
            return true
        end
        return false
    end
    pruning = true
    -- some versions remove the first match and return its index, others all
    for _ = 1, 1000 do
        local ok, index = pcall(dp.RemoveByPredicate, dp, Unwanted)
        if not ok or not index then break end
    end
    pruning = false
    return hits
end

-- Takes specific elements (plain entries or tree nodes) out of a provider.
local function RemoveElements(dp, list)
    local function Size()
        if type(dp.GetSize) ~= "function" then return nil end
        local ok, n = pcall(dp.GetSize, dp)
        return ok and type(n) == "number" and n or nil
    end
    local before, tried = Size(), 0
    for _, el in ipairs(list) do
        local done
        if type(el) == "table" and type(el.GetParent) == "function" then
            local ok, parent = pcall(el.GetParent, el)
            if ok and type(parent) == "table" and type(parent.Remove) == "function" then
                done = pcall(parent.Remove, parent, el)
            end
        end
        if not done and type(dp.Remove) == "function" then done = pcall(dp.Remove, dp, el) end
        if done then tried = tried + 1 end
    end
    if tried > 0 and type(dp.Invalidate) == "function" then pcall(dp.Invalidate, dp) end
    local after = Size()
    if before and after then return math.max(0, before - after) end
    return tried
end

-- Safety net: the game can add groups to the list after it was filtered. If a
-- row from an unticked location is on screen, take it out.
local stuck = setmetatable({}, { __mode = "k" })
local sweepQueued
local function Sweep()
    sweepQueued = false
    if not (browseBox and browseBox:IsVisible() and NS.FilterActive()) then return end
    local dp = browseBox.GetDataProvider and browseBox:GetDataProvider()
    if type(dp) ~= "table" or stuck[dp] then return end
    local bad = {}
    browseBox:ForEachFrame(function(row)
        if row.CategoryLabel or not row.GetElementData then return end
        local id = RowResult(row)
        local realm = id and NS.ResultRealm(id)
        if realm and cdb.hide[NS.LocKey(realm)] then
            local ok, el = pcall(row.GetElementData, row)
            if ok and el then bad[#bad + 1] = el end
        end
    end)
    if #bad == 0 then return end
    local n = Prune(dp)
    if n == 0 then n = RemoveElements(dp, bad) end
    NS.sweeps = (NS.sweeps or 0) + 1
    if n == 0 then
        stuck[dp] = true    -- this list can't be edited; don't retry on every repaint
        NS.noPrune = true
    else
        NS.hidden = NS.hidden + n
        if NS.UpdateFilterButton then NS.UpdateFilterButton() end
    end
end

local function QueueSweep()
    if sweepQueued or not NS.FilterActive() then return end
    sweepQueued = true
    C_Timer.After(0, function() pcall(Sweep); sweepQueued = false end)
end

-- The browse window's group tooltip is its own frame, so the host line goes in
-- a small box under it, for whichever row the mouse is on.
local tipBox
local function UpdateBrowseTip(tip)
    local realm
    if db.tooltip and browseBox then
        local id
        browseBox:ForEachFrame(function(row)
            if not id and row:IsVisible() and row:IsMouseOver() then id = RowResult(row) end
        end)
        realm = id and NS.ResultRealm(id)
    end
    if not realm then
        if tipBox then tipBox:Hide() end
        return
    end
    if not tipBox then
        tipBox = CreateFrame("Frame", nil, tip, "BackdropTemplate")
        NS.UI.Backdrop(tipBox, 0.03, 0.03, 0.035, 0.95)
        tipBox:SetPoint("TOPLEFT", tip, "BOTTOMLEFT", 0, -2)
        tipBox.text = tipBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tipBox.text:SetPoint("TOPLEFT", 8, -6)
        tipBox.text:SetJustifyH("LEFT")
    end
    local text = "|cffffd100Host:|r " .. NS.HostLine(realm)
    local p = db.pings[realm]
    if p and p.n > 0 then
        text = text .. ("\n|cffffd100Your ping in their instances:|r %d ms (%d samples)"):format(p.sum / p.n, p.n)
    end
    tipBox.text:SetText(text)
    tipBox:SetSize(math.max(tip:GetWidth() or 0, tipBox.text:GetStringWidth() + 16),
        tipBox.text:GetStringHeight() + 12)
    tipBox:Show()
end

-- What the browse window is made of, saved so a wrong guess can be fixed from
-- the SavedVariables file. Taken once per session, on the first list with rows.
local function Kind(v)
    if Secret(v) then return "secret" end
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
    return t
end

local function Keys(t)
    local out = {}
    if Readable(t) then
        for k, v in pairs(t) do
            if type(k) == "string" or type(k) == "number" then out[tostring(k)] = Kind(v) end
        end
    end
    return out
end

function NS.Debug()
    local BF = _G.LFGBrowseFrame
    local d = { time = time(), browseLists = browseLists or false, noPrune = NS.noPrune or false,
        hasRetailFrame = LFGListFrame ~= nil, hidden = NS.hidden, sweeps = NS.sweeps or 0 }
    d.globals = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and (k:find("^LFGBrowse") or k:find("^LFGVanilla") or k:find("^LFGUtil")) then
            d.globals[k] = type(v)
        end
    end
    d.frame = Keys(BF)
    if browseBox then
        local dp = browseBox.GetDataProvider and browseBox:GetDataProvider()
        d.provider = Keys(dp)
        if type(dp) == "table" then
            d.providerMethods = { RemoveByPredicate = type(dp.RemoveByPredicate), GetRootNode = type(dp.GetRootNode),
                Enumerate = type(dp.Enumerate), GetSize = type(dp.GetSize) }
        end
        d.rows = {}
        browseBox:ForEachFrame(function(row)
            if #d.rows >= 6 then return end
            local entry = { keys = Keys(row), resultID = Kind(RowResult(row)), texts = {} }
            local ok, data = pcall(function() return row:GetElementData() end)
            if ok and type(data) == "table" then
                entry.data = Keys(data)
                if type(data.GetData) == "function" then
                    local ok2, inner = pcall(data.GetData, data)
                    if ok2 then entry.inner = Keys(inner) end
                end
            end
            for _, r in ipairs({ row:GetRegions() }) do
                if r:GetObjectType() == "FontString" then
                    local name
                    for k, v in pairs(row) do if v == r then name = k end end
                    entry.texts[#entry.texts + 1] = tostring(name) .. " = " .. tostring(Kind(r:GetText()))
                end
            end
            d.rows[#d.rows + 1] = entry
        end)
    end
    db.debug = d
    return d
end

local browseDone, debugTaken
local function InstallBrowse()
    local sb, BF = _G.LFGBrowseFrameScrollBox, _G.LFGBrowseFrame
    if browseDone or not (sb and BF and sb.ForEachFrame) then return end
    browseDone = true
    browseBox = sb
    if type(sb.Update) == "function" then
        hooksecurefunc(sb, "Update", function()
            TagAllBrowse()
            QueueSweep()
            if not debugTaken and sb:IsVisible() then
                local any = false
                sb:ForEachFrame(function(row) if RowResult(row) then any = true end end)
                if any then debugTaken = true; pcall(NS.Debug) end
            end
        end)
    end
    if type(BF.UpdateResultList) == "function" then
        browseLists = true
        hooksecurefunc(BF, "UpdateResultList", function(self)
            local ok, err = pcall(OnResultList, self)
            if not ok and not NS.filterErr then NS.filterErr = true; NS.Print("filter error: " .. tostring(err)) end
            -- the game may have drawn the rows before this ran: draw them again
            -- from the trimmed list
            if ok and NS.hidden > 0 and type(self.UpdateResults) == "function" then
                pcall(self.UpdateResults, self)
            end
        end)
    end
    if type(sb.SetDataProvider) == "function" then
        hooksecurefunc(sb, "SetDataProvider", function(_, dp)
            local n = Prune(dp)
            if not browseLists then NS.hidden = n elseif n > 0 then NS.hidden = NS.hidden + n end
            if NS.UpdateFilterButton then NS.UpdateFilterButton() end
        end)
    end
    local tip = _G.LFGBrowseSearchEntryTooltip
    if tip then
        local driver = CreateFrame("Frame", nil, tip)
        local wait = 0
        driver:SetScript("OnUpdate", function(_, dt)
            wait = wait - dt
            if wait > 0 then return end
            wait = 0.1
            pcall(UpdateBrowseTip, tip)
        end)
        tip:HookScript("OnShow", function() wait = 0 end)
    end
    BF:HookScript("OnShow", TagAllBrowse)
    if NS.BuildFilterButton then
        NS.BuildFilterButton(BF, _G.LFGBrowseFrameGroupInviteButton, _G.LFGBrowseFrameSendMessageButton)
    end
end

---------------------------------------------------------
--  SECTION: Refresh
---------------------------------------------------------
-- Rebuild the list from the last search (after a filter or realm change).
function NS.Refilter()
    local SP = SearchPanel()
    if SP and SP:IsVisible() and LFGListSearchPanel_UpdateResultList then
        pcall(LFGListSearchPanel_UpdateResultList, SP)
        if LFGListSearchPanel_UpdateResults then pcall(LFGListSearchPanel_UpdateResults, SP) end
    end
    local BF = _G.LFGBrowseFrame
    if browseBox and BF and BF:IsVisible() then
        if browseLists and type(BF.UpdateResults) == "function" then
            pcall(BF.UpdateResultList, BF)
            pcall(BF.UpdateResults, BF)
        else
            -- no way to rebuild from here: take out what is now unticked, and
            -- the next refresh brings back anything ticked again
            local n = Prune(browseBox.GetDataProvider and browseBox:GetDataProvider())
            NS.hidden = NS.hidden + n
            if not NS.toldRefresh then
                NS.toldRefresh = true
                NS.Print("press the list's refresh button to bring back groups you ticked again")
            end
        end
        TagAllBrowse()
    end
    if NS.UpdateFilterButton then NS.UpdateFilterButton() end
end

-- Repaint the rows without touching which ones show.
function NS.Redraw()
    local SP = SearchPanel()
    if SP and SP:IsVisible() and LFGListSearchPanel_UpdateResults then
        pcall(LFGListSearchPanel_UpdateResults, SP)
    end
    TagAllBrowse()
end

---------------------------------------------------------
--  SECTION: Hooks into retail's group finder (LFGListFrame)
---------------------------------------------------------

-- Blizzard's own rows: the tag sits right after the activity name.
local function TagBlizzardRow(entry)
    local fs = rowTag[entry]
    local anchor = entry.ActivityName or entry.Name
    local tag, r, g, b
    if db.tags and anchor then tag, r, g, b = NS.TagOf(entry.resultID) end
    if not tag then
        if fs then fs:Hide() end
        return
    end
    if not fs then
        fs = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rowTag[entry] = fs
    end
    fs:SetText(tag)
    fs:SetTextColor(r, g, b)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", anchor, "LEFT", TextWidth(anchor) + 6, 0)
    fs:Show()
end

local function AddTooltip(tooltip, resultID)
    if not db.tooltip or not tooltip then return end
    local id = NS.ResultRealm(resultID)
    if not id then return end
    tooltip:AddLine(" ")
    tooltip:AddLine("|cffffd100Host:|r " .. NS.HostLine(id), 1, 1, 1, true)
    local p = db.pings[id]
    if p and p.n > 0 then
        tooltip:AddLine(("|cffffd100Your ping in their instances:|r %d ms (%d samples)"):format(p.sum / p.n, p.n),
            1, 1, 1, true)
    end
    tooltip:Show()
end

local hooked
local function InstallHooks()
    if hooked or not (LFGListFrame and LFGListSearchPanel_UpdateResultList) then return end
    hooked = true
    hooksecurefunc("LFGListSearchPanel_UpdateResultList", function(panel)
        if panel ~= SearchPanel() then return end
        local ok, err = pcall(OnResultList, panel)
        if not ok and not NS.filterErr then NS.filterErr = true; NS.Print("filter error: " .. tostring(err)) end
    end)
    if LFGListSearchEntry_Update then
        hooksecurefunc("LFGListSearchEntry_Update", function(entry) pcall(TagBlizzardRow, entry) end)
    end
    if LFGListUtil_SetSearchEntryTooltip then
        hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", function(tooltip, resultID)
            pcall(AddTooltip, tooltip, resultID)
        end)
    end
    local SP = SearchPanel()
    if NS.BuildFilterButton and SP then NS.BuildFilterButton(SP, SP.SignUpButton, SP.BackButton) end
end

-- EllesmereUI's group finder draws its own rows and asks its module table for
-- a region tag per listing. On Forever that tag comes from the leader's realm
-- name, which doesn't exist, so every group reads "NA". Hand it ours instead.
local euiDone
local function InstallEllesmere()
    if euiDone then return end
    local reg = type(EllesmereUI) == "table" and EllesmereUI._ModuleNS
    local gf = type(reg) == "table" and reg.EllesmereUIGroupFinder
    if type(gf) ~= "table" then return end
    euiDone = true
    local orig = gf.RegionTagOf
    gf.RegionTagOf = function(resultID)
        if db.tags then
            local ok, tag, r, g, b = pcall(NS.TagOf, resultID)
            if ok then return tag, r, g, b end
        end
        if orig then return orig(resultID) end
    end
end

---------------------------------------------------------
--  SECTION: Sharing realms with other GroupHost users
---------------------------------------------------------
-- "R^<realm id>^<datacenter>". Your own labels (/gh set) are never sent.
local lastShare = 0

local function Share(channel)
    if not db.share or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local n = 0
    for id, e in pairs(db.learned) do
        if e.src ~= "manual" and n < SHARE_MAX then
            n = n + 1
            pcall(C_ChatInfo.SendAddonMessage, PREFIX, "R^" .. id .. "^" .. e.dc, channel)
        end
    end
end

local function ShareWithGroup()
    if not (IsInGroup and IsInGroup()) then return end
    local now = GetTime()
    if now - lastShare < SHARE_EVERY then return end
    lastShare = now
    Share((IsInRaid and IsInRaid()) and "RAID" or "PARTY")
end

local function OnAddonMessage(prefix, msg)
    if prefix ~= PREFIX or Secret(msg) or type(msg) ~= "string" then return end
    local id, dc = msg:match("^R%^(%d+)%^(%a+%d+)$")
    id = tonumber(id)
    if not id or id < 1 or id > 999999 or #dc > 6 then return end
    if NS.Learn(id, dc:upper(), nil, "shared") then
        LearnSelf()
        NS.Refilter()
        if NS.UI and NS.UI.RefreshAll then NS.UI.RefreshAll() end
    end
end

---------------------------------------------------------
--  SECTION: Instance ping per host realm
---------------------------------------------------------
-- While in an instance with a group, log our world ping under the group
-- leader's realm ID. It shows in listing tooltips and the realm list, and it
-- is the only measure of a realm nobody has named yet.
local function LeaderRealm()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if n == 0 then return nil end
    local raid = IsInRaid and IsInRaid()
    for i = 1, n do
        local unit = raid and ("raid" .. i) or (i == n and "player" or ("party" .. i))
        if UnitIsGroupLeader(unit) then return GuidRealm(UnitGUID(unit)) end
    end
end

local function SamplePing()
    if not IsInInstance() then return end
    local realm = LeaderRealm()
    local _, _, _, world = GetNetStats()
    if not realm or Secret(world) or type(world) ~= "number" or world <= 0 then return end
    local p = db.pings[realm] or { n = 0, sum = 0, min = world, max = world }
    p.n, p.sum = p.n + 1, p.sum + world
    p.min, p.max = math.min(p.min, world), math.max(p.max, world)
    db.pings[realm] = p
end

---------------------------------------------------------
--  SECTION: Realm list for the settings window
---------------------------------------------------------
-- Every realm we can say something about, lowest ID first.
function NS.RealmRows()
    local seen, rows = {}, {}
    local function Add(id)
        if seen[id] then return end
        seen[id] = true
        local e, l = NS.Lookup(id), db.learned[id]
        rows[#rows + 1] = {
            id = id,
            dc = e and (e.sure and e.dc or (e.loc .. "?")) or "?",
            name = e and e.name or nil,
            src = l and l.src or (NS.KNOWN[id] and "built in") or nil,
            ping = db.pings[id],
            mine = id == NS.myRealm,
        }
    end
    for id in pairs(NS.KNOWN) do Add(id) end
    for id in pairs(db.learned) do Add(id) end
    for id in pairs(db.pings) do Add(id) end
    table.sort(rows, function(a, b) return a.id < b.id end)
    return rows
end

---------------------------------------------------------
--  SECTION: Events
---------------------------------------------------------
local DEFAULTS = { theme = "auto", tags = true, tooltip = true, guess = true, share = true }

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 == ADDON then
            GroupHostDB = type(GroupHostDB) == "table" and GroupHostDB or {}
            GroupHostCharDB = type(GroupHostCharDB) == "table" and GroupHostCharDB or {}
            db, cdb = GroupHostDB, GroupHostCharDB
            for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
            db.learned = type(db.learned) == "table" and db.learned or {}
            db.pings = type(db.pings) == "table" and db.pings or {}
            db.minimap = type(db.minimap) == "table" and db.minimap or { hide = false }
            cdb.hide = type(cdb.hide) == "table" and cdb.hide or {}
            NS.db, NS.cdb = db, cdb
        elseif db then
            -- the group finder loads on demand, under a name that differs by client
            InstallBrowse()
            InstallHooks()
        end
    elseif event == "PLAYER_LOGIN" then
        LearnSelf()
        InstallBrowse()
        InstallHooks()
        InstallEllesmere()
        if NS.InitUI then NS.InitUI() end
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        end
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "CHAT_MSG_ADDON",
            "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_RESULT_UPDATED" }) do
            pcall(frame.RegisterEvent, frame, e)
        end
        if C_Timer then
            C_Timer.NewTicker(30, function() pcall(SamplePing) end)
            C_Timer.After(15, function()
                if IsInGuild and IsInGuild() then Share("GUILD") end
            end)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        LearnSelf()
        InstallBrowse()
        InstallHooks()
        InstallEllesmere()
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" or event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        -- the rows redraw first; tag them on the next frame
        InstallBrowse()
        if browseBox and C_Timer then C_Timer.After(0, TagAllBrowse) end
    elseif event == "GROUP_ROSTER_UPDATE" then
        ShareWithGroup()
    elseif event == "CHAT_MSG_ADDON" then
        OnAddonMessage(a1, a2)
    end
end)

---------------------------------------------------------
--  SECTION: Slash command
---------------------------------------------------------
SLASH_GROUPHOST1 = "/grouphost"
SLASH_GROUPHOST2 = "/gh"
SlashCmdList.GROUPHOST = function(msg)
    if not db then return end
    local cmd, a, b = (msg or ""):match("^%s*(%S*)%s*(%S*)%s*(%S*)")
    cmd = cmd:lower()
    if cmd == "" then
        if NS.ToggleWindow then NS.ToggleWindow() end
    elseif cmd == "set" then
        local id, dc = tonumber(a), b:upper()
        if not id or not dc:match("^%a+%d+$") then
            NS.Print("usage: /gh set <realm id> <datacenter>, for example /gh set 6934 US2")
            return
        end
        NS.Learn(id, dc, nil, "manual")
        LearnSelf()
        NS.Refilter()
        if NS.UI then NS.UI.RefreshAll() end
        NS.Print("realm " .. id .. " is now " .. dc)
    elseif cmd == "forget" then
        local id = tonumber(a)
        if id and NS.Forget(id) then
            LearnSelf()
            NS.Refilter()
            if NS.UI then NS.UI.RefreshAll() end
            NS.Print("forgot realm " .. id)
        else
            NS.Print("no saved label for that realm")
        end
    elseif cmd == "debug" then
        local ok, err = pcall(NS.Debug)
        NS.Print(ok and "saved what the group finder window is made of. /reload writes it to the SavedVariables file."
            or ("debug failed: " .. tostring(err)))
    elseif cmd == "list" then
        for _, row in ipairs(NS.RealmRows()) do
            NS.Print(("%d  %s%s%s"):format(row.id, row.dc, row.mine and "  (your realm)" or "",
                row.ping and ("  ping " .. math.floor(row.ping.sum / row.ping.n) .. " ms") or ""))
        end
    else
        NS.Print("/gh - open the window")
        NS.Print("/gh set <realm id> <datacenter> - label a realm, e.g. /gh set 6934 US2")
        NS.Print("/gh forget <realm id> - drop a label")
        NS.Print("/gh list - realms known so far")
    end
end

function GroupHost_OnCompartmentClick()
    if NS.ToggleWindow then NS.ToggleWindow() end
end
