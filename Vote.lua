-- Elternabend: Abstimmung im Raid
--
-- Die Leitung der Gruppe (im Schlachtzug Leiter oder Assistent) stellt eine Frage, z. B. „Noch ein Boss?“.
-- Bei allen mit Addon geht ein kleines Fenster mit drei Knöpfen auf: Dafür, Dagegen, Passt beides.
-- Alle sehen, wer wie gestimmt hat und wer noch fehlt (Raid » Abstimmung). Umentscheiden geht, bis die
-- Leitung die Abstimmung beendet; nach zehn Minuten endet sie von selbst. Das Ergebnis kann die Leitung
-- im Raidchat ansagen.
--   VT  S id Frage    (Gruppe, von der Leitung: Abstimmung startet)
--   VT  V id Wahl     (Gruppe: 1 = dafür, 2 = dagegen, 3 = passt beides; die letzte Stimme zählt)
--   VT  E id          (Gruppe, von der Leitung: beendet)
local _, ns = ...
local T = ns.Theme

local Vote = {}
ns.Vote = Vote

Vote.CHOICES = {
    { label = "Dafür", color = "green" },
    { label = "Dagegen", color = "red" },
    { label = "Passt beides", color = "goldBright" },
}
Vote.MAX_AGE = 600 -- Sekunden, dann endet eine Abstimmung von selbst
Vote.MAX_LEN = 120 -- Zeichen für die Frage

local SEP = "\t"
local GROUP_CHANNELS = { RAID = true, PARTY = true, INSTANCE_CHAT = true }

function Vote.CanStart()
    return IsInGroup() and ns.IsTrusted(ns.UnitFullName("player"))
end

local function CleanQuestion(q)
    q = strtrim((tostring(q or ""):gsub("[\t\r\n|]", " ")))
    if #q > Vote.MAX_LEN then q = (q:sub(1, Vote.MAX_LEN):gsub("[\192-\255][\128-\191]*$", "")) .. "…" end
    return q
end

-- Leitung: Frage an die Gruppe
function Vote:Start(question, announce)
    question = CleanQuestion(question)
    if question == "" then
        ns.Print("Bitte zuerst die Frage eintragen, z. B. „Noch ein Boss?“.")
        return false
    end
    if not IsInGroup() then
        ns.Print("Abstimmen geht nur in einer Gruppe oder einem Schlachtzug.")
        return false
    end
    if not Vote.CanStart() then
        ns.Print("Eine Abstimmung startet die Leitung der Gruppe (Leiter oder Assistent).")
        return false
    end
    local id = tostring(math.random(1000, 9999))
    ns.Comm:Send("VT", table.concat({ "S", id, question }, SEP))
    if announce then
        ns.Announce("Abstimmung: " .. question .. " – Dafür, Dagegen oder Passt beides? Mit dem Gildenaddon im Fenster abstimmen.")
    end
    self:Begin(id, question, ns.UnitFullName("player"), true)
    return true
end

function Vote:Begin(id, question, host, open)
    self.current = { id = id, question = question, host = host, started = GetTime(), votes = {}, open = true }
    if open then self:ShowPopup() end
    ns:Fire("VOTE_UPDATE")
end

-- Eigene Stimme (umentscheiden erlaubt)
function Vote:Cast(choice)
    local v = self.current
    if not v or not v.open or not self.CHOICES[choice] then return false end
    local me = ns.UnitFullName("player")
    v.votes[ns.NameKey(me) or "?"] = { name = me, choice = choice }
    ns.Comm:Send("VT", table.concat({ "V", v.id, choice }, SEP))
    self:CheckComplete()
    ns:Fire("VOTE_UPDATE")
    return true
end

function Vote:Mine()
    local v = self.current
    local mine = v and v.votes[ns.NameKey(ns.UnitFullName("player")) or ""]
    return mine and mine.choice
end

