---------------------------------------------------------
--  GroupHost - filter dropdown, settings window, launcher
--  Author: Dranged
---------------------------------------------------------

local ADDON, NS = ...
local UI = NS.UI
local ICON = "Interface\\AddOns\\GroupHost\\icon"

---------------------------------------------------------
--  SECTION: Locations offered by the filter
---------------------------------------------------------
-- Your own location first, the others by name, "Unknown host" last.
local function Locations()
    local seen, list = {}, {}
    local function Add(dc)
        local loc = dc and dc:match("^(%a+)")
        if loc and not seen[loc] then
            seen[loc] = true
            list[#list + 1] = loc
        end
    end
    for _, v in pairs(NS.KNOWN) do Add(v.dc) end
    for _, v in pairs(NS.db.learned) do Add(v.dc) end
    table.sort(list, function(a, b)
        if (a == NS.myLoc) ~= (b == NS.myLoc) then return a == NS.myLoc end
        return a < b
    end)
    list[#list + 1] = NS.UNKNOWN
    return list
end

---------------------------------------------------------
--  SECTION: Filter dropdown on the group finder
---------------------------------------------------------
local button, menu, catcher
local checks = {}

local function CloseMenu()
    if menu then menu:Hide() end
    if catcher then catcher:Hide() end
end

-- "Hosts: All", or the locations still shown and how many groups were dropped.
function NS.UpdateFilterButton()
    if not button then return end
    local text = "Hosts: All"
    if NS.FilterActive() then
        local shown = {}
        for _, loc in ipairs(Locations()) do
            if not NS.cdb.hide[loc] then shown[#shown + 1] = loc end
        end
        text = "Hosts: " .. table.concat(shown, ", ")
        if NS.hidden > 0 then text = text .. " (" .. NS.hidden .. " hidden)" end
    end
    button.text:SetText(text)
end

local function SetShown(loc, on)
    local hide = NS.cdb.hide
    hide[loc] = (not on) or nil
    -- never leave nothing ticked: that is an empty list with no way to tell why
    local any = false
    for _, l in ipairs(Locations()) do if not hide[l] then any = true end end
    if not any then
        hide[loc] = nil
        NS.Print("at least one location has to stay ticked")
    end
    NS.Refilter()
    NS.UpdateFilterButton()
end

local function OpenMenu()
    if not menu then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:SetFrameLevel(1)
        catcher:RegisterForClicks("AnyUp")
        catcher:SetScript("OnClick", CloseMenu)
        menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        UI.Backdrop(menu, 0.03, 0.03, 0.035, 0.97)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(50)
        menu:EnableMouse(true)
        menu.title = UI.Text(menu, "Show groups hosted in", "GameFontNormalSmall")
        menu.title:SetPoint("TOPLEFT", 8, -8)
    end
    local locs = Locations()
    local width = 180
    for i, loc in ipairs(locs) do
        local cb = checks[i]
        if not cb then
            cb = UI.Check(menu, "", function() return cb.loc and not NS.cdb.hide[cb.loc] end,
                function(on) if cb.loc then SetShown(cb.loc, on) end end)
            cb:SetPoint("TOPLEFT", 6, -22 - (i - 1) * 24)
            checks[i] = cb
        end
        cb.loc = loc
        cb.label:SetText(NS.LocationLabel(loc) .. (loc == NS.myLoc and "  |cff4de666yours|r" or ""))
        cb:Show()
        cb:Refresh()
        width = math.max(width, cb.label:GetStringWidth() + 48)
    end
    for i = #locs + 1, #checks do
        checks[i].loc = nil
        checks[i]:Hide()
    end
    menu:SetSize(width, 30 + #locs * 24)
    menu:ClearAllPoints()
    menu:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 2)  -- the button sits at the panel's bottom edge
    catcher:Show()
    menu:Show()
end

-- Fits the button into the gap between the window's two bottom buttons.
local leftOf, rightOf
local function Fit()
    local w = 150
    local l, r = leftOf and leftOf:GetRight(), rightOf and rightOf:GetLeft()
    if l and r then w = math.max(80, math.min(190, r - l - 12)) end
    button:SetWidth(w)
end

-- parent: the list window. right / left: its bottom-right and bottom-left
-- buttons (Group Invite and Send Message on Forever).
function NS.BuildFilterButton(parent, right, left)
    local SP = parent
    if button or not SP then return end
    leftOf, rightOf = left, right
    button = CreateFrame("Button", nil, SP, "BackdropTemplate")
    button:SetSize(150, 22)
    UI.Backdrop(button, 0.1, 0.1, 0.11, 1)
    button.text = UI.Text(button, "", "GameFontHighlightSmall")
    button.text:SetPoint("LEFT", 6, 0)
    button.text:SetPoint("RIGHT", -16, 0)
    button.text:SetWordWrap(false)
    local arrow = UI.Text(button, "v", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", -5, 0)
    if right then
        button:SetPoint("RIGHT", right, "LEFT", -6, 0)
    else
        button:SetPoint("BOTTOM", SP, "BOTTOM", 0, 6)
    end
    button:SetFrameLevel(SP:GetFrameLevel() + 20)
    button:SetScript("OnClick", function()
        if menu and menu:IsShown() then CloseMenu() else OpenMenu() end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Host filter")
        GameTooltip:AddLine("Only groups hosted in the locations you tick are listed. "
            .. "A host ending in ? is a guess from a nearby realm ID.", 1, 1, 1, true)
        if NS.hidden > 0 then GameTooltip:AddLine(NS.hidden .. " groups hidden right now", 1, 0.5, 0.3) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnHide", CloseMenu)
    SP:HookScript("OnShow", function() pcall(Fit); NS.UpdateFilterButton() end)
    pcall(Fit)
    NS.UpdateFilterButton()
end

---------------------------------------------------------
--  SECTION: Settings window
---------------------------------------------------------
local window

local function RealmText(row)
    local parts = { ("|cffffd100%d|r"):format(row.id), row.dc }
    if row.name then parts[#parts + 1] = row.name end
    if row.mine then parts[#parts + 1] = "|cff4de666your realm|r" end
    if row.src == "manual" then parts[#parts + 1] = "|cff999999your label|r" end
    if row.src == "shared" then parts[#parts + 1] = "|cff999999from another player|r" end
    if row.ping then
        parts[#parts + 1] = ("ping %d ms (%d samples)"):format(row.ping.sum / row.ping.n, row.ping.n)
    end
    return table.concat(parts, "   ")
end

local function BuildWindow()
    local db = NS.db
    window = UI.Window({ name = "GroupHostFrame", title = "GroupHost", width = 620, height = 560 })
    local body = window.body
    local y = 0
    local function Row(widget, h)
        widget:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
        y = y - (h or 26)
        return widget
    end

    Row(UI.Check(body, "Show the host on each group", function() return db.tags end,
        function(v) db.tags = v; NS.Redraw() end))
    Row(UI.Check(body, "Show the host in group tooltips", function() return db.tooltip end,
        function(v) db.tooltip = v end))
    Row(UI.Check(body, "Guess unknown realms from nearby realm IDs", function() return db.guess end,
        function(v) db.guess = v; NS.ClearCache(); NS.Refilter() end))
    Row(UI.Check(body, "Share known realms with group and guild members", function() return db.share end,
        function(v) db.share = v end))
    Row(UI.Check(body, "Show minimap button", function() return not db.minimap.hide end,
        function(v) UI.SetLauncherShown(db.minimap, v) end), 32)

    local lookLabel = Row(UI.Text(body, "Window look", "GameFontNormalSmall"), 18)
    local look = UI.Dropdown(body, 260, function()
        local items = {}
        for _, o in ipairs(NS.LookOptions()) do items[#items + 1] = { value = o.value, label = o.text } end
        return items
    end, function() return db.theme end, function(v) NS.SetLook(v) end)
    Row(look, 36)

    Row(UI.Text(body, "Known realms", "GameFontNormal"), 20)
    local hint = Row(UI.Text(body, "Hover a group in the finder to see its realm ID. Label one here when you "
        .. "know where it is hosted.", "GameFontHighlightSmall"), 20)
    hint:SetWidth(580)

    local list = UI.List(body, 584, 20, 9, function(row, item) UI.RenderRow(row, RealmText(item)) end,
        function(self, item)
            self.selected = item
            self:Update()
        end)
    Row(list, 9 * 20 + 14)
    function list:Refresh() self:SetData(NS.RealmRows()) end
    UI.Track(list)

    -- label a realm: ID, datacenter, Add
    local newId, newDc = "", ""
    local idLabel = UI.Text(body, "Realm ID", "GameFontNormalSmall")
    idLabel:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y - 4)
    local idBox = UI.Edit(body, 70, false, function() return newId end, function(v) newId = v end)
    idBox.allowEmpty = true
    idBox:SetPoint("LEFT", idLabel, "RIGHT", 10, 0)
    local dcLabel = UI.Text(body, "Datacenter (AU1, US2...)", "GameFontNormalSmall")
    dcLabel:SetPoint("LEFT", idBox, "RIGHT", 14, 0)
    local dcBox = UI.Edit(body, 60, false, function() return newDc end, function(v) newDc = v end)
    dcBox.allowEmpty = true
    dcBox:SetPoint("LEFT", dcLabel, "RIGHT", 10, 0)

    local function AfterChange()
        NS.myLoc = (NS.Lookup(NS.myRealm or 0) or {}).loc or NS.myLoc
        NS.Refilter()
        NS.UpdateFilterButton()
        UI.RefreshAll()
    end
    local add = UI.Button(body, "Add", 70, 22, function()
        idBox:ClearFocus()
        dcBox:ClearFocus()
        local id, dc = tonumber(newId), tostring(newDc):upper():gsub("%s", "")
        if not id or not dc:match("^%a+%d+$") then
            NS.Print("enter a realm ID and a datacenter code such as US2")
            return
        end
        NS.Learn(id, dc, nil, "manual")
        newId, newDc = "", ""
        AfterChange()
    end)
    add:SetPoint("LEFT", dcBox, "RIGHT", 12, 0)
    local remove = UI.Button(body, "Remove label", 110, 22, function()
        local item = list.selected
        if not item then NS.Print("pick a realm in the list first") return end
        if not NS.Forget(item.id) then NS.Print("that realm has no saved label to remove") return end
        AfterChange()
    end)
    remove:SetPoint("LEFT", add, "RIGHT", 8, 0)
end

function NS.ToggleWindow()
    if not NS.db then return end
    if not window then BuildWindow() end
    window:SetShown(not window:IsShown())
end

---------------------------------------------------------
--  SECTION: Launcher and Options page
---------------------------------------------------------
UI.RegisterSettingsPage(ICON, "/gh", function() NS.ToggleWindow() end)

function NS.InitUI()
    UI.Launcher({
        icon = ICON,
        db = NS.db.minimap,
        onLeft = NS.ToggleWindow,
        lines = { "Host tags and the host filter are in the group finder" },
    })
end
