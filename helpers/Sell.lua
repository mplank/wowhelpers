--[[
    wowhelpers – Feature: Taschen leeren (Verkaufen + Zerstören)
    Verkauf am Händler, graue Gegenstände zerstören, Button im Händlerfenster.
]]
local Wowhelpers = LibStub("AceAddon-3.0"):GetAddon("wowhelpers")

local SELL_DELAY = 0.12
local destroyQueue = {}
local destroyFrame = nil       -- Container-Frame für die Zerstören-UI
local destroyBtn, skipBtn, cancelBtn = nil, nil, nil
local currentDestroyBag, currentDestroySlot = nil, nil  -- aktuell auf Cursor (für Zurücklegen)

--- Alle Taschen-Slots, deren Item beim Händler verkaufbar ist (wie Baganator: hasNoValue aus GetContainerItemInfo).
--- Egal welche Qualität – nur „hat keinen Händlerwert“ (Quest, nicht verkaufbar) wird ausgeschlossen.
local function GetSellableSlots()
    if not C_Container or not C_Container.GetContainerNumSlots then return {} end
    local list = {}
    for bag = 0, 5 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local slotInfo = C_Container.GetContainerItemInfo(bag, slot)
                -- Item im Slot und hat Händlerwert (hasNoValue ~= true) → verkaufbar
                if slotInfo and (slotInfo.itemID or slotInfo.hyperlink) and not slotInfo.hasNoValue then
                    list[#list + 1] = { bag = bag, slot = slot }
                end
            end
        end
    end
    return list
end

--- Optional: onDone() wird aufgerufen, wenn der Verkauf durch ist (für "Verkaufen & Löschen"-Button).
function Wowhelpers:SellAllAtVendor(onDone)
    if not MerchantFrame or not MerchantFrame:IsShown() then
        print("[wowhelpers] Bitte zuerst einen Händler ansprechen (Verkaufsfenster offen).")
        if onDone then onDone() end
        return
    end
    local list = GetSellableSlots()
    if #list == 0 then
        print("[wowhelpers] Nichts zu verkaufen.")
        if onDone then onDone() end
        return
    end
    local idx = 0
    local function sellNext()
        idx = idx + 1
        if idx > #list then
            print(("[wowhelpers] %d Gegenstand/Gegenstände verkauft."):format(#list))
            if onDone then onDone() end
            return
        end
        local e = list[idx]
        local useItem = (C_Container and C_Container.UseContainerItem) or UseContainerItem
        useItem(e.bag, e.slot)
        C_Timer.After(SELL_DELAY, sellNext)
    end
    sellNext()
end

--- Qualität: 5 = Legendary, 6 = Artifact (z. B. Legion-Waffen) – können nicht zerstört werden.
local QUALITY_LEGENDARY = 5
local QUALITY_ARTIFACT = 6
local function isDestroyableByQuality(quality)
    if quality == nil then return true end
    return quality ~= QUALITY_LEGENDARY and quality ~= QUALITY_ARTIFACT
end

--- Slots mit Items, die beim Händler nicht verkaufbar sind (hasNoValue) und zerstörbar (kein Legendary/Artifact).
local function GetNonSellableSlots()
    if not C_Container or not C_Container.GetContainerNumSlots then return {} end
    local list = {}
    for bag = 0, 5 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and (info.itemID or info.hyperlink or info.itemLink) and info.hasNoValue then
                    local q = info.quality or info.itemQuality
                    if isDestroyableByQuality(q) then
                        list[#list + 1] = { bag = bag, slot = slot }
                    end
                end
            end
        end
    end
    return list
end

local function GetGreySlots()
    if not C_Container or not C_Container.GetContainerNumSlots then return {} end
    local list = {}
    for bag = 0, 5 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and (info.itemID or info.hyperlink or info.itemLink) then
                    local quality = info.quality or info.itemQuality
                    if quality == 0 and isDestroyableByQuality(quality) then
                        list[#list + 1] = { bag = bag, slot = slot }
                    end
                end
            end
        end
    end
    return list
end

local destroyWaitingForPopupClose = false

local function PickupContainerItemSafe(bag, slot)
    if C_Container and C_Container.PickupContainerItem then
        C_Container.PickupContainerItem(bag, slot)
    else
        PickupContainerItem(bag, slot)
    end
end

local function PickupNextInDestroyQueue()
    if #destroyQueue == 0 then return false end
    local e = destroyQueue[1]
    table.remove(destroyQueue, 1)
    currentDestroyBag, currentDestroySlot = e.bag, e.slot
    PickupContainerItemSafe(e.bag, e.slot)
    return true
end

local function UpdateDestroyUI()
    if destroyBtn then
        destroyBtn:SetText(("Löschen (%d übrig)"):format(#destroyQueue))
    end
end

--- Ganzen Löschvorgang abbrechen: Item zurücklegen, Frame verstecken.
local function CancelDestroyProcess()
    destroyWaitingForPopupClose = false
    if currentDestroyBag ~= nil and currentDestroySlot ~= nil and CursorHasItem() then
        PickupContainerItemSafe(currentDestroyBag, currentDestroySlot)
    end
    currentDestroyBag, currentDestroySlot = nil, nil
    destroyQueue = {}
    if destroyFrame then destroyFrame:Hide() end
    print("[wowhelpers] Zerstören abgebrochen.")
end

local function UpdateDestroyButtonAndAdvance()
    if not destroyFrame or not destroyFrame:IsShown() then return end
    destroyWaitingForPopupClose = false
    if not PickupNextInDestroyQueue() then
        destroyFrame:Hide()
        print("[wowhelpers] Alle nicht verkaufbaren Gegenstände zerstört.")
        return
    end
    UpdateDestroyUI()
end

--- Lösch-Dialoge: Enter bestätigt (kein Klick nötig), nach Schließen automatisch nächstes Item aufnehmen.
local function SetupDeletePopupEnterConfirm()
    for name, dialog in pairs(StaticPopupDialogs or {}) do
        if type(name) == "string" and (name:find("DELETE", 1, true) or name:find("DESTROY", 1, true)) and type(dialog) == "table" then
            dialog.enterClicksFirstButton = 1
        end
    end
    if _G.StaticPopup1 and not destroyFrame then
        -- Hook wird in InitSell nach destroyFrame-Erstellung gesetzt
    end
end

--- Nicht löschen: Item zurücklegen, nächstes holen.
local function SkipCurrentAndAdvance()
    if not destroyFrame or not destroyFrame:IsShown() then return end
    destroyWaitingForPopupClose = false
    if currentDestroyBag ~= nil and currentDestroySlot ~= nil and CursorHasItem() then
        PickupContainerItemSafe(currentDestroyBag, currentDestroySlot)
    end
    currentDestroyBag, currentDestroySlot = nil, nil
    if not PickupNextInDestroyQueue() then
        destroyFrame:Hide()
        print("[wowhelpers] Fertig (Rest behalten).")
        return
    end
    UpdateDestroyUI()
end

function Wowhelpers:DestroyGreyItems()
    local list = GetNonSellableSlots()
    if #list == 0 then
        list = GetGreySlots()
    end
    if #list == 0 then
        print("[wowhelpers] Keine nicht verkaufbaren bzw. grauen Gegenstände zum Zerstören.")
        return
    end
    destroyQueue = list
    if not destroyFrame then
        destroyFrame = CreateFrame("Frame", "WowhelpersDestroyFrame", UIParent)
        destroyFrame:SetSize(340, 44)
        destroyFrame:SetPoint("CENTER", 0, -50)
        destroyFrame:SetFrameStrata("DIALOG")

        local bg = destroyFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(destroyFrame)
        bg:SetColorTexture(0.15, 0.15, 0.15, 0.95)

        local borderW = 2
        local top = destroyFrame:CreateTexture(nil, "BORDER")
        top:SetColorTexture(0.4, 0.4, 0.4, 1)
        top:SetPoint("TOPLEFT", destroyFrame, "TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", destroyFrame, "TOPRIGHT", 0, 0)
        top:SetHeight(borderW)
        local bottom = destroyFrame:CreateTexture(nil, "BORDER")
        bottom:SetColorTexture(0.4, 0.4, 0.4, 1)
        bottom:SetPoint("BOTTOMLEFT", destroyFrame, "BOTTOMLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", destroyFrame, "BOTTOMRIGHT", 0, 0)
        bottom:SetHeight(borderW)
        local left = destroyFrame:CreateTexture(nil, "BORDER")
        left:SetColorTexture(0.4, 0.4, 0.4, 1)
        left:SetPoint("TOPLEFT", destroyFrame, "TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", destroyFrame, "BOTTOMLEFT", 0, 0)
        left:SetWidth(borderW)
        local right = destroyFrame:CreateTexture(nil, "BORDER")
        right:SetColorTexture(0.4, 0.4, 0.4, 1)
        right:SetPoint("TOPRIGHT", destroyFrame, "TOPRIGHT", 0, 0)
        right:SetPoint("BOTTOMRIGHT", destroyFrame, "BOTTOMRIGHT", 0, 0)
        right:SetWidth(borderW)

        destroyBtn = CreateFrame("Button", nil, destroyFrame, "UIPanelButtonTemplate")
        destroyBtn:SetSize(120, 24)
        destroyBtn:SetPoint("LEFT", destroyFrame, "LEFT", 12, 0)
        destroyBtn:SetText("Löschen")
        destroyBtn:SetScript("OnClick", function()
            if CursorHasItem() then
                destroyWaitingForPopupClose = true
                DeleteCursorItem()
                C_Timer.After(0.35, function()
                    if destroyWaitingForPopupClose and destroyFrame and destroyFrame:IsShown() and not CursorHasItem() then
                        UpdateDestroyButtonAndAdvance()
                    end
                end)
            else
                if not PickupNextInDestroyQueue() then
                    destroyFrame:Hide()
                    print("[wowhelpers] Alle nicht verkaufbaren Gegenstände zerstört.")
                    return
                end
                UpdateDestroyUI()
            end
        end)

        skipBtn = CreateFrame("Button", nil, destroyFrame, "UIPanelButtonTemplate")
        skipBtn:SetSize(100, 24)
        skipBtn:SetPoint("LEFT", destroyBtn, "RIGHT", 8, 0)
        skipBtn:SetText("Nicht löschen")
        skipBtn:SetScript("OnClick", function()
            SkipCurrentAndAdvance()
        end)

        cancelBtn = CreateFrame("Button", nil, destroyFrame, "UIPanelButtonTemplate")
        cancelBtn:SetSize(90, 24)
        cancelBtn:SetPoint("LEFT", skipBtn, "RIGHT", 8, 0)
        cancelBtn:SetText("Abbrechen")
        cancelBtn:SetScript("OnClick", function()
            CancelDestroyProcess()
        end)
    end
    if _G.StaticPopup1 and not _G.StaticPopup1.WowhelpersDestroyHideHook then
        _G.StaticPopup1.WowhelpersDestroyHideHook = true
        _G.StaticPopup1:HookScript("OnHide", function()
            if destroyWaitingForPopupClose and destroyFrame and destroyFrame:IsShown() then
                C_Timer.After(0.05, UpdateDestroyButtonAndAdvance)
            end
        end)
    end
    SetupDeletePopupEnterConfirm()
    PickupNextInDestroyQueue()
    UpdateDestroyUI()
    destroyFrame:Show()
end

-- Händler-Button. Wird von wowhelpers.lua OnEnable aufgerufen.
function Wowhelpers.InitSell()
    if not MerchantFrame or _G["WowhelpersMerchantButton"] then return end
    local merchantButton = CreateFrame("Button", "WowhelpersMerchantButton", MerchantFrame, "UIPanelButtonTemplate")
    merchantButton:SetSize(140, 22)
    merchantButton:SetText("Verkaufen & Löschen")
    merchantButton:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 16, 4)
    merchantButton:SetScript("OnClick", function()
        -- Erst verkaufen, danach Graues zerstören (vermeidet Cursor/Konflikt)
        Wowhelpers:SellAllAtVendor(function()
            Wowhelpers:DestroyGreyItems()
        end)
    end)
end
