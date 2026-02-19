--[[
    wowhelpers – Feature: Questlog leeren
    Bricht alle Quests ab, Button unter Questlog-Fenster, Zählung (API + Fenster).
]]
local Wowhelpers = LibStub("AceAddon-3.0"):GetAddon("wowhelpers")

local ABANDON_DELAY = 0.12  -- Sekunden zwischen zwei Abbrüchen, damit das Spiel nachkommt

--- Bricht alle Quests im Questlog ab (außer nicht abbrechbare z.B. Kampagnen). Mit Verzögerung pro Quest und automatischem Nachlauf, bis wirklich leer.
function Wowhelpers:AbandonAllQuests()
    if not C_QuestLog or not C_QuestLog.GetInfo then
        print("[wowhelpers] Quest-API nicht verfügbar.")
        return
    end
    local questIds = {}
    for i = 1, 50 do
        local info = C_QuestLog.GetInfo(i)
        if not info then break end
        if info.questID and not info.isHeader then
            table.insert(questIds, info.questID)
        end
    end
    if #questIds == 0 then
        print("[wowhelpers] Questlog ist leer.")
        return
    end
    local idx = 0
    local function abandonNext()
        idx = idx + 1
        if idx > #questIds then
            -- Nach kurzer Wartezeit: Button-Ansicht aktualisieren; wenn API noch Quests meldet, nochmal abarbeiten (ein Klick = bis leer)
            C_Timer.After(0.6, function()
                if Wowhelpers.RefreshQuestLogButton then Wowhelpers.RefreshQuestLogButton() end
                if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then return end
                local a, b = C_QuestLog.GetNumQuestLogEntries()
                local numQuests = b or a or 0
                if numQuests > 0 then
                    Wowhelpers:AbandonAllQuests()
                else
                    print("[wowhelpers] Questlog ist leer.")
                end
            end)
            return
        end
        local questID = questIds[idx]
        C_QuestLog.SetSelectedQuest(questID)
        C_QuestLog.SetAbandonQuest()
        C_QuestLog.AbandonQuest()
        C_Timer.After(ABANDON_DELAY, abandonNext)
    end
    abandonNext()
end

--- Prüft, ob im Questlog-Fenster der Text „Keine Quests verfügbar“ / „No quests available“ sichtbar ist.
local EMPTY_QUESTLOG_PHRASES = { "Keine Quests verfügbar", "No quests available", "No quests" }

