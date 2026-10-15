local _, ns = ...

-- A mob's page: level, rank, zone and where it spawns; what a kill is worth
-- with the filters at the top; and its loot table: each drop's chance, how
-- many come at once, its price and what it adds per kill. Drops QuestieDB
-- lists that nobody has seen yet are at the bottom. Back returns to the list;
-- the arrows step through it.

local ROWS, ROW_H = 15, 18
local view, back, prevBtn, nextBtn, pos, name, about, star, trackCheck, stats, rows, empty, spawnText
local current, index, offset = nil, nil, 0
local value

local COLS = {
    { key = "item", label = "Drop", w = 230, justify = "LEFT" },
    { key = "chance", label = "Chance", w = 70, justify = "RIGHT" },
    { key = "avg", label = "Per drop", w = 70, justify = "RIGHT" },
    { key = "unit", label = "Price", w = 110, justify = "RIGHT" },
    { key = "perKill", label = "Per kill", w = 110, justify = "RIGHT" },
    { key = "from", label = "", w = 70, justify = "LEFT" },
}

local function pct(x)
    if not x then return "|cff808080-|r" end
    if x >= 0.1 then return string.format("%.0f%%", x * 100) end
    if x >= 0.01 then return string.format("%.1f%%", x * 100) end
    return string.format("%.2f%%", x * 100)
end

