--[[
    wowhelpers – Feature: Briefkasten-Reiter "Verschieben"
    Reiter "Verschieben", Ziel-Char-Dropdown (gleicher Realm + Faktion).
]]
local Wowhelpers = LibStub("AceAddon-3.0"):GetAddon("wowhelpers")

if not WowhelpersMailDB or not WowhelpersMailDB.chars then
    WowhelpersMailDB = WowhelpersMailDB or {}
    WowhelpersMailDB.chars = WowhelpersMailDB.chars or {}
end
WowhelpersMailDB.lastTarget = WowhelpersMailDB.lastTarget or {}  -- pro Char: letzter gewählter Ziel-Char
WowhelpersMailDB.sendBlacklist = WowhelpersMailDB.sendBlacklist or {}  -- [realm-char] = { [itemID] = true | { keep = number } }

local ATTACHMENTS_MAX_SEND = ATTACHMENTS_MAX_SEND or 12

-- Enum.ItemBind: 1=BoP, 2=BoE, 3=OnUse, 4=Quest, 7=Account, 8=Warband, 9=WarbandUntilEquipped
local BIND_ACCOUNT = 7
local BIND_WARBAND = 8
local BIND_WARBAND_UNTIL_EQUIP = 9

--- Prüft per C_TooltipInfo.GetHyperlink(link), ob im Tooltip „Kriegsmeutengebunden“ / Account-/BNet-Gebunden steht.
-- Returns: true = versendbar (Kriegsmeute/Account), false = seelengebunden, nil = Tooltip nicht auslesbar (dann nicht filtern).
local function tooltipShowsWarbandOrAccountBound(link)
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink and link) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
    if not ok or not data or not data.lines then return nil end
    local function strip(s)
        if not s or s == "" then return "" end
        return s:gsub("|c%x%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", " "):gsub("^%s+", ""):gsub("%s+$", "")
    end
    local warbandStrings = {
        "Kriegsmeutengebunden",  -- DE
        "Kriegsmeute",           -- DE kürzer
    }
    if _G.ITEM_BNETACCOUNTBOUND and _G.ITEM_BNETACCOUNTBOUND ~= "" then warbandStrings[#warbandStrings + 1] = _G.ITEM_BNETACCOUNTBOUND end
    if _G.ITEM_BIND_TO_BNETACCOUNT and _G.ITEM_BIND_TO_BNETACCOUNT ~= "" then warbandStrings[#warbandStrings + 1] = _G.ITEM_BIND_TO_BNETACCOUNT end
    if _G.ITEM_ACCOUNTBOUND and _G.ITEM_ACCOUNTBOUND ~= "" then warbandStrings[#warbandStrings + 1] = _G.ITEM_ACCOUNTBOUND end
    if _G.ITEM_BIND_TO_ACCOUNT and _G.ITEM_BIND_TO_ACCOUNT ~= "" then warbandStrings[#warbandStrings + 1] = _G.ITEM_BIND_TO_ACCOUNT end
    for _, lineData in ipairs(data.lines) do
        for _, part in ipairs({ lineData.leftText, lineData.rightText }) do
            local text = strip(part)
            for _, needle in ipairs(warbandStrings) do
                if needle ~= "" and text and text:find(needle, 1, true) then return true end
            end
        end
    end
    return false
end

--- Liefert die Namen der heute aktiven Holidays (Kalender-API), gecacht pro Tag.
local activeEventNamesCache = {}
local function getActiveEventNames()
    if not (C_Calendar and C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime) then return {} end
    local ok, date = pcall(C_DateAndTime.GetCurrentCalendarTime)
    if not ok or not date or not date.monthDay then return {} end
    local cacheKey = (date.year or 0) * 10000 + (date.month or 0) * 100 + (date.monthDay or 0)
    if activeEventNamesCache.key == cacheKey and activeEventNamesCache.names then return activeEventNamesCache.names end
    activeEventNamesCache.key = cacheKey
    activeEventNamesCache.names = {}
    pcall(function()
        if C_Calendar.OpenCalendar then C_Calendar.OpenCalendar() end
        local numEvents = (C_Calendar.GetNumDayEvents and C_Calendar.GetNumDayEvents(0, date.monthDay)) or 0
        for i = 1, numEvents do
            local event = (C_Calendar.GetDayEvent and C_Calendar.GetDayEvent(0, date.monthDay, i)) or nil
            if event and event.calendarType == "HOLIDAY" and event.title and event.title ~= "" then
                activeEventNamesCache.names[#activeEventNamesCache.names + 1] = event.title
            end
        end
    end)
    return activeEventNamesCache.names
end

--- True, wenn im Tooltip „Benötigt [aktueller Event]“ steht (nur aktive Holidays von heute).
local function tooltipShowsRequiredCurrentEvent(link)
    local activeNames = getActiveEventNames()
    if #activeNames == 0 then return false end
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink and link) then return false end
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
    if not ok or not data or not data.lines then return false end
    local function strip(s)
        if not s or s == "" then return "" end
        return s:gsub("|c%x%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", " "):gsub("^%s+", ""):gsub("%s+$", "")
    end
    local requiredPrefixes = { "Benötigt", "Requires" }
    if _G.REQUIRES and type(_G.REQUIRES) == "string" and _G.REQUIRES ~= "" then requiredPrefixes[#requiredPrefixes + 1] = _G.REQUIRES end
    for _, lineData in ipairs(data.lines) do
        for _, part in ipairs({ lineData.leftText, lineData.rightText }) do
            local text = strip(part)
            if text and text ~= "" then
                for _, prefix in ipairs(requiredPrefixes) do
                    if prefix ~= "" and text:find(prefix, 1, true) == 1 then
                        for _, eventName in ipairs(activeNames) do
                            if eventName ~= "" and text:find(eventName, 1, true) then return true end
                        end
                    end
                end
            end
        end
    end
    return false
end

--- True, wenn im Tooltip „Seelengebunden“ (soulbound) steht. Mit bag/slot wird zuerst GetBagItem versucht (echter Slot-Tooltip).
local function tooltipShowsSoulbound(link, bag, slot)
    if not C_TooltipInfo then return false end
    local function checkData(data)
        if not data or not data.lines then return false end
        local function strip(s)
            if not s or s == "" then return "" end
            return s:gsub("|c%x%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", " "):gsub("^%s+", ""):gsub("%s+$", "")
        end
        local soulboundStrings = { "Seelengebunden" }
        if _G.ITEM_SOULBOUND and type(_G.ITEM_SOULBOUND) == "string" and _G.ITEM_SOULBOUND ~= "" then soulboundStrings[#soulboundStrings + 1] = _G.ITEM_SOULBOUND end
        for _, lineData in ipairs(data.lines) do
            for _, part in ipairs({ lineData.leftText, lineData.rightText, lineData.leftString, lineData.rightString }) do
                local text = strip(part)
                for _, needle in ipairs(soulboundStrings) do
                    if needle ~= "" and text and text:find(needle, 1, true) then return true end
                end
            end
            -- Alle String-Felder der Zeile durchsuchen (falls API andere Keys nutzt)
            if type(lineData) == "table" then
                for _, v in pairs(lineData) do
                    if type(v) == "string" then
                        local text = strip(v)
                        for _, needle in ipairs(soulboundStrings) do
                            if needle ~= "" and text and text:find(needle, 1, true) then return true end
                        end
                    end
                end
            end
        end
        return false
    end
    if type(bag) == "number" and type(slot) == "number" and C_TooltipInfo.GetBagItem then
        local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
        if ok and data and checkData(data) then return true end
    end
    if link and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
        if ok and checkData(data) then return true end
    end
    return false
end

--- True, wenn das Item versendbar ist. bindType 1 (BoP): nur ausblenden wenn Tooltip NICHT „Kriegsmeutengebunden“/Account zeigt.
--- bindType 2 (BoE): ausblenden wenn Tooltip „Seelengebunden“ zeigt (bereits angezogen).
local function isSendableItem(bag, slot, link)
    local ok, sendable = pcall(function()
        -- Nur ausblenden wenn Tooltip „Benötigt [aktueller Event]“ zeigt (z. B. Liebe liegt in der Luft)
        if tooltipShowsRequiredCurrentEvent(link) then return false end
        if not (C_Item and C_Item.GetItemInfo) then return true end
        local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(link)
        -- bindType 2 (BoE) + „Seelengebunden“ im Tooltip: sofort ausblenden (IsBound-API kann bei manchen Items false liefern)
        if bindType == 2 and tooltipShowsSoulbound(link, bag, slot) then return false end
        local createLoc = (ItemLocation and ItemLocation.CreateFromBagAndSlot) or (ItemLocationMixin and ItemLocationMixin.CreateFromBagAndSlot)
        if not createLoc then return true end
        local loc = createLoc(ItemLocation or ItemLocationMixin, bag, slot)
        if not loc then return true end
        if not (C_Item and C_Item.IsBound) then return true end
        if not C_Item.IsBound(loc) then return true end
        if bindType == 3 or bindType == 4 then return false end
        -- bindType 1 (BoP): nur filtern wenn Tooltip eindeutig kein Kriegsmeute/Account zeigt; bei unbekannt (nil) anzeigen
        if bindType == 1 then
            local warband = tooltipShowsWarbandOrAccountBound(link)
            if warband == true then return true end   -- Kriegsmeute/Account → anzeigen
            if warband == false then return false end -- Seelengebunden → ausblenden
            return true                              -- nil = Tooltip nicht lesbar → anzeigen
        end
        return true
    end)
    return not ok or sendable
end

--- Sammelt versendbare Items aus den Taschen (Rucksack + Taschen 1–4 + Reagenzientasche). Seelengebundene werden ausgeblendet, Account- und Kriegsmeutengebunden einbezogen.
local function getBagItems()
    local list = {}
    local getNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local getItemLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
    for bag = 0, 5 do  -- 0 = Rucksack, 1–4 = Taschen, 5 = Reagenzientasche
        local numSlots = getNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local link = getItemLink(bag, slot)
                if link and isSendableItem(bag, slot, link) then
                    local itemID = tonumber(link:match("item:(%d+)"))
                    local count = 1
                    if C_Container and C_Container.GetContainerItemInfo then
                        local info = C_Container.GetContainerItemInfo(bag, slot)
                        if info and info.stackCount then count = info.stackCount end
                    elseif GetContainerItemInfo then
                        local _, itemCount = GetContainerItemInfo(bag, slot)
                        if itemCount and itemCount > 0 then count = itemCount end
                    end
                    if count < 1 then count = 1 end
                    local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(link)
                    list[#list + 1] = { itemID = itemID, name = name, texture = texture, count = count, bag = bag, slot = slot, quality = quality }
                end
            end
        end
    end
    return list
end

local moveFrame = nil
local moveTab = nil
local targetDropdown = nil
local didInit = false
local pendingMailRecipient = nil  -- erst bei MAIL_SEND_SUCCESS zur Liste hinzufügen
local savedMailFrameTitle = nil   -- Fenstertitel beim Wechsel zu "Verschieben" zurücksetzen

--- Aktuellen Charakter in die gespeicherte Liste eintragen (Realm + Faktion).
local function saveCurrentCharacter()
    local name = UnitName("player")
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or ""
    local faction = UnitFactionGroup("player")
    if not name or name == "" or not faction then return end
    local key = realm .. "-" .. name
    WowhelpersMailDB.chars[key] = { name = name, realm = realm, faction = faction }
end

--- Fügt Empfänger zur Liste hinzu (nur intern nach SendMail – keine manuelle Eingabe).
local function addCharacterToList(name)
    name = name and strtrim(name):gsub("^%s+", ""):gsub("%s+$", "")
    if not name or name == "" then return end
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or ""
    local faction = UnitFactionGroup("player")
    local key = realm .. "-" .. name
    WowhelpersMailDB.chars[key] = { name = name, realm = realm, faction = faction }
end

--- Entfernt einen Charakter aus der Ziel-Liste (z. B. /wh mailcharpurge Charactername).
function Wowhelpers:MailCharPurge(charName)
    charName = charName and strtrim(charName):gsub("^%s+", ""):gsub("%s+$", "")
    if not charName or charName == "" then
        print("[wowhelpers] Nutzung: /wh mailcharpurge Charactername")
        return
    end
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or ""
    local key = realm .. "-" .. charName
    if WowhelpersMailDB.chars[key] then
        WowhelpersMailDB.chars[key] = nil
        print(("[wowhelpers] \"%s\" wurde aus der Mail-Zielliste entfernt."):format(charName))
    else
        print(("[wowhelpers] \"%s\" steht nicht in der Zielliste (Realm: %s)."):format(charName, realm))
    end
end

--- Schlüssel für den aktuellen Char (Realm-Name), für lastTarget / sendBlacklist.
local function currentCharKey()
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or ""
    return realm .. "-" .. (UnitName("player") or "")
end

--- Blacklist-Tabelle für den aktuellen Char (lesend/schreibend).
local function currentBlacklist()
    local key = currentCharKey()
    if not WowhelpersMailDB.sendBlacklist then WowhelpersMailDB.sendBlacklist = {} end
    if not WowhelpersMailDB.sendBlacklist[key] then WowhelpersMailDB.sendBlacklist[key] = {} end
    return WowhelpersMailDB.sendBlacklist[key]
end

--- Prüft, ob ein Item stapelbar ist (max. Stapelgröße > 1, z. B. 20 oder 200).
--- currentCount: optional; wenn > 1, gilt als stapelbar (Fallback falls API nichts liefert).
local function isStackableItem(itemID, currentCount)
    if not itemID then return false end
    if currentCount and currentCount > 1 then return true end
    local maxStack
    if C_Item and C_Item.GetItemInfo then
        local info = C_Item.GetItemInfo(itemID)
        if info and type(info) == "table" then
            maxStack = info.maxStack or info.stackCount
        end
    end
    if not maxStack then
        maxStack = select(8, GetItemInfo(itemID))
    end
    return maxStack and maxStack > 1
end

--- ItemID als Blacklist-Schlüssel (SavedVariables speichern Keys oft als String – einheitlich nutzen).
local function blKey(itemID)
    if itemID == nil then return nil end
    return tostring(itemID)
end

--- Prüft, ob ein Item (itemID) auf der Blacklist des aktuellen Chars steht.
local function isOnBlacklist(itemID)
    if not itemID then return false end
    local bl = currentBlacklist()
    return bl[blKey(itemID)] ~= nil or bl[itemID] ~= nil
end

--- Liefert die „Anzahl behalten“ für ein Item auf der Blacklist (nil wenn nicht auf Blacklist oder kein keep gesetzt).
local function getBlacklistKeep(itemID)
    if not itemID then return nil end
    local bl = currentBlacklist()
    local v = bl[blKey(itemID)] or bl[itemID]
    if type(v) == "table" and v.keep then return v.keep end
    return nil
end

--- Liefert eine flache Liste aller Taschen-Slots, die versendet werden sollen (Blacklist/keep berücksichtigt).
--- Rückgabe: { { bag, slot, count }, ... } in Bag-Reihenfolge, max. 12 Anhänge pro Mail.
local function getSendableSlotsForSending()
    local items = getBagItems()
    local totalByItem = {}
    for _, data in ipairs(items) do
        if data and data.itemID then
            totalByItem[data.itemID] = (totalByItem[data.itemID] or 0) + (data.count or 1)
        end
    end
    local sentCount = {}
    local list = {}
    local checkBlacklist = isOnBlacklist
    if type(checkBlacklist) ~= "function" then checkBlacklist = function() return false end end
    for _, data in ipairs(items) do
        if data and data.itemID and data.bag and data.slot then
            local itemID = data.itemID
            local count = data.count or 1
            local skip = false
            if checkBlacklist(itemID) then
                local keep = (type(getBlacklistKeep) == "function" and getBlacklistKeep(itemID)) or nil
                if not (keep and keep >= 0) then
                    skip = true
                else
                    local total = totalByItem[itemID] or count
                    local allowed = math.max(0, total - keep)
                    local soFar = sentCount[itemID] or 0
                    if soFar >= allowed or soFar + count > allowed then
                        skip = true
                    else
                        sentCount[itemID] = soFar + count
                    end
                end
            end
            if not skip then
                list[#list + 1] = { bag = data.bag, slot = data.slot, count = count }
            end
        end
    end
    return list
end

--- Fügt itemID zur Blacklist des aktuellen Chars hinzu. optKeep: optional Anzahl zu behalten (0 = alles blockieren).
local function addToBlacklist(itemID, optKeep)
    if not itemID then return end
    currentBlacklist()[blKey(itemID)] = (optKeep and optKeep > 0) and { keep = optKeep } or true
end

--- Entfernt itemID von der Blacklist des aktuellen Chars.
local function removeFromBlacklist(itemID)
    if not itemID then return end
    local bl = currentBlacklist()
    bl[blKey(itemID)] = nil
    bl[itemID] = nil
end

--- Liefert Liste der Chars mit gleichem Realm und gleicher Faktion (ohne aktuellen Char).
local function getCharsSameRealmFaction()
    local currentRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or ""
    local currentFaction = UnitFactionGroup("player")
    local currentName = UnitName("player")
    local list = {}
    for _, data in pairs(WowhelpersMailDB.chars) do
        if data.realm == currentRealm and data.faction == currentFaction and data.name ~= currentName then
            list[#list + 1] = data.name
        end
    end
    table.sort(list)
    return list
end

local function showMoveFrame()
    if not moveFrame then return end
    if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(MailFrame) end
    if InboxFrame then InboxFrame:Hide() end
    if OpenMailFrame then OpenMailFrame:Hide() end
    if SendMailFrame then SendMailFrame:Hide() end
    if SetSendMailShowing then SetSendMailShowing(false) end
    if MailFrameInset then MailFrameInset:Hide() end
    local titleObj = MailFrame and (MailFrame.Title or _G.MailFrameTitleText)
    if titleObj and titleObj.SetText then
        savedMailFrameTitle = titleObj:GetText()
        titleObj:SetText("Post verschieben")
    end
    moveFrame:Show()
end

local function hideMoveFrame()
    if not moveFrame then return end
    moveFrame:Hide()
    local titleObj = MailFrame and (MailFrame.Title or _G.MailFrameTitleText)
    if titleObj and titleObj.SetText and savedMailFrameTitle then
        titleObj:SetText(savedMailFrameTitle)
        savedMailFrameTitle = nil
    end
    if MailFrameInset then MailFrameInset:Show() end
end

local function onMoveTabClick(tabButton)
    PanelTemplates_SetTab(MailFrame, tabButton:GetID())
    showMoveFrame()
end

local function onMailTabClick()
    if PanelTemplates_GetSelectedTab(MailFrame) <= 2 then
        hideMoveFrame()
    end
end

local function createMoveTabAndFrame()
    if didInit or not MailFrame then return end
    -- Tab 3 = "Verschieben" (nach Posteingang=1, Post versenden=2)
    local n = 3
    local prevTab = _G["MailFrameTab2"]
    if not prevTab then return end
    didInit = true

    -- Reiter "Verschieben" (neben Post versenden)
    moveTab = CreateFrame("Button", "MailFrameTab" .. n, MailFrame, "FriendsFrameTabTemplate")
    moveTab:SetID(n)
    moveTab:SetText("Verschieben")
    moveTab:SetPoint("LEFT", prevTab, "RIGHT", -8, 0)
    moveTab:SetScript("OnClick", onMoveTabClick)
    PanelTemplates_SetNumTabs(MailFrame, n)
    PanelTemplates_EnableTab(MailFrame, n)

    -- Frame mit Ziel-Dropdown
    moveFrame = CreateFrame("Frame", "WowhelpersMailMoveFrame", MailFrame)
    moveFrame:SetAllPoints(MailFrame)
    moveFrame:EnableMouse(true)
    moveFrame:Hide()
    local updateVerschiebenButtonState

    -- Ziel-Zeile
    local label = moveFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", moveFrame, "TOPLEFT", 60, -44)
    label:SetText("Ziel:")

    -- Dropdown: Chars gleicher Realm + Faktion
    targetDropdown = CreateFrame("Frame", "WowhelpersMailTargetDropdown", moveFrame, "UIDropDownMenuTemplate")
    targetDropdown:SetPoint("LEFT", label, "RIGHT", 8, 0)
    UIDropDownMenu_SetWidth(targetDropdown, 180)
    UIDropDownMenu_SetText(targetDropdown, "Charakter wählen...")

    UIDropDownMenu_Initialize(targetDropdown, function(self, level)
        local chars = getCharsSameRealmFaction()
        if #chars == 0 then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "(keine anderen Chars)"
            info.notCheckable = true
            info.disabled = true
            UIDropDownMenu_AddButton(info)
        else
            for _, charName in ipairs(chars) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = charName
                info.value = charName
                info.func = function()
                    UIDropDownMenu_SetSelectedValue(targetDropdown, charName)
                    UIDropDownMenu_SetText(targetDropdown, charName)
                    local key = ((GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "") .. "-" .. UnitName("player")
                    WowhelpersMailDB.lastTarget[key] = charName
                    if updateVerschiebenButtonState then updateVerschiebenButtonState() end
                end
                UIDropDownMenu_AddButton(info)
            end
        end
    end)

    -- Grid: nur Item-Icons + Stückzahl, Tooltip beim Hover, Rechtsklick → Blacklist
    -- Erweiterung (später): Alt+Klick auf Item = als „unversendbar“ markieren (eigenes Speicher-Format, bei getBagItems/canSend ausblenden)
    local listHeader = moveFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listHeader:SetPoint("TOPLEFT", moveFrame, "TOPLEFT", 60, -72)
    listHeader:SetText("Verschiebbare Items aus deinen Taschen")
    local emptyMessageLabel = moveFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyMessageLabel:SetPoint("TOP", listHeader, "BOTTOM", 0, -24)
    emptyMessageLabel:SetWidth(280)
    emptyMessageLabel:SetWordWrap(true)
    emptyMessageLabel:SetJustifyH("CENTER")
    emptyMessageLabel:Hide()
    moveFrame.emptyMessageLabel = emptyMessageLabel

    local gridCols = 5
    local iconSize = 36
    local cellGap = 10
    local cellSize = iconSize + cellGap
    local scrollBarWidth = 24
    -- ScrollFrame: Platz für Scrollbalken innen (rechts), damit er nicht aus dem Fenster ragt
    local listScroll = CreateFrame("ScrollFrame", "WowhelpersMailBagListScroll", moveFrame, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", 0, -4)
    listScroll:SetPoint("BOTTOMRIGHT", moveFrame, "BOTTOMRIGHT", -(scrollBarWidth + 16), 80)
    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(gridCols * cellSize + scrollBarWidth, 1)
    listScroll:SetScrollChild(listContent)

    local gridCells = {}
    local maxCells = 80
    for i = 1, maxCells do
        local col = (i - 1) % gridCols
        local row = math.floor((i - 1) / gridCols)
        local cell = CreateFrame("Button", nil, listContent)
        cell:SetSize(cellSize, cellSize)
        cell:SetPoint("TOPLEFT", listContent, "TOPLEFT", col * cellSize, -row * cellSize)
        cell:RegisterForClicks("RightButtonUp")
        cell:EnableMouse(true)
        cell:SetScript("OnEnter", function(self)
            if self.bag and self.slot and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetBagItem(self.bag, self.slot)
                GameTooltip:Show()
            end
        end)
        cell:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        cell:SetScript("OnMouseDown", function(self, button)
            if button ~= "RightButton" then return end
            if GameTooltip then GameTooltip:Hide() end
            local itemID = self.itemID
            if not itemID then return end
            -- Bereits auf Blacklist: Rechtsklick = von Blacklist entfernen
            if isOnBlacklist(itemID) then
                removeFromBlacklist(itemID)
                refreshSendItemList()
                return
            end
            -- Stapel oder mehrere gleiche Items: Fenster „Anzahl behalten“. Sonst: direkt auf Blacklist.
            local totalSame = (self.totalSameItem and self.totalSameItem > 1) and self.totalSameItem or nil
            if isStackableItem(itemID, self.count) or totalSame then
                Wowhelpers.MailBlacklistPendingItemID = itemID
                local d = StaticPopup_Show("WOWHELPERS_MAIL_BLACKLIST_KEEP")
                if d then d.data = itemID; if d.editBox then d.editBox:SetNumber(0); d.editBox:SetMaxLetters(6) end end
            else
                addToBlacklist(itemID)
                refreshSendItemList()
            end
        end)
        cell:SetScript("OnClick", function() end)
        -- Taschen-Slot-Hintergrund (dunkler Rahmen + Symbol bei leer, wie Blizzard-Taschen)
        local slotBg = cell:CreateTexture(nil, "BACKGROUND")
        slotBg:SetSize(iconSize + 4, iconSize + 4)
        slotBg:SetPoint("CENTER", cell, "CENTER", 0, 0)
        slotBg:SetTexture("Interface\\Buttons\\UI-EmptySlot")
        slotBg:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- Qualitäts-Rand um das Item-Icon (farbig je nach Seltenheit)
        local qualityGlow = cell:CreateTexture(nil, "BORDER")
        qualityGlow:SetSize(iconSize + 3, iconSize + 3)
        qualityGlow:SetPoint("CENTER", cell, "CENTER", 0, 0)
        qualityGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
        qualityGlow:SetTexCoord(0, 1, 0, 1)
        qualityGlow:SetVertexColor(0.5, 0.5, 0.5, 0.8)
        cell.qualityGlow = qualityGlow
        local icon = cell:CreateTexture(nil, "ARTWORK")
        icon:SetSize(iconSize, iconSize)
        icon:SetPoint("CENTER", cell, "CENTER", 0, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        cell.icon = icon
        local countLabel = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        countLabel:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -3, 3)
        countLabel:SetJustifyH("RIGHT")
        countLabel:SetTextColor(1, 1, 1, 1)
        cell.countLabel = countLabel
        cell:Hide()
        gridCells[i] = cell
    end

    function refreshSendItemList()
        if not moveFrame or not moveFrame:IsShown() then return end
        Wowhelpers.RefreshMailSendItemList = refreshSendItemList
        local items = getBagItems()
        -- Gesamtanzahl pro ItemID (für „mehrere gleiche“ und für keep-Rest)
        local totalByItem = {}
        for _, data in ipairs(items) do
            if data and data.itemID then
                totalByItem[data.itemID] = (totalByItem[data.itemID] or 0) + (data.count or 1)
            end
        end
        local displayItems = {}
        local seenBlacklistWithKeep = {}
        for _, data in ipairs(items) do
            if data and data.itemID then
                if not isOnBlacklist(data.itemID) then
                    displayItems[#displayItems + 1] = data
                else
                    local keep = getBlacklistKeep(data.itemID)
                    if not (keep and keep >= 0) then
                        -- alles blockiert, nichts anzeigen
                    else
                        local totalCount = totalByItem[data.itemID] or (data.count or 1)
                        local remaining = math.max(0, totalCount - keep)
                        if remaining > 0 then
                            if not seenBlacklistWithKeep[data.itemID] then
                                seenBlacklistWithKeep[data.itemID] = true
                                local merged = {}
                                for k, v in pairs(data) do merged[k] = v end
                                merged.count = remaining
                                displayItems[#displayItems + 1] = merged
                            end
                        end
                    end
                end
            end
        end
        for i = 1, maxCells do
            local cell = gridCells[i]
            local data = displayItems[i]
            if data and data.itemID then
                local rawCount = data.count or 1
                local totalSame = totalByItem[data.itemID] or rawCount
                cell.itemID = data.itemID
                cell.name = data.name
                cell.texture = data.texture
                cell.count = rawCount
                cell.totalSameItem = totalSame
                cell.bag = data.bag
                cell.slot = data.slot
                cell.icon:SetTexture(data.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
                cell.icon:SetVertexColor(1, 1, 1)
                cell.icon:Show()
                local q = data.quality
                if q and q >= 0 and GetItemQualityColor then
                    local r, g, b = GetItemQualityColor(q)
                    cell.qualityGlow:SetVertexColor(r, g, b, 0.9)
                    cell.qualityGlow:Show()
                else
                    cell.qualityGlow:SetVertexColor(0.5, 0.5, 0.5, 0.8)
                    cell.qualityGlow:Show()
                end
                cell.countLabel:SetText((rawCount > 1) and tostring(rawCount) or (rawCount == 1 and "1" or ""))
                cell.countLabel:Show()
                cell:Show()
            else
                cell.itemID = nil
                cell.bag = nil
                cell.slot = nil
                cell:Hide()
            end
        end
        local rows = math.ceil(#displayItems / gridCols)
        local contentH = math.max(1, rows * cellSize)
        listContent:SetHeight(contentH)
        -- Scrollbalken nur anzeigen, wenn Inhalt höher als sichtbarer Bereich
        local scrollBar = listScroll.ScrollBar or _G[listScroll:GetName() and (listScroll:GetName() .. "ScrollBar")]
        if scrollBar then scrollBar:SetShown(contentH > listScroll:GetHeight()) end
        moveFrame.sendableCount = #displayItems
        if moveFrame.emptyMessageLabel then
            if #displayItems == 0 then
                if moveFrame.justFinishedSending then
                    moveFrame.emptyMessageLabel:SetText("Alles verschickt – mehr Platz in deinen Taschen!")
                else
                    moveFrame.emptyMessageLabel:SetText("Keine Pakete zum Verschicken.\nDeine Taschen sind leer – oder die Blacklist hat alles einkassiert.")
                end
                moveFrame.emptyMessageLabel:Show()
            else
                moveFrame.emptyMessageLabel:Hide()
            end
            moveFrame.justFinishedSending = nil
        end
        if updateVerschiebenButtonState then updateVerschiebenButtonState() end
    end

    -- Nach Versand-Ende: zurück zum Verschieben-Tab, ggf. „mehr Platz“-Hinweis (Progress-Frame direkt, sendState kann in Timer/Event nil sein)
    local function finishSendingAndReturnToTab(showEmptyMessage)
        local progFrame = WowhelpersMailSendProgressFrame
        local failed = progFrame and progFrame.attachFailedCount and progFrame.attachFailedCount > 0 and progFrame.attachFailedCount or 0
        if progFrame then
            progFrame.attachFailedCount = nil
            progFrame:Hide()
        end
        if failed > 0 then
            local msg = failed == 1 and "1 Item konnte nicht angehängt werden (z. B. nicht versendbar)." or ("%d Items konnten nicht angehängt werden (z. B. nicht versendbar)."):format(failed)
            print("|cff00aaff[wowhelpers]|r " .. msg)
        end
        PanelTemplates_SetTab(MailFrame, 3)
        showMoveFrame()
        if showEmptyMessage and moveFrame then moveFrame.justFinishedSending = true end
        if refreshSendItemList then refreshSendItemList() end
        if updateVerschiebenButtonState then updateVerschiebenButtonState() end
    end

    -- Button: Blacklist (N) verwalten – N = Anzahl eindeutiger Items
    local blacklistBtn = CreateFrame("Button", nil, moveFrame, "UIPanelButtonTemplate")
    blacklistBtn:SetSize(120, 22)
    blacklistBtn:SetPoint("BOTTOMLEFT", moveFrame, "BOTTOMLEFT", 60, 24)
    local function updateBlacklistButtonText()
        local n = 0
        for _ in pairs(currentBlacklist()) do n = n + 1 end
        blacklistBtn:SetText("Blacklist (" .. n .. ")")
        blacklistBtn:SetEnabled(n > 0)
    end
    updateBlacklistButtonText()
    blacklistBtn:SetScript("OnClick", function()
        if WowhelpersMailBlacklistFrame then
            WowhelpersMailBlacklistFrame:SetShown(not WowhelpersMailBlacklistFrame:IsShown())
            if WowhelpersMailBlacklistFrame:IsShown() then refreshBlacklistFrame() end
        end
    end)

    -- Progress-Frame: Versand-Anzeige (Paket X/Y, Verschickt an Charname, Abbrechen)
    local sendProgressFrame = CreateFrame("Frame", "WowhelpersMailSendProgressFrame", UIParent, "BackdropTemplate")
    sendProgressFrame:SetSize(320, 160)
    sendProgressFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    -- Hintergrund-Texture (immer sichtbar, auch wenn Backdrop nicht greift)
    local progBgTex = sendProgressFrame:CreateTexture(nil, "BACKGROUND")
    progBgTex:SetAllPoints(sendProgressFrame)
    progBgTex:SetColorTexture(0.08, 0.08, 0.08, 1)
    if sendProgressFrame.SetBackdrop then
        sendProgressFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\DialogFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        sendProgressFrame:SetBackdropColor(0, 0, 0, 1)
    end
    sendProgressFrame:SetFrameStrata("DIALOG")
    sendProgressFrame:Hide()
    local progTitle = sendProgressFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    progTitle:SetPoint("TOP", sendProgressFrame, "TOP", 0, -16)
    progTitle:SetText("Verschieben")
    local progBarBg = sendProgressFrame:CreateTexture(nil, "BACKGROUND")
    progBarBg:SetSize(280, 22)
    progBarBg:SetPoint("TOP", sendProgressFrame, "TOP", 0, -44)
    progBarBg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
    local progBarFill = sendProgressFrame:CreateTexture(nil, "ARTWORK")
    progBarFill:SetSize(0, 20)
    progBarFill:SetPoint("TOPLEFT", progBarBg, "TOPLEFT", 2, -1)
    progBarFill:SetColorTexture(0.2, 0.6, 0.2, 1)
    local progLabelPackage = sendProgressFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    progLabelPackage:SetPoint("TOP", progBarBg, "BOTTOM", 0, -6)
    progLabelPackage:SetText("Paket 0/0")
    local progLabelRecipient = sendProgressFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    progLabelRecipient:SetPoint("TOP", progLabelPackage, "BOTTOM", 0, -2)
    progLabelRecipient:SetText("Verschickt an ...")
    local progCancelBtn = CreateFrame("Button", nil, sendProgressFrame, "UIPanelButtonTemplate")
    progCancelBtn:SetSize(100, 22)
    progCancelBtn:SetPoint("BOTTOM", sendProgressFrame, "BOTTOM", 0, 14)
    progCancelBtn:SetText("Abbrechen")

    local sendState = {
        cancel = false,
        currentPackage = 0,
        totalPackages = 0,
        recipient = nil,
        waitingForSuccess = false,
        frame = sendProgressFrame,
        barBg = progBarBg,
        barFill = progBarFill,
        labelPackage = progLabelPackage,
        labelRecipient = progLabelRecipient,
    }
    sendProgressFrame:RegisterEvent("MAIL_SEND_SUCCESS")
    sendProgressFrame:SetScript("OnEvent", function(self, event)
        if event == "MAIL_SEND_SUCCESS" and sendState.waitingForSuccess then
            sendState.waitingForSuccess = false
            local nextFn = self.sendNextPackage
            if type(nextFn) == "function" then
                -- Verzögerung damit Taschen nach Versand aktualisiert sind (BAG_UPDATE), sonst nur 1 Mail
                local cb = function() nextFn() end
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.6, cb)
                else
                    nextFn()
                end
            end
        end
    end)
    local function updateSendProgressUI()
        local s = sendState
        local cur, tot = s.currentPackage, s.totalPackages
        s.labelPackage:SetText(("Paket %d/%d"):format(cur, tot))
        s.labelRecipient:SetText("Verschickt an " .. (s.recipient or ""))
        local w = (s.barBg:GetWidth() or 280) - 4
        if tot and tot > 0 then
            s.barFill:SetWidth(math.max(0, (cur / tot) * w))
        else
            s.barFill:SetWidth(0)
        end
    end
    progCancelBtn:SetScript("OnClick", function()
        sendState.cancel = true
    end)

    local function sendNextPackage()
        if sendState.cancel then
            finishSendingAndReturnToTab(false)
            return
        end
        local slots = getSendableSlotsForSending()
        local total = #slots
        if total == 0 then
            -- Einmal Retry nach kurzer Verzögerung (Taschen-Update kann verzögert sein)
            if sendState.currentPackage >= 1 and C_Timer and C_Timer.After then
                sendState.retryCount = (sendState.retryCount or 0) + 1
                if sendState.retryCount <= 2 then
                    C_Timer.After(0.4, function()
                        if sendProgressFrame.sendNextPackage then sendProgressFrame.sendNextPackage() end
                    end)
                    return
                end
            end
            sendState.retryCount = nil
            finishSendingAndReturnToTab(true)
            return
        end
        sendState.retryCount = nil
        -- totalPackages nur beim Start setzen (startSending), hier nicht überschreiben – sonst bricht nach 1 Mail ab
        sendState.currentPackage = sendState.currentPackage + 1
        if sendState.totalPackages and sendState.currentPackage > sendState.totalPackages then
            finishSendingAndReturnToTab(true)
            return
        end
        updateSendProgressUI()
        local package = {}
        for i = 1, math.min(ATTACHMENTS_MAX_SEND, total) do
            package[i] = slots[i]
        end
        if not MailFrame or not MailFrame:IsShown() or not SendMailFrame then
            finishSendingAndReturnToTab(false)
            return
        end
        -- Tab „Post versenden“ aktivieren, Empfänger setzen; kein ClearSendMail (kann Anhänge-Zustand kaputtmachen)
        local doSend = function()
            if sendState.cancel then sendNextPackage() return end
            if MailFrameTab2 then MailFrameTab2:Click() end
            if SetSendMailShowing then SetSendMailShowing(true) end
            if SendMailFrame then SendMailFrame:Show() end
            if SendMailNameEditBox then SendMailNameEditBox:SetText(sendState.recipient or "") end
            -- Anhänge nacheinander; prüfen ob Item tatsächlich im Slot landete (HasSendMailItem)
            local useItem = (C_Container and C_Container.UseContainerItem) or UseContainerItem
            local idx = 0
            local attachFailedCount = 0
            local function countFilledSlots()
                local n = 0
                for i = 1, ATTACHMENTS_MAX_SEND do
                    if HasSendMailItem and HasSendMailItem(i) then n = n + 1 end
                end
                return n
            end
            local function attachOne()
                idx = idx + 1
                if sendState.cancel then sendNextPackage() return end
                if idx <= #package then
                    if idx > 1 then
                        local filled = countFilledSlots()
                        if filled < idx - 1 then
                            attachFailedCount = attachFailedCount + (idx - 1 - filled)
                        end
                    end
                    if useItem then useItem(package[idx].bag, package[idx].slot) end
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0.12, attachOne)
                    else
                        attachOne()
                    end
                    return
                end
                if attachFailedCount > 0 and sendState and sendState.frame then
                    sendState.frame.attachFailedCount = (sendState.frame.attachFailedCount or 0) + attachFailedCount
                end
                if SendMail and sendState.recipient and sendState.recipient ~= "" then
                    sendState.waitingForSuccess = true
                    SendMail(sendState.recipient, "Verschieben", "")
                else
                    local cb = function() sendNextPackage() end
                    if C_Timer and C_Timer.After and type(cb) == "function" then
                        C_Timer.After(0.2, cb)
                    else
                        sendNextPackage()
                    end
                end
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(0.5, attachOne)
            else
                attachOne()
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, doSend)
        else
            doSend()
        end
    end
    sendProgressFrame.sendNextPackage = sendNextPackage

    local function startSending(target)
        local slots = getSendableSlotsForSending()
        if #slots == 0 then return end
        sendState.cancel = false
        sendState.currentPackage = 0
        sendState.retryCount = nil
        sendState.totalPackages = math.ceil(#slots / ATTACHMENTS_MAX_SEND)
        sendState.recipient = target
        sendProgressFrame.attachFailedCount = nil
        sendProgressFrame:Show()
        updateSendProgressUI()
        sendNextPackage()
    end

    -- Button: Verschieben – startet Versand mit Progress-Fenster
    local verschiebenBtn = CreateFrame("Button", nil, moveFrame, "UIPanelButtonTemplate")
    verschiebenBtn:SetSize(100, 22)
    verschiebenBtn:SetPoint("LEFT", blacklistBtn, "RIGHT", 8, 0)
    verschiebenBtn:SetText("Verschieben")
    verschiebenBtn:SetScript("OnClick", function()
        local target = UIDropDownMenu_GetSelectedValue(targetDropdown)
        if not target or target == "" then return end
        if not MailFrame or not MailFrame:IsShown() then return end
        startSending(target)
    end)
    updateVerschiebenButtonState = function()
        local target = UIDropDownMenu_GetSelectedValue(targetDropdown)
        local n = moveFrame.sendableCount or 0
        verschiebenBtn:SetEnabled(not not target and n > 0)
    end
    updateVerschiebenButtonState()

    -- Blacklist-Fenster (Liste aller geblockten Items, Von Blacklist entfernen)
    local blFrame = CreateFrame("Frame", "WowhelpersMailBlacklistFrame", UIParent, "BasicFrameTemplate")
    blFrame:SetSize(320, 280)
    blFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    -- Titel in der Titelleiste (oberhalb des Inhalts)
    if blFrame.SetTitle then
        blFrame:SetTitle("Mail-Blacklist")
    else
        local blTitle = blFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        blTitle:SetPoint("TOP", blFrame, "TOP", 0, -8)
        blTitle:SetText("Mail-Blacklist")
    end
    blFrame:SetMovable(true)
    blFrame:EnableMouse(true)
    blFrame:RegisterForDrag("LeftButton")
    blFrame:SetScript("OnDragStart", blFrame.StartMoving)
    blFrame:SetScript("OnDragStop", blFrame.StopMovingOrSizing)
    blFrame:Hide()
    -- Grid 1:1 wie Verschieben: 5 Spalten, gleicher Abstand, Icon-Rahmen (UI-EmptySlot), kein Gesamt-Rahmen
    local blGridCols = 5
    local blIconSize = 36
    local blCellGap = 10
    local blCellSize = blIconSize + blCellGap
    local blScrollBarWidth = 24
    -- ScrollFrame mit Inset rechts, damit der Scrollbalken im Inhaltsbereich liegt (nicht am Fensterrand)
    local blScrollRightInset = 10 + blScrollBarWidth  -- Rand + Platz für Scrollbalken
    local blScroll = CreateFrame("ScrollFrame", "WowhelpersMailBlacklistScroll", blFrame, "UIPanelScrollFrameTemplate")
    blScroll:SetPoint("TOPLEFT", blFrame, "TOPLEFT", 10, -50)
    blScroll:SetPoint("BOTTOMRIGHT", blFrame, "BOTTOMRIGHT", -blScrollRightInset, 10)
    local blContent = CreateFrame("Frame", nil, blScroll)
    blContent:SetSize(blGridCols * blCellSize + blScrollBarWidth, 1)
    blScroll:SetScrollChild(blContent)
    blFrame.content = blContent
    blFrame.scroll = blScroll
    local blCells = {}
    local blMaxCells = 60
    for i = 1, blMaxCells do
        local col = (i - 1) % blGridCols
        local row = math.floor((i - 1) / blGridCols)
        local cell = CreateFrame("Button", nil, blContent)
        cell:SetSize(blCellSize, blCellSize)
        cell:SetPoint("TOPLEFT", blContent, "TOPLEFT", col * blCellSize, -row * blCellSize)
        cell:RegisterForClicks("RightButtonUp")
        cell:EnableMouse(true)
        cell:SetScript("OnEnter", function(self)
            if self.itemID and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if GameTooltip.SetItemByID then
                    GameTooltip:SetItemByID(self.itemID)
                else
                    GameTooltip:SetHyperlink("item:" .. self.itemID)
                end
                GameTooltip:Show()
            end
        end)
        cell:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        cell:SetScript("OnClick", function(self, button)
            if button == "RightButton" and self.itemID then
                removeFromBlacklist(self.itemID)
                refreshBlacklistFrame()
                refreshSendItemList()
            end
        end)
        local slotBg = cell:CreateTexture(nil, "BACKGROUND")
        slotBg:SetSize(blIconSize + 4, blIconSize + 4)
        slotBg:SetPoint("CENTER", cell, "CENTER", 0, 0)
        slotBg:SetTexture("Interface\\Buttons\\UI-EmptySlot")
        slotBg:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local qualityGlow = cell:CreateTexture(nil, "BORDER")
        qualityGlow:SetSize(blIconSize + 3, blIconSize + 3)
        qualityGlow:SetPoint("CENTER", cell, "CENTER", 0, 0)
        qualityGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
        qualityGlow:SetTexCoord(0, 1, 0, 1)
        qualityGlow:SetVertexColor(0.5, 0.5, 0.5, 0.8)
        cell.qualityGlow = qualityGlow
        local icon = cell:CreateTexture(nil, "ARTWORK")
        icon:SetSize(blIconSize, blIconSize)
        icon:SetPoint("CENTER", cell, "CENTER", 0, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        cell.icon = icon
        local countLabel = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        countLabel:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -3, 3)
        countLabel:SetJustifyH("RIGHT")
        countLabel:SetTextColor(1, 1, 1, 1)
        cell.countLabel = countLabel
        cell:Hide()
        blCells[i] = cell
    end
    function refreshBlacklistFrame()
        local list = {}
        for itemIDKey, v in pairs(currentBlacklist()) do
            local id = tonumber(itemIDKey) or itemIDKey
            local keep = (type(v) == "table" and v.keep) or nil
            list[#list + 1] = { itemID = id, keep = keep }
        end
        table.sort(list, function(a, b) return a.itemID < b.itemID end)
        for i = 1, blMaxCells do
            local cell = blCells[i]
            local entry = list[i]
            if entry and entry.itemID then
                local id = entry.itemID
                local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(id)
                cell.itemID = id
                cell.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
                if quality and quality >= 0 and GetItemQualityColor then
                    local r, g, b = GetItemQualityColor(quality)
                    cell.qualityGlow:SetVertexColor(r, g, b, 0.9)
                else
                    cell.qualityGlow:SetVertexColor(0.5, 0.5, 0.5, 0.8)
                end
                cell.qualityGlow:Show()
                cell.countLabel:SetText(entry.keep and entry.keep > 0 and tostring(entry.keep) or "")
                cell.countLabel:Show()
                cell:Show()
            else
                cell.itemID = nil
                cell:Hide()
            end
        end
        local rows = math.ceil(#list / blGridCols)
        blContent:SetHeight(math.max(1, rows * blCellSize))
        updateBlacklistButtonText()
        if #list == 0 and blFrame and blFrame:IsShown() then
            blFrame:Hide()
        end
    end
    Wowhelpers.RefreshMailBlacklistFrame = refreshBlacklistFrame

    moveFrame:SetScript("OnShow", function()
        local key = ((GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "") .. "-" .. UnitName("player")
        local saved = WowhelpersMailDB.lastTarget[key]
        local chars = getCharsSameRealmFaction()
        local valid = false
        if saved then
            for _, c in ipairs(chars) do if c == saved then valid = true break end end
        end
        if valid then
            UIDropDownMenu_SetSelectedValue(targetDropdown, saved)
            UIDropDownMenu_SetText(targetDropdown, saved)
        else
            UIDropDownMenu_SetSelectedValue(targetDropdown, nil)
            UIDropDownMenu_SetText(targetDropdown, "Charakter wählen...")
        end
        refreshSendItemList()
        updateBlacklistButtonText()
        if updateVerschiebenButtonState then updateVerschiebenButtonState() end
    end)

    -- Hook: wenn Spieler auf "Posteingang" oder "Post versenden" wechselt, unseren Frame verstecken
    hooksecurefunc("MailFrameTab_OnClick", onMailTabClick)
end

local function onMailShow()
    createMoveTabAndFrame()
end

-- Bei Aufruf von SendMail nur Empfänger merken; hinzufügen erst bei MAIL_SEND_SUCCESS
hooksecurefunc("SendMail", function(recipient)
    pendingMailRecipient = (recipient and recipient ~= "" and strtrim(recipient)) or nil
end)

-- Bei MAIL_SHOW Reiter anlegen; bei PLAYER_LOGIN Char speichern; bei Erfolg/Fehler Empfänger verarbeiten
local mailEventFrame = CreateFrame("Frame")
mailEventFrame:RegisterEvent("MAIL_SHOW")
mailEventFrame:RegisterEvent("PLAYER_LOGIN")
mailEventFrame:RegisterEvent("MAIL_SEND_SUCCESS")
mailEventFrame:RegisterEvent("MAIL_FAILED")
mailEventFrame:SetScript("OnEvent", function(_, event)
    if event == "MAIL_SHOW" then
        onMailShow()
    elseif event == "PLAYER_LOGIN" then
        saveCurrentCharacter()
    elseif event == "MAIL_SEND_SUCCESS" then
        if pendingMailRecipient and pendingMailRecipient ~= "" then
            addCharacterToList(pendingMailRecipient)
        end
        pendingMailRecipient = nil
    elseif event == "MAIL_FAILED" then
        pendingMailRecipient = nil
    end
end)

-- StaticPopup: Anzahl behalten beim Auf-Blacklist-setzen (Stapel)
StaticPopupDialogs["WOWHELPERS_MAIL_BLACKLIST_KEEP"] = {
    text = "Anzahl behalten (0 = alles blockieren):",
    button1 = OKAY,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 6,
    OnAccept = function(self)
        local itemID = (self and self.data) or Wowhelpers.MailBlacklistPendingItemID
        local editBox = self and (self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox()))
        if not editBox and _G.StaticPopup1 then
            editBox = _G.StaticPopup1.editBox or _G.StaticPopup1.EditBox
        end
        local num = editBox and tonumber(editBox:GetText()) or 0
        if itemID then
            addToBlacklist(itemID, (num and num > 0) and num or nil)
            if Wowhelpers.RefreshMailSendItemList then Wowhelpers.RefreshMailSendItemList() end
            if Wowhelpers.RefreshMailBlacklistFrame then Wowhelpers.RefreshMailBlacklistFrame() end
        end
        Wowhelpers.MailBlacklistPendingItemID = nil
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

-- Bind-Info im Tooltip (wie Zygor: TooltipDataProcessor + GetItem; zusätzlich SetBagItem für IsBound)
local function addBindLineToTooltip(tip, bindType, isBound, bag, slot)
    if bindType == nil and isBound == nil then return end
    tip = tip or GameTooltip
    if not tip.AddLine then return end
    local t = {}
    if bindType ~= nil then
        local names = { [0] = "Keins", [1] = "BoP", [2] = "BoE", [3] = "OnUse", [4] = "Quest", [7] = "Account", [8] = "Warband", [9] = "WarbandBisAnlegen" }
        t[#t + 1] = "bindType=" .. tostring(bindType) .. " (" .. (names[bindType] or "?") .. ")"
    end
    if isBound ~= nil then t[#t + 1] = "IsBound=" .. tostring(isBound) end
    if type(bag) == "number" and type(slot) == "number" then t[#t + 1] = "Bag=" .. bag .. " Slot=" .. slot end
    if #t > 0 then
        tip:AddLine("|cffa0a0a0[wh] " .. table.concat(t, " | "), 0.7, 0.7, 0.7)
        tip:Show()
    end
end
-- Retail: TooltipDataProcessor (funktioniert mit Taschen-Addons, wie bei Zygor)
if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        pcall(function()
            if not tooltip or not tooltip.GetItem then return end
            local itemName, itemlink = tooltip:GetItem()
            if not itemlink or not itemlink:match("item:") then return end
            local bindType = nil
            if C_Item and C_Item.GetItemInfo then
                local _, _, _, _, _, _, _, _, _, _, _, _, _, bt = C_Item.GetItemInfo(itemlink)
                bindType = bt
            end
            addBindLineToTooltip(tooltip, bindType, nil, nil, nil)
        end)
    end)
end
-- Fallback: SetBagItem (Standard-UI / manche Addons) – dann haben wir auch Bag/Slot und IsBound
hooksecurefunc(GameTooltip, "SetBagItem", function(bag, slot)
    pcall(function()
        if type(bag) ~= "number" or type(slot) ~= "number" then return end
        local getItemLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
        local link = getItemLink(bag, slot)
        if not link then return end
        local bindType = nil
        if C_Item and C_Item.GetItemInfo then
            local _, _, _, _, _, _, _, _, _, _, _, _, _, bt = C_Item.GetItemInfo(link)
            bindType = bt
        end
        local isBound = nil
        if C_Item and C_Item.IsBound then
            local createLoc = (ItemLocation and ItemLocation.CreateFromBagAndSlot) or (ItemLocationMixin and ItemLocationMixin.CreateFromBagAndSlot)
            if createLoc then
                local loc = createLoc(ItemLocation or ItemLocationMixin, bag, slot)
                if loc then isBound = C_Item.IsBound(loc) end
            end
        end
        addBindLineToTooltip(GameTooltip, bindType, isBound, bag, slot)
    end)
end)
hooksecurefunc(GameTooltip, "SetHyperlink", function(link)
    if type(link) ~= "string" or not link:match("item:") then return end
    pcall(function()
        local bindType = nil
        if C_Item and C_Item.GetItemInfo then
            local _, _, _, _, _, _, _, _, _, _, _, _, _, bt = C_Item.GetItemInfo(link)
            bindType = bt
        end
        addBindLineToTooltip(GameTooltip, bindType, nil, nil, nil)
    end)
end)

-- Init für Addon (optional, falls wir später was brauchen)
function Wowhelpers.InitMail()
    -- Reiter wird beim ersten Öffnen des Briefkastens erstellt
end