-- Leitung: beenden
function Vote:End()
    local v = self.current
    if not v or not v.open then return false end
    if v.host and not ns.SameName(v.host, ns.UnitFullName("player")) and not Vote.CanStart() then
        ns.Print("Beenden kann nur die Leitung der Gruppe.")
        return false
    end
    ns.Comm:Send("VT", table.concat({ "E", v.id }, SEP))
    self:Finish()
    return true
end

function Vote:Finish()
    local v = self.current
    if not v or not v.open then return end
    v.open = false
    v.ended = GetTime()
    ns:Fire("VOTE_UPDATE")
end

-- Zählung: je Wahl die Namen, dazu wer in der Gruppe noch nicht abgestimmt hat
function Vote:Tally()
    local v = self.current
    local out = { { }, { }, { }, missing = {}, total = 0 }
    if not v then return out end
    for _, e in pairs(v.votes) do
        if out[e.choice] then
            table.insert(out[e.choice], e)
            out.total = out.total + 1
        end
    end
    for i = 1, 3 do
        table.sort(out[i], function(a, b) return (ns.ShortName(a.name) or a.name) < (ns.ShortName(b.name) or b.name) end)
    end
    for _, m in ipairs(ns.Raid and ns.Raid.members or {}) do
        if m.key and not v.votes[m.key] then table.insert(out.missing, m) end
    end
    table.sort(out.missing, function(a, b) return (ns.ShortName(a.name) or a.name) < (ns.ShortName(b.name) or b.name) end)
    return out
end

-- Kurzform „29 dafür, 1 dagegen, 10 passt beides“ und die ganze Zeile für den Raidchat
function Vote:CountText()
    local t = self:Tally()
    local parts = {}
    for i, c in ipairs(self.CHOICES) do parts[i] = #t[i] .. " " .. c.label:lower() end
    return table.concat(parts, ", ")
end

function Vote:ResultText()
    local v = self.current
    if not v then return nil end
    return "Ergebnis der Abstimmung „" .. v.question .. "“: " .. self:CountText()
end

-- Haben alle in der Gruppe abgestimmt? Dann bekommt die Leitung Bescheid und kann das Ergebnis posten.
function Vote:CheckComplete()
    local v = self.current
    if not v or not v.open or v.complete then return end
    local t = self:Tally()
    if #t.missing == 0 and t.total > 0 then
        v.complete = true
        if Vote.CanStart() then
            ns.Sound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master", true)
            ns.Print("Alle haben abgestimmt: " .. self:CountText() .. " – mit „Ergebnis posten“ sehen es alle im Raidchat.")
        end
    end
end

function Vote:Announce()
    local text = self:ResultText()
    if not text then return false end
    if not Vote.CanStart() then
        ns.Print("Das Ergebnis sagt die Leitung der Gruppe an.")
        return false
    end
    ns.Announce(text)
    return true
end

ns.Comm.handlers.VT = function(sender, parts, channel)
    if not GROUP_CHANNELS[channel] then return end
    local kind, id = parts[2], parts[3]
    if not id or id == "" then return end
    if kind == "S" then
        if not ns.IsTrusted(sender) then return end
        local question = CleanQuestion(parts[4])
        if question == "" then return end
        local open = ns.Opt("voteOpen")
        Vote:Begin(id, question, sender, open)
        ns.Sound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master", true)
        ns.Print((ns.ShortName(sender) or "Die Leitung") .. " fragt: „" .. question .. "“ – "
            .. (open and "abstimmen im Fenster." or "abstimmen unter Raid » Abstimmung."))
    elseif kind == "V" then
        local v, choice, key = Vote.current, tonumber(parts[4]), ns.NameKey(sender)
        if not v or v.id ~= id or not v.open or not key or not Vote.CHOICES[choice or 0] then return end
        v.votes[key] = { name = sender, choice = choice }
        Vote:CheckComplete()
        ns:Fire("VOTE_UPDATE")
    elseif kind == "E" then
        local v = Vote.current
        if not v or v.id ~= id then return end
        if not ns.IsTrusted(sender) and not ns.SameName(sender, v.host) then return end
        Vote:Finish()
    end
