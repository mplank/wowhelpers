-- Modernes Addon-Grundgerüst
local AceAddon = LibStub("AceAddon-3.0")
local Wowhelpers = AceAddon:NewAddon("wowhelpers")

local eventFrame = CreateFrame("Frame")

function Wowhelpers:OnInitialize()
    SLASH_WOWHELPERS1 = "/wh"
    SLASH_WOWHELPERS2 = "/wowhelpers"
    SlashCmdList["WOWHELPERS"] = function(msg)
        local raw = msg:gsub("^%s+", ""):gsub("%s+$", "")
        local cmd, rest = raw:match("^(%S+)%s*(.*)$")
        if not cmd then cmd, rest = raw, "" end
        local c = cmd:lower()
        if c == "trashlog" or c == "trash" then
            Wowhelpers:ConfirmTrashlog()
        elseif c == "sell" or c == "verkaufen" then
            Wowhelpers:SellAllAtVendor()
        elseif c == "destroy" or c == "zerstören" or c == "löschen" then
            Wowhelpers:DestroyGreyItems()
        elseif c == "emptybags" or c == "empty" or c == "taschen" then
            Wowhelpers:SellAllAtVendor()
            Wowhelpers:DestroyGreyItems()
        elseif c == "mailcharpurge" then
            Wowhelpers:MailCharPurge(rest)
        else
            print("[wowhelpers] Befehle:")
            print("  /wh trashlog        – alle Quests abbrechen (mit Abfrage)")
            print("  /wh sell            – alles Verkaufbare am Händler verkaufen (Fenster offen)")
            print("  /wh destroy         – nicht verkaufbare/graue Gegenstände zerstören (Klick + ggf. Enter)")
            print("  /wh emptybags       – verkaufen + zerstören")
            print("  /wh mailcharpurge <Name> – Char aus Mail-Zielliste entfernen")
        end
    end
end

function Wowhelpers:OnEnable()
    if Wowhelpers.InitQuests then Wowhelpers.InitQuests() end
    if Wowhelpers.InitSell then Wowhelpers.InitSell() end
    if Wowhelpers.InitMail then Wowhelpers.InitMail() end
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        print("[wowhelpers] Addon geladen und bereit!")
    end
end)
eventFrame:RegisterEvent("PLAYER_LOGIN")
