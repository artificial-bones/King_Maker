local _, KM = ...
local ns = KM.Module("Gather")

-- What the old Gather King minimap button did, on the King Maker crown instead: quick actions to open the
-- Gathering page and switch profile (one action that opens a small menu of profiles), plus a line in the crown's
-- tooltip. (Its "Farming ledger" action is the Farm Tracker's "Farm Tracker" since King Maker 2.6.)

-- The profile menu, anchored at owner (or the cursor). Radios: the active profile is ticked.
function ns.ProfileMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        KM.Print(ns, "Profiles: " .. table.concat(ns.ProfileNames(), ", ") .. ". /gt profile <name> switches.")
        return
    end
    MenuUtil.CreateContextMenu(owner or UIParent, function(_, root)
        root:CreateTitle("Gathering profile")
        for _, name in ipairs(ns.ProfileNames()) do
            root:CreateRadio(name,
                function() return ns.ActiveProfile() == name end,
                function() ns.UseProfile(name) end)
        end
        root:CreateDivider()
        root:CreateButton("Open the Gathering page", function() ns.OpenSettings() end)
    end)
end

KM.RegisterQuickAction({ id = "gather-page", label = "Gathering", order = 45, func = function() ns.OpenSettings() end })
-- Opened a moment later: the crown's own menu closes after the click has run.
KM.RegisterQuickAction({ id = "gather-profile", label = "Switch gathering profile", order = 47, func = function()
    C_Timer.After(0, function() ns.ProfileMenu(KM.minimapButton) end)
end, shown = function() return ns.db ~= nil end })

KM.RegisterTooltip(function(tt)
    if not ns.db then return end
    local n = 0
    for _, list in pairs(ns.db.nodes) do n = n + #list end
    tt:AddLine(KM.Commas(n) .. " gathering markers. Profile: " .. ns.ActiveProfile() .. ".", 1, 1, 1)
end)