end

-- Nach zehn Minuten endet eine Abstimmung von selbst; wer die Gruppe verlässt, sieht sie nicht weiter laufen
ns:Listen("INIT", function()
    C_Timer.NewTicker(10, function()
        local v = Vote.current
        if v and v.open and (GetTime() - v.started > Vote.MAX_AGE or not IsInGroup()) then Vote:Finish() end
    end)
end)

-- Kleines Fenster mit der Frage ----------------------------------------------------------------
local W = 460

function Vote:CreatePopup()
    if self.popup then return self.popup end
    local c = T.colors
    local d = CreateFrame("Frame", "ElternabendVote", UIParent, "BackdropTemplate")
    d:SetSize(W, 196)
    d:SetPoint("TOP", 0, -150)
    d:SetFrameStrata("DIALOG")
    d:SetToplevel(true)
    d:SetMovable(true)
    d:SetClampedToScreen(true)
    d:EnableMouse(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    T.Backdrop(d, c.navy, 0.98, 0.7)
    tinsert(UISpecialFrames, "ElternabendVote")

    local kicker = T.Text(d, "kicker")
    kicker:SetPoint("TOPLEFT", 20, -16)
    kicker:SetText("ELTERNABEND · ABSTIMMUNG")
    d.from = T.Text(d, "muted", "RIGHT")
    d.from:SetPoint("TOPRIGHT", -20, -14)
    d.question = T.Text(d, "heading")
    d.question:SetPoint("TOPLEFT", 20, -36)
    d.question:SetWidth(W - 40)
    d.question:SetSpacing(3)

    d.buttons = {}
    local bw = (W - 40 - 16) / 3
    for i, choice in ipairs(self.CHOICES) do
        local b = T.Button(d, choice.label, bw)
        b:SetHeight(32)
        b:SetPoint("TOPLEFT", 20 + (i - 1) * (bw + 8), -96)
        b:SetScript("OnClick", function() Vote:Cast(i) end)
        d.buttons[i] = b
    end
    d.state = T.Text(d, "small")
    d.state:SetPoint("TOPLEFT", 20, -140)
    d.state:SetWidth(W - 150)
    d.state:SetJustifyH("LEFT")
    d.close = T.Button(d, "Schließen", 100)
    d.close:SetPoint("BOTTOMRIGHT", -16, 14)
    d.close:SetScript("OnClick", function() d:Hide() end)
    d:Hide()
    self.popup = d
    return d
end

function Vote:ShowPopup()
    local d = self:CreatePopup()
    d:Show()
    self:RefreshPopup()
end

function Vote:RefreshPopup()
    local d = self.popup
    if not d or not d:IsShown() then return end
    local v = self.current
    if not v then d:Hide() return end
    d.question:SetText(v.question)
    d.from:SetText(v.host and ("von " .. (ns.ShortName(v.host) or v.host)) or "")
    local mine = self:Mine()
    for i, b in ipairs(d.buttons) do
        local choice = self.CHOICES[i]
        b:SetText(mine == i and T.Hex(choice.color, "» " .. choice.label .. " «") or choice.label)
        b:SetEnabled(v.open)
    end
    local t = self:Tally()
    local count = #ns.Raid.members > 0 and (t.total .. " von " .. math.max(#ns.Raid.members, t.total)) or tostring(t.total)
    if not v.open then
        d.state:SetText(T.Hex("goldBright", "Beendet") .. "  ·  " .. self:CountText())
    elseif mine then
        d.state:SetText("Deine Stimme: " .. T.Hex(self.CHOICES[mine].color, self.CHOICES[mine].label)
            .. T.Hex("muted", "  ·  " .. count .. " haben abgestimmt – umentscheiden geht noch."))
    else
        d.state:SetText(T.Hex("muted", count .. " haben abgestimmt."))
    end
end

ns:Listen("VOTE_UPDATE", function() Vote:RefreshPopup() end)
