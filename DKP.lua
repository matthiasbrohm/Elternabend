-- Elternabend: DKP (Punkte und Bieterrunde)
--
-- Für Raids, die nach DKP verteilt werden (Webseite: dkp.php, raids.php: 'loot' => 'dkp'). Der Raid-Text aus dem
-- Raidplaner bringt Mindestgebot und Punktestände mit:
--   dkpregel;Mindestgebot
--   dkp;Charakter;Punkte
-- Statt einer Würfelrunde startet der Plündermeister dann eine verdeckte Bieterrunde:
--   BIDOPEN  Link \t Sekunden \t Mindestgebot   Plündermeister → Gruppe
--   BID      Punkte                              Spieler → Plündermeister (Flüstern); „biete 30“ im Chat geht auch
--   BIDOK    Punkte \t Text                      Plündermeister → Spieler (Bestätigung oder Ablehnung)
--   BIDEND                                       Plündermeister → Gruppe: Runde vorbei (Fenster schließen)
-- Jeder bietet genau einmal verdeckt – keine Bieterschlachten. Nur der Plündermeister sieht die Gebote; wer neu
-- bietet, ersetzt sein altes Gebot. Wer gewinnt, zahlt sein Gebot; der Preis steht im Raid-Bericht (Beute-Art „DKP“)
-- und wird auf der Webseite abgebucht. Die Kontostände aller sind für alle sichtbar (Raid-Übersicht, /ea dkp, Webseite).
local _, ns = ...

local DKP = {}
ns.DKP = DKP

function DKP:Data()
    return ns.db and ns.db.dkp
end

function DKP:Active()
    return self:Data() ~= nil
end

function DKP:Min()
    local d = self:Data()
    return d and d.min or 0
end

-- points: { [Schlüssel] = { name = …, n = Punkte } }
function DKP:Set(points, min, importedAt)
    if next(points) == nil then
        ns.db.dkp = nil
    else
        ns.db.dkp = { points = points, min = math.max(0, tonumber(min) or 0), importedAt = importedAt or time() }
    end
    ns:Fire("DKP_UPDATE")
end

function DKP:Clear()
    ns.db.dkp = nil
    ns:Fire("DKP_UPDATE")
end

-- Punktestand eines Charakters oder nil (unbekannt)
function DKP:Points(name)
    local d, key = self:Data(), ns.NameKey(name)
    local e = d and key and d.points[key]
    return e and e.n
end

-- Nach der Vergabe den Preis abziehen (bis die Webseite neu bucht)
function DKP:Spend(name, amount)
    local d, key = self:Data(), ns.NameKey(name)
    amount = tonumber(amount)
    if not d or not key or not amount or amount <= 0 then return end
    local e = d.points[key]
    if e then
        e.n = e.n - amount
        ns:Fire("DKP_UPDATE")
    end
end

function DKP:PrintOwn()
    if not self:Active() then return end
    local mine = self:Points(ns.UnitFullName("player"))
    ns.Print(mine and string.format("DKP: Du hast %d Punkte (Mindestgebot %d).", mine, self:Min())
        or "DKP: Für dich gibt es noch keine Punkte – sie kommen mit dem ersten Raid.")
end

-- Alle Kontostände, höchste zuerst: { { name, n }, … }
function DKP:List()
    local d, out = self:Data(), {}
    for _, e in pairs(d and d.points or {}) do table.insert(out, { name = e.name, n = e.n }) end
    table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
    return out
end

-- /ea dkp: eigene Punkte und die Stände aller in der Gruppe (sonst aller Konten)
function DKP:PrintAll()
    if not self:Active() then
        ns.Print("Gerade sind keine DKP geladen – sie kommen mit dem Raid-Text aus dem Raidplaner.")
        return
    end
    self:PrintOwn()
    local inGroup = IsInGroup()
    local parts = {}
    for _, e in ipairs(self:List()) do
        if not inGroup or ns.Raid:IsMember(ns.NameKey(e.name)) then table.insert(parts, ns.ShortName(e.name) .. " " .. e.n) end
    end
    if #parts == 0 then return end
    local prefix = inGroup and "DKP in der Gruppe: " or "DKP aller Konten: "
    local line = prefix
    for i, p in ipairs(parts) do
        local add = (i > 1 and line ~= prefix) and (", " .. p) or p
        if #line + #add > 240 then
            ns.Print(line)
            line, add = "   ", p
        end
        line = line .. add
    end
    ns.Print(line)