local function refreshRows()
    local list = value and value.rows or {}
    offset = math.max(0, math.min(offset, #list - ROWS))
    for i = 1, ROWS do
        local r, row = rows[i], list[i + offset]
        if row then
            r.item = row.item
            r.icon:SetTexture(ns.Item(row.item).icon)
            r.cells.item:SetText(ns.ItemText(row.item))
            r.cells.chance:SetText(row.possible and "|cff808080not seen|r" or pct(row.chance))
            r.cells.avg:SetText(row.avg and (row.avg >= 1.05 and string.format("%.1f", row.avg) or "1") or "")
            r.cells.unit:SetText(row.unit and ns.Money(row.unit) or "|cff808080loading|r")
            r.cells.perKill:SetText(row.perKill and ns.Money(row.perKill) or "")
            r.cells.from:SetText(row.from == "ah" and "|cffa0a0a0AH|r" or row.from == "vendor" and "|cffa0a0a0vendor|r"
                or row.from == "quest" and "|cffa0a0a0quest|r" or "")
            r:SetAlpha((row.possible or not row.included) and 0.45 or 1)
            r:Show()
        else
            r.item = nil
            r:Hide()
        end
    end
    empty:SetText(#list == 0 and "No drops recorded yet. Kill and loot it, or Ask guild." or "")
end

function ns.RefreshMob()
    if not current or not view:IsShown() then return end
    local id = current
    local info = ns.MobInfo(id)
    name:SetText(info.name .. (info.rank and (" |cffffd100(" .. info.rank .. ")|r") or ""))
    local bits = {}
    local lvl = ns.LevelText(info)
    if lvl ~= "" then table.insert(bits, "Level " .. lvl) end
    if info.type then table.insert(bits, info.type) end
    if info.map then table.insert(bits, ns.MapName(info.map)) end
    if info.sub and info.sub ~= "" then table.insert(bits, "<" .. info.sub .. ">") end
    about:SetText(table.concat(bits, "  -  "))
    local starTex = star:GetNormalTexture()
    if starTex then starTex:SetAlpha(ns.db.fav[id] and 1 or 0.2) end
    trackCheck:SetChecked(ns.db.track[id] and true or false)

    local list = ns.CurrentList()
    if index and list[index] and list[index].id == id then
        pos:SetText(index .. " of " .. #list)
        prevBtn:SetEnabled(index > 1)
        nextBtn:SetEnabled(index < #list)
    else
        pos:SetText("")
        prevBtn:SetEnabled(false)
        nextBtn:SetEnabled(false)
    end

    value = ns.Value(id)
    local v = value
    local mine, others = v.mine, v.kills - v.mine
    stats.gold:SetText(v.gold and ns.Money(v.gold) or "|cff808080-|r")
    stats.coin:SetText(v.coin and ns.Money(v.coin) or "|cff808080-|r")
    stats.kills:SetText(v.kills .. (others > 0 and ("  |cffa0a0a0(you " .. mine .. ", guild " .. others .. " from " .. v.mates .. ")|r") or ""))
    stats.note:SetText(v.kills == 0 and "No kills recorded yet." or v.kills < ns.db.filter.minKills and "Few kills so far: rough numbers."
        or v.incomplete and "Some prices are still loading." or "")
    local spots, from = ns.Spots(id)
    spawnText:SetText(#spots > 0 and ((from == "QuestieDB" and (#spots .. " spawn points from QuestieDB.") or ("Seen at " .. #spots .. " spots.")))
        or "No spawn points known yet.")
    refreshRows()
end

function ns.OpenMob(id, i)
    current, index, offset = id, i, 0
    view:Show()
    ns.RefreshMob()
end

function ns.HideMob() if view then view:Hide() end end

local function step(d)
    local list = ns.CurrentList()
    if not index or not list[index + d] then return end
    index = index + d
    current, offset = list[index].id, 0
    ns.RefreshMob()
end

local function button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 20)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

function ns.CreateMobView(parent)
    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)
    view:Hide()

    back = button(view, "< Back", 70, function() ns.ShowList() end)
    back:SetPoint("TOPLEFT", 0, 0)
    prevBtn = button(view, "<", 26, function() step(-1) end)
    prevBtn:SetPoint("LEFT", back, "RIGHT", 6, 0)
    nextBtn = button(view, ">", 26, function() step(1) end)
    nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 2, 0)
    pos = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pos:SetPoint("LEFT", nextBtn, "RIGHT", 6, 0)

    name = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", 0, -30)
    about = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    about:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)

    -- Right side: favorite, track, ask
    star = CreateFrame("Button", nil, view)
    star:SetSize(18, 18)
    star:SetPoint("TOPRIGHT", -250, -2)
    star:SetNormalTexture(ns.STAR)
    star:SetScript("OnClick", function()
        if current then ns.db.fav[current] = (not ns.db.fav[current]) or nil; ns.RefreshMob() end
    end)
    trackCheck = CreateFrame("CheckButton", nil, view, "UICheckButtonTemplate")
    trackCheck:SetSize(22, 22)
    trackCheck:SetPoint("LEFT", star, "RIGHT", 10, 0)
    local trackLabel = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    trackLabel:SetPoint("LEFT", trackCheck, "RIGHT", 0, 1)
    trackLabel:SetText("Track on map")
    trackCheck:SetScript("OnClick", function(self)
        if current then ns.SetTracked(current, self:GetChecked()) end
    end)
    local ask = button(view, "Ask guild", 80, function() if current then ns.AskGuild({ current }) end end)
    ask:SetPoint("TOPRIGHT", 0, 0)

    -- What a kill is worth
    stats = {}
    for i, s in ipairs({ { "gold", "Gold per kill" }, { "coin", "Coin per kill" }, { "kills", "Kills recorded" } }) do
        local x = (i - 1) * 180
        local label = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        label:SetPoint("TOPLEFT", x, -72)
        label:SetText(s[2])
        local v = view:CreateFontString(nil, "OVERLAY", i == 1 and "GameFontNormalLarge" or "GameFontHighlight")
        v:SetPoint("TOPLEFT", x, -86)
        stats[s[1]] = v
    end
    stats.note = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    stats.note:SetPoint("TOPLEFT", 0, -110)
    spawnText = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    spawnText:SetPoint("TOPRIGHT", 0, -110)

    -- Loot table
    local x = 20
    for _, col in ipairs(COLS) do
        local h = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", x, -130)
        h:SetWidth(col.w - 6)
        h:SetJustifyH(col.justify)
        h:SetText(col.label)
        x = x + col.w
    end
    rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, view)
        r:SetSize(x, ROW_H)
        r:SetPoint("TOPLEFT", 0, -146 - (i - 1) * ROW_H)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT", 0, 0)
        r.cells = {}
        local cx = 20
        for _, col in ipairs(COLS) do
            local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", cx, 0)
            fs:SetWidth(col.w - 6)
            fs:SetJustifyH(col.justify)
            if fs.SetWordWrap then fs:SetWordWrap(false) end
            r.cells[col.key] = fs
            cx = cx + col.w
        end
        r:SetScript("OnEnter", function(self)
            if not self.item then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.item) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = r
    end
    empty = view:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOP", 0, -200)
    view:EnableMouseWheel(true)
    view:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 3)
        refreshRows()
    end)
end