local function questLogWindowShowsEmpty()
    local ok, found = pcall(function()
        local function scanForEmptyText(f, depth)
            if not f or depth > 10 then return false end
            if f.GetText and f.IsVisible and f:IsVisible() then
                local text = f:GetText()
                if text and type(text) == "string" then
                    local t = text:gsub("|c%x%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
                    for _, phrase in ipairs(EMPTY_QUESTLOG_PHRASES) do
                        if t:find(phrase, 1, true) then return true end
                    end
                end
            end
            if f.GetChildren then
                local n = f:GetNumChildren()
                for i = 1, n do
                    local child = select(i, f:GetChildren())
                    if scanForEmptyText(child, depth + 1) then return true end
                end
            end
            if f.GetRegions then
                for i = 1, f:GetNumRegions() do
                    local r = select(i, f:GetRegions())
                    if r and r.GetText and r.IsVisible and r:IsVisible() then
                        local text = r:GetText()
                        if text and type(text) == "string" then
                            local t = text:gsub("|c%x%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
                            for _, phrase in ipairs(EMPTY_QUESTLOG_PHRASES) do
                                if t:find(phrase, 1, true) then return true end
                            end
                        end
                    end
                end
            end
            return false
        end
        local roots = { QuestMapFrame, WorldMapFrame, QuestLogFrame, _G["WorldQuestsListFrame"], UIParent }
        for _, root in ipairs(roots) do
            if root and (root == UIParent or (root.IsVisible and root:IsVisible())) and scanForEmptyText(root, 0) then
                return true
            end
        end
        return false
    end)
    return ok and found
end

--- Liefert die Anzahl Quests für Anzeige/Button. Wenn das Fenster „Keine Quests verfügbar“ anzeigt, liefert 0.
function Wowhelpers:GetRealQuestCount()
    if questLogWindowShowsEmpty() then return 0 end

    if not C_QuestLog or not C_QuestLog.GetInfo then return 0 end
    local a, b = C_QuestLog.GetNumQuestLogEntries()
    local numShownEntries, numQuests = a, b or a
    if not numQuests or numQuests == 0 then return 0 end
    if numShownEntries and numShownEntries == 0 then return 0 end

    local count = 0
    local maxIndex = (numShownEntries and numShownEntries > 0) and numShownEntries or 50
    for i = 1, maxIndex do
        local info = C_QuestLog.GetInfo(i)
        if not info then break end
        if info.questID and not info.isHeader then
            count = count + 1
        end
    end
    return count
end

function Wowhelpers:ConfirmTrashlog()
    if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then
        print("[wowhelpers] Quest-API nicht verfügbar.")
        return
    end
    local num = Wowhelpers:GetRealQuestCount()
    if num == 0 then
        print("[wowhelpers] Questlog ist leer.")
        return
    end
    StaticPopup_Show("WOWHELPERS_TRASHLOG_CONFIRM", num)
end

-- StaticPopup beim Laden registrieren
StaticPopupDialogs["WOWHELPERS_TRASHLOG_CONFIRM"] = {
    text = "Wirklich alle %d Quest(s) im Log abbrechen?",
    button1 = "Ja",
    button2 = "Nein",
    OnAccept = function()
        Wowhelpers:AbandonAllQuests()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = true,
}

-- UI: Button unter Questlog, Hooks, Ticker. Wird von wowhelpers.lua OnEnable aufgerufen.
function Wowhelpers.InitQuests()
    if _G["WowhelpersQuestLogButton"] then return end
    local questLogButton = CreateFrame("Button", "WowhelpersQuestLogButton", UIParent, "UIPanelButtonTemplate")
        questLogButton:SetSize(120, 22)
        questLogButton:SetText("Questlog leeren")
        questLogButton:SetPoint("TOP", UIParent, "CENTER", 0, -100)
        questLogButton:Hide()
        questLogButton:SetScript("OnClick", function()
            Wowhelpers:ConfirmTrashlog()
        end)

    local function positionUnderMap()
        if not questLogButton then return end
        local parent = QuestMapFrame or WorldMapFrame
        local numQuests = Wowhelpers:GetRealQuestCount()
        local parentShown = parent and parent:IsShown()
        if parentShown and numQuests > 0 then
            questLogButton:SetParent(parent)
            questLogButton:ClearAllPoints()
            questLogButton:SetPoint("TOP", parent, "BOTTOM", 0, -4)
            questLogButton:Show()
        else
            questLogButton:SetParent(UIParent)
            questLogButton:Hide()
        end
    end

    local function hideButton()
        if questLogButton then questLogButton:Hide() end
    end

    local function hookMapAndQuestFrames()
        if WorldMapFrame then
            WorldMapFrame:HookScript("OnShow", positionUnderMap)
            WorldMapFrame:HookScript("OnHide", hideButton)
            hooksecurefunc(WorldMapFrame, "Hide", hideButton)
            if WorldMapFrame:IsShown() then positionUnderMap() end
        end
        if QuestMapFrame and QuestMapFrame ~= WorldMapFrame then
            QuestMapFrame:HookScript("OnShow", positionUnderMap)
            QuestMapFrame:HookScript("OnHide", hideButton)
            hooksecurefunc(QuestMapFrame, "Hide", hideButton)
        end
    end

    if WorldMapFrame then
        hookMapAndQuestFrames()
    else
        C_Timer.After(1, hookMapAndQuestFrames)
    end

    local function startVisibilityCheck()
        C_Timer.NewTicker(0.2, function()
            if not questLogButton or not questLogButton:IsShown() then return end
            local parent = QuestMapFrame or WorldMapFrame
            if not parent or not parent:IsShown() then
                questLogButton:Hide()
            end
        end)
    end
    startVisibilityCheck()

    local questLogEventFrame = CreateFrame("Frame")
    questLogEventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    questLogEventFrame:SetScript("OnEvent", positionUnderMap)

    Wowhelpers.RefreshQuestLogButton = positionUnderMap
end