end

-- Sync in der Gruppe: Zeit;Mindestgebot;Name:Punkte;…
function DKP:Serialize()
    local d = self:Data()
    if not d then return nil end
    local parts = { tostring(d.importedAt or 0), tostring(d.min or 0) }
    for _, e in pairs(d.points) do
        table.insert(parts, (e.name:gsub("[:;]", " ")) .. ":" .. e.n)
    end
    return table.concat(parts, ";")
end

function DKP:ImportSerialized(str, from)
    local fields = { strsplit(";", str or "") }
    local importedAt, min = tonumber(fields[1]) or 0, tonumber(fields[2]) or 0
    local own = self:Data()
    if own and (own.importedAt or 0) > importedAt then return end
    local points = {}
    for i = 3, #fields do
        local name, n = strsplit(":", fields[i])
        local key = name and ns.NameKey(strtrim(name))
        if key and tonumber(n) then points[key] = { name = strtrim(name), n = tonumber(n) } end
    end
    self:Set(points, min, importedAt)
    if ns.Opt("notices") then ns.Print("DKP-Stände von " .. (from or "?") .. " empfangen.") end
    self:PrintOwn()
end

ns.Comm.handlers.DKS = function(sender, parts)
    local data = ns.Comm:Assemble(sender, parts)
    if data and ns.IsTrusted(sender) then DKP:ImportSerialized(data, ns.ShortName(sender)) end
end

-- Bieten (alle) ------------------------------------------------------------------
DKP.round = nil -- { link, from, endsAt, min }

local function BidPopupText(r)
    local mine = DKP:Points(ns.UnitFullName("player"))
    return string.format("Bieterrunde für %s\n(du hast %s, Mindestgebot %d)\n\nVerdeckt: Nur der Plündermeister sieht die Gebote.\n\nDein Gebot:",
        r.link, mine and (mine .. " DKP") or "keine DKP", r.min)
end

function DKP:Bid(amount)
    local r = self.round
    if not r or GetTime() > r.endsAt then
        ns.Print("Gerade läuft keine Bieterrunde.")
        return false
    end
    amount = math.floor(tonumber(amount) or -1)
    if amount < 0 then
        ns.Print("Bitte eine Zahl bieten, z. B. /ea biete 30")
        return false
    end
    if amount < r.min then
        ns.Print(string.format("Das Mindestgebot ist %d DKP.", r.min))
        return false
    end
    local mine = self:Points(ns.UnitFullName("player"))
    if mine and amount > mine then
        ns.Print(string.format("Du hast nur %d DKP.", mine))
        return false
    end
    ns.Comm:SendUrgent("BID", tostring(amount), "WHISPER", r.from)
    ns.Print(string.format("Gebot abgegeben: %d DKP für %s – bis zum Ende kannst du neu bieten, das letzte Gebot zählt.", amount, r.link))
    return true
end

-- Wer die Beute verteilt, darf Bieterrunden starten
local function FromLootLead(sender)
    if ns.IsTrusted(sender) then return true end
    local ml = ns.Raid:GetMasterLooterName()
    return ml ~= nil and ns.SameName(ml, sender)
end

ns.Comm.handlers.BIDOPEN = function(sender, parts)
    if not FromLootLead(sender) then return end
    local link, seconds, min = parts[2], tonumber(parts[3]) or 20, tonumber(parts[4]) or 0
    if not link then return end
    DKP.round = { link = link, from = sender, endsAt = GetTime() + seconds, min = min }
    if ns.SameName(sender, ns.UnitFullName("player")) then return end
    local mine = DKP:Points(ns.UnitFullName("player"))
    ns.Print(string.format("|cff40ff40Bieterrunde:|r %s – %s. Bieten mit /ea biete <Zahl> (mind. %d, %ds).", link,
        mine and ("du hast " .. mine .. " DKP") or "für dich sind keine DKP bekannt", min, seconds))
    ns.Sound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, nil, true)
    -- Fenster mit Eingabefeld: Zahl eintippen, Enter oder „Bieten“
    StaticPopupDialogs["ELTERNABEND_BID"].timeout = seconds
    StaticPopupDialogs["ELTERNABEND_BID"].text = (BidPopupText(DKP.round):gsub("%%", "%%%%"))
    StaticPopup_Show("ELTERNABEND_BID")
