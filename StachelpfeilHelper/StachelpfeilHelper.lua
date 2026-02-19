local frame = CreateFrame("Frame", "StachelpfeilHelperFrame", UIParent)
frame:SetSize(220, 60)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
frame:Hide()


-- Progressbar für Buffdauer
local bar = CreateFrame("StatusBar", nil, frame)
bar:SetSize(200, 20)
bar:SetPoint("TOP", frame, "TOP", 0, -5)
bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
bar:SetMinMaxValues(0, 1)
bar:SetValue(0)
bar:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background"})

-- Stack-Anzeige
local stackText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
stackText:SetPoint("LEFT", bar, "RIGHT", 10, 0)
stackText:SetText("Stacks: 0")

-- Freeze Tracker
local freezeText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
freezeText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 5)
freezeText:SetText("")

local BUFF_NAME = "Stachelpfeil"

frame:RegisterEvent("UNIT_AURA")

local function CheckBuff()
    local aura = AuraUtil.FindAuraByName(BUFF_NAME, "player", "HELPFUL")
    if aura then
        local duration = aura.duration or 0
        local expirationTime = aura.expirationTime or 0
        local stacks = aura.applications or 0
        local timeLeft = expirationTime - GetTime()
        frame:Show()
        -- Progressbar
        if duration > 0 then
            bar:SetMinMaxValues(0, duration)
            bar:SetValue(timeLeft)
        else
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0)
        end
        -- Stack-Anzeige
        stackText:SetText("Stacks: " .. stacks)
        -- Freeze Tracker
        if stacks < 3 then
            freezeText:SetText("Buff erneuern!")
            freezeText:SetTextColor(1, 0, 0)
        elseif timeLeft < (duration * 0.33) then
            freezeText:SetText("Bald erneuern!")
            freezeText:SetTextColor(1, 1, 0)
        else
            freezeText:SetText("")
        end
    else
        frame:Hide()
    end
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            CheckBuff()
        end
    end
end)

C_Timer.After(1, CheckBuff)
