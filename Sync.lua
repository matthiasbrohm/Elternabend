-- Elternabend: Abgleich mit gilde-elternabend.de über die Mac-App „Elternabend Abgleich“
--
-- Ein Addon kann nicht ins Internet. Die App auf dem Rechner der Gildenleitung übernimmt das:
--   Spiel → Webseite: Beim Ausloggen und bei /reload legt das Addon Klassenliste, Pinnwand, Berufe und den
--                     Raid-Bericht in die gespeicherte Variable „ElternabendSync“. Die App liest sie und lädt
--                     hoch, was sich geändert hat.
--   Webseite → Spiel: Die App schreibt den nächsten Raid (Anmeldungen, Raidgruppen, Soft-Reserves, Termine)
--                     in die Datei Abgleich.lua. Das Addon übernimmt ihn beim Einloggen oder nach /reload.
-- Aktiv ist das alles nur, wenn die App die Datei Abgleich.lua geschrieben hat – und nur für die Gildenleitung.
local _, ns = ...

local Sync = {}
ns.Sync = Sync

local BERUFE_PAUSE = 30 * 60 -- so oft wird der Berufe-Export im Hintergrund neu vorbereitet

local function AppData()
    local d = ElternabendAbgleich
    return type(d) == "table" and d or nil
end

function Sync:HasApp()
    return AppData() ~= nil
end

local function Store()
    ns.db.sync = ns.db.sync or {}
    return ns.db.sync
end

local function IsLeader()
    return ns.UI and ns.UI.IsLeader and ns.UI:IsLeader() or false
end

-- Spiel → Webseite -----------------------------------------------------------
-- Der Berufe-Export lädt Gegenstandsdaten nach und braucht ein paar Sekunden. Beim Ausloggen ist dafür keine
-- Zeit, deshalb wird er im Hintergrund vorbereitet und hier nur noch abgelegt.
function Sync:PrepareProfessions()
    if self.profBusy or not self:HasApp() or not IsLeader() then return end
    local M, P = ns.Members, ns.Professions
    if not P or not P.PrepareExport then return end
    self.profBusy = true
    local only
    if M and M.list and #M.list > 0 then only = M.byKey end
    local ok = pcall(P.PrepareExport, P, only, nil, function(text, count)
        self.profBusy = false
        if text and (count or 0) > 0 then self.professions = text end
    end)
    if not ok then self.profBusy = false end
end

-- Alles, was die App hochladen soll. nil, wenn es nichts gibt (keine App, keine Gildenleitung).
function Sync:Collect()
    if not self:HasApp() or not IsLeader() then return nil end
    local out = { v = 1, zeit = time(), addon = ns.VERSION or "" }

    local ok, text, count = pcall(function() return ns.Web:BuildRoster() end)
    if ok and text and (count or 0) > 0 then out.mitglieder = text end

    ok, text, count = pcall(function() return ns.Board:ExportForWeb() end)
    if ok and text and (count or 0) > 0 then out.pinnwand = text end

    if self.professions then out.berufe = self.professions end

    -- Raid-Bericht erst, wenn das Raid-Protokoll beendet ist und zu einem Raid aus dem Raidplaner gehört
    local s = ns.db.session
    if s and s.ended and s.raidId and s.raidId ~= "" then
        ok, text = pcall(function() return ns.Web:BuildReport() end)
        if ok and text then out.bericht = text end
    end
    return out
end

ns:On("PLAYER_LOGOUT", function()
    local ok, data = pcall(Sync.Collect, Sync)
    ElternabendSync = ok and data or nil
end)

-- Webseite → Spiel -------------------------------------------------------------
local function RaidTitle(text)
    local id, title, _, when = text:match("raid;([^;\n]*);([^;\n]*);([^;\n]*);([^;\n]*)")
    return id, title, when
end

-- Übernimmt den Raid aus Abgleich.lua. Von selbst nur, wenn er neu ist und gerade kein Raid läuft
-- (mitten im Schlachtzug sollen sich Soft-Reserves nicht unbemerkt ändern); von Hand mit /ea abgleich.
function Sync:ApplyRaid(manual)
    local d = AppData()
    if not d then
        if manual then
            ns.Print("Der Abgleich läuft über die Mac-App „Elternabend Abgleich“. Auf diesem Rechner hat sie noch nichts geschrieben.")
        end
        return false
    end
    local st = Store()
    local raid = type(d.raid) == "string" and d.raid or ""
    local stamp = tonumber(d.zeit) or 0
    if raid == "" or not raid:find("#ELTERNABEND%-RAID") then
        if manual then ns.Print("Abgleich: Auf der Webseite steht gerade kein kommender Raid.") end
        st.raidZeit = stamp
        return false
    end
    if not manual and stamp <= (st.raidZeit or 0) then return false end

    local id, title, when = RaidTitle(raid)
    local label = (title or "?") .. (when and when ~= "" and (" am " .. when) or "")
    if not manual and (IsInRaid() or ns.Web:IsRunning()) then
        if st.hinweis ~= stamp then
            st.hinweis = stamp
            ns.Print("Abgleich: Von der Webseite gibt es neue Raiddaten (" .. label .. "). Solange ein Raid läuft, übernehme ich sie nicht von selbst – |cfff3dc9a/ea abgleich|r holt sie.")
        end
        return false
    end

    ns.Print("Abgleich mit der Webseite (Stand " .. date("%d.%m. %H:%M", stamp) .. "):")
    local ok, done = pcall(ns.Web.ImportPlan, ns.Web, raid)
    if ok and done then
        st.raidZeit, st.raidId = stamp, id
        return true
    end
    if not ok then ns.Print("|cffff5555Abgleich fehlgeschlagen:|r " .. tostring(done)) end
    return false
end

function Sync:Status()
    local d = AppData()
    if not d then
        ns.Print("Abgleich: Die Mac-App „Elternabend Abgleich“ hat auf diesem Rechner noch nichts geschrieben.")
        return
    end
    ns.Print("Abgleich: Daten der Webseite vom " .. date("%d.%m.%Y, %H:%M", tonumber(d.zeit) or 0) .. " Uhr (App " .. tostring(d.app or "?") .. ").")
    if IsLeader() then
        ns.Print("Klassenliste, Pinnwand, Berufe und Raid-Bericht gehen beim Ausloggen oder nach /reload an die Webseite.")
    else
        ns.Print("Hochgeladen wird nur mit einem Charakter der Gildenleitung.")
    end
end

ns:Listen("INIT", function()
    if not Sync:HasApp() then return end
    -- Gildenliste und Rang brauchen nach dem Einloggen ein paar Sekunden
    C_Timer.After(8, function() Sync:ApplyRaid(false) end)
    C_Timer.After(45, function() Sync:PrepareProfessions() end)
    C_Timer.NewTicker(BERUFE_PAUSE, function() Sync:PrepareProfessions() end)
end)
