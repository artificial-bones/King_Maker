local addonName, ns = ...

local MARK_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local MAX_SLOTS = 36

---------------------------------------------------------------------------
-- Marks on the default bag buttons
---------------------------------------------------------------------------

local function markButton(button, bag, slot)
    local show = QuestKingDB and QuestKingDB.marks and ns.Status(bag, slot) == "unneeded"
    if show and not button.QuestKingMark then
        local t = button:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetTexture(MARK_TEXTURE)
        t:SetSize(16, 16)
        t:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        button.QuestKingMark = t
    end
    if button.QuestKingMark then button.QuestKingMark:SetShown(show and true or false) end
end

-- Modern bag frames hand out their buttons; the older style names them
-- ContainerFrame1Item1.. with the bag as the frame's ID and the slot as the button's.
local function updateFrame(frame)
    if not frame or not frame:IsShown() then return end
    if frame.EnumerateValidItems then
        for _, button in frame:EnumerateValidItems() do
            markButton(button, button.GetBagID and button:GetBagID() or frame:GetID(), button:GetID())
        end
        return
    end
    local name = frame.GetName and frame:GetName()
    if not name then return end
    local bag = frame:GetID()
    for i = 1, MAX_SLOTS do
        local button = _G[name .. "Item" .. i]
        if not button then break end
        markButton(button, bag, button:GetID())
    end
end

local function eachFrame(fn)
    fn(ContainerFrameCombinedBags)
    for i = 1, NUM_CONTAINER_FRAMES or 13 do fn(_G["ContainerFrame" .. i]) end
end

function ns.UpdateBagButtons()
    eachFrame(updateFrame)
end

local hooked = {}
function ns.HookBags()
    eachFrame(function(frame)
        if not frame or hooked[frame] then return end
        hooked[frame] = true
        frame:HookScript("OnShow", function(self) updateFrame(self) end)
        if frame.UpdateItems then hooksecurefunc(frame, "UpdateItems", updateFrame) end
    end)
    if ContainerFrame_Update and not hooked.global then
        hooked.global = true
        hooksecurefunc("ContainerFrame_Update", updateFrame)
    end
end

---------------------------------------------------------------------------
-- Tooltip line
---------------------------------------------------------------------------

local function addLine(tooltip, itemID)
    if not (QuestKingDB and QuestKingDB.tooltip) then return end
    local why = ns.UnneededReason(itemID)
    if why then
        tooltip:AddLine("Quest King: safe to delete, " .. why .. ".", 1, 0.3, 0.3, true)
    end
end

local function itemIDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

local function hookTooltip()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if data and data.id then addLine(tooltip, data.id) end
        end)
    elseif GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetItem") then
        GameTooltip:HookScript("OnTooltipSetItem", function(self)
            local _, link = self:GetItem()
            addLine(self, itemIDFromLink(link))
        end)
    end
end
hookTooltip()