end

ns.Comm.handlers.BIDEND = function(sender)
    local r = DKP.round
    if not r or not ns.SameName(sender, r.from) then return end
    DKP.round = nil
    if StaticPopup_Hide then StaticPopup_Hide("ELTERNABEND_BID") end
end

local function BidBox(dialog)
    return dialog.editBox or (dialog.GetEditBox and dialog:GetEditBox())
end

StaticPopupDialogs["ELTERNABEND_BID"] = {
    text = "Bieterrunde",
    button1 = "Bieten",
    button2 = "Passen",
    hasEditBox = true,
    maxLetters = 5,
    OnShow = function(self)
        local box = BidBox(self)
        if box then box:SetNumeric(true) box:SetText("") box:SetFocus() end
    end,
    OnAccept = function(self)
        local box = BidBox(self)
        DKP:Bid(box and box:GetText())
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        DKP:Bid(self:GetText())
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 20,
    whileDead = true,
    hideOnEscape = true,
}

ns.Comm.handlers.BIDOK = function(sender, parts)
    local r = DKP.round
    if r and ns.SameName(sender, r.from) and parts[3] then ns.Print(parts[3]) end
end

-- Gebote annehmen (Plündermeister) -----------------------------------------------

-- Liefert true, wenn das Gebot gilt, sonst false und den Grund
function DKP:Accept(name, amount)
    local cur = ns.Loot.current
    if not cur or not cur.active or not cur.dkp then return false, "Gerade läuft keine Bieterrunde." end
    amount = math.floor(tonumber(amount) or -1)
    local key = ns.NameKey(name)
    if not key or amount < 0 then return false, "Bitte eine Zahl bieten." end
    if not ns.Raid:IsMember(key) then return false, "Bieten können nur Spieler im Raid." end
    if amount < (cur.min or 0) then return false, string.format("Das Mindestgebot ist %d DKP.", cur.min or 0) end
    local points = self:Points(name)
    if points and amount > points then return false, string.format("Du hast nur %d DKP.", points) end
    if not points and amount > 0 then return false, "Für dich sind keine DKP bekannt – bieten geht erst nach dem ersten Raid." end
    local existing = cur.rolls[key]
    if existing then
        existing.roll = amount
    else
        cur.order = cur.order + 1
        cur.rolls[key] = { name = name, key = key, roll = amount, bid = true, order = cur.order, label = "DKP" }
    end
    ns:Fire("ROLL_UPDATE")
    return true, string.format("Gebot angenommen: %d DKP für %s.", amount, cur.link)
end

ns.Comm.handlers.BID = function(sender, parts, channel)
    if channel ~= "WHISPER" then return end
    local ok, text = DKP:Accept(sender, parts[2])
    local cur = ns.Loot.current
    if cur and cur.dkp then ns.Comm:SendUrgent("BIDOK", (parts[2] or "") .. "\t" .. text, "WHISPER", sender) end
    return ok
end

-- „biete 30“ geflüstert (für alle ohne Addon)
ns:On("CHAT_MSG_WHISPER", function(msg, sender)
    if type(msg) ~= "string" or ns.IsSecret(msg) then return end
    local cur = ns.Loot.current
    if not cur or not cur.active or not cur.dkp then return end
    local amount = msg:lower():match("^%s*!?biete%s+(%d+)")
    if not amount then return end
    local _, text = DKP:Accept(sender, amount)
    ns.WhenChatFree(function() C_ChatInfo.SendChatMessage("[Elternabend] " .. text, "WHISPER", nil, sender) end)
end)
