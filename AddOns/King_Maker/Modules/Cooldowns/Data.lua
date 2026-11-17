local _, KM = ...
local ns = KM.Module("Cooldowns", { title = "Cooldown King", short = "Cooldowns", db = "CooldownKingDB" })

-- Cooldowns (new in 2.6): every crafting cooldown on every character, on one page of the King Maker window
-- (Crafting > Cooldowns, /cdk, /km cooldowns), with a red count on the sidebar when one is ready here.
--
-- Files:
--   Data.lua    the catalogue: which recipes have a cooldown, their groups (the shared transmute), tools
--   Core.lua    saved data, reading the game's timers (and which reading to trust), events, the badge, reminders,
--               /cdk, the CooldownKing API
--   Money.lua   what each cooldown is worth (Crafting Profits' rules), per week, idle cost, pace; the Scanner
--               watch list, the Shopping "Cooldown mats" list and the Inventory callback
--   UI.lua      the page (tiles, table, detail cards, price chart), the toast, the crown's quick action and
--               tooltip line, the Home tile and note, Settings
--
-- Recipe facts (product, reagents, how many made, skill) are not copied here: they come from Market.Recipe(spell),
-- so a ForeverDB data refresh fixes them for us. The catalogue only adds what Market doesn't know: the group, the
-- default length and the tool. Lengths the game reports replace these defaults (db.learned[spell].dur).

local HOUR, DAY = 3600, 86400
ns.HOUR, ns.DAY = HOUR, DAY
ns.MIN_TRACKED = 2 * HOUR    -- a recipe the window reports with less left than this is never "discovered"
ns.MAX_DISCOVERED = 14 * DAY -- a reading longer than this for a discovered recipe is garbage

-- Market's profession ids (Modules\Market\Core.lua), by the name GetProfessionInfo gives.
ns.PROF_IDS = { ["Alchemy"] = 4, ["Blacksmithing"] = 2, ["Cooking"] = 6, ["Enchanting"] = 10, ["Engineering"] = 9,
    ["First Aid"] = 1, ["Leatherworking"] = 3, ["Mining"] = 7, ["Tailoring"] = 8 }
ns.PROF_NAMES = {}
for name, id in pairs(ns.PROF_IDS) do ns.PROF_NAMES[id] = name end

-- One row per group on the page. shared = one cooldown for every member (casting any blocks all).
-- skill = the least skill that can have a member (for the "open your window once" hint); needTool = no row at all
-- without the tool (the Salt Shaker is the thing you use), otherwise a missing tool only warns.
ns.GROUPS = {
    transmute = { label = "Transmute", prof = 4, skill = 225, tool = 9149, shared = true, order = 1, icon = 12360 },
    mooncloth = { label = "Mooncloth", prof = 8, skill = 230, order = 2, where = "at a moonwell", icon = 14342 },
    salt      = { label = "Refined Salt", prof = 3, skill = 250, tool = 15846, needTool = true, order = 3, icon = 15409 },
}

-- [spell] = { group, dur = default length in seconds (replaced by the real one once seen, db.learned) }
ns.CATALOGUE = {
    [17187]   = { group = "transmute", dur = 2 * DAY },   -- Arcanite
    [11479]   = { group = "transmute", dur = DAY },       -- Iron to Gold
    [11480]   = { group = "transmute", dur = DAY },       -- Mithril to Truesilver
    [17559]   = { group = "transmute", dur = DAY },       -- Air to Fire
    [17560]   = { group = "transmute", dur = DAY },       -- Fire to Earth
    [17561]   = { group = "transmute", dur = DAY },       -- Earth to Water
    [17562]   = { group = "transmute", dur = DAY },       -- Water to Air
    [17563]   = { group = "transmute", dur = DAY },       -- Undeath to Water
    [17564]   = { group = "transmute", dur = DAY },       -- Water to Undeath
    [17565]   = { group = "transmute", dur = DAY },       -- Life to Earth
    [17566]   = { group = "transmute", dur = DAY },       -- Earth to Life
    [1317279] = { group = "transmute", dur = 47 * HOUR }, -- Legionite (Forever)
    [18560]   = { group = "mooncloth", dur = 4 * DAY },   -- Mooncloth
    -- not a trade skill: an item you use. Carries its own recipe.
    [19566]   = { group = "salt", dur = 3 * DAY, item = 15846,
                  recipe = { item = 15409, prof = 3, skill = 250, reagents = { 8150, 1 }, made = 1 } },
}
ns.TOOLS = { [9149] = "Philosopher's Stone", [15846] = "Salt Shaker" }
-- Items whose price says what a cooldown's product is worth further down the line (watched by the Scanner too).
ns.DOWNSTREAM = { 15407, 8171 }   -- Cured Rugged Hide, Rugged Hide (the salt's main use)

local function learned(spell) return ns.db and ns.db.learned and ns.db.learned[spell] end

-- The group a spell's cooldown belongs to: a member found not to share its group's cooldown gets its own
-- ("r:<spell>"), as does a recipe discovered at runtime. nil when we don't track it.
function ns.GroupOf(spell)
    local l = learned(spell)
    if l and l.split then return "r:" .. spell end
    local c = ns.CATALOGUE[spell]
    if c then return c.group end
    if l and l.group then return l.group end
end

local function spellName(spell)
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, spell)
        if ok and type(n) == "string" then return n end
    end
end

-- The group's description: a catalogue group, or one made on the fly for "r:<spell>" from its recipe.
local made = {}
function ns.Group(key)
    if ns.GROUPS[key] then return ns.GROUPS[key] end
    local spell = type(key) == "string" and tonumber(key:match("^r:(%d+)$"))
    if not spell then return nil end
    local g = made[key]
    if not g then
        g = { spell = spell, discovered = true, order = 10 }
        made[key] = g
    end
    local r = ns.Recipe and ns.Recipe(spell)
    local l = learned(spell)
    g.prof = (r and r.prof) or (l and l.prof) or (ns.CATALOGUE[spell] and ns.GROUPS[ns.CATALOGUE[spell].group].prof)
    g.icon = r and r.item
    g.split = l and l.split or nil
    local base = ns.CATALOGUE[spell] and ns.GROUPS[ns.CATALOGUE[spell].group]
    g.tool = base and base.tool
    local name = (r and r.item and ns.ItemName and ns.ItemName(r.item)) or spellName(spell) or ("Recipe " .. spell)
    g.label = name
    return g
end

-- Every spell we track: the catalogue and what the client taught us.
function ns.AllSpells()
    local out = {}
    for spell in pairs(ns.CATALOGUE) do out[#out + 1] = spell end
    for spell, l in pairs(ns.db and ns.db.learned or {}) do
        if not ns.CATALOGUE[spell] and l.group then out[#out + 1] = spell end
    end
    table.sort(out)
    return out
end

-- The spells of one group, sorted.
function ns.Members(key)
    local out = {}
    for _, spell in ipairs(ns.AllSpells()) do
        if ns.GroupOf(spell) == key then out[#out + 1] = spell end
    end
    return out
end

-- Every group key there is (catalogue, discovered, split).
function ns.GroupKeys()
    local seen, out = {}, {}
    for _, spell in ipairs(ns.AllSpells()) do
        local g = ns.GroupOf(spell)
        if g and not seen[g] then seen[g] = true; out[#out + 1] = g end
    end
    table.sort(out, function(a, b)
        local ga, gb = ns.Group(a), ns.Group(b)
        local oa, ob = ga and ga.order or 99, gb and gb.order or 99
        if oa ~= ob then return oa < ob end
        return a < b
    end)
    return out
end

function ns.ProfName(id) return ns.PROF_NAMES[id] or "your profession" end
