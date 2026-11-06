-- Elternabend: „Kind wach, gleich zurück“
--
-- Ein Klick auf den Elternknopf meldet der Gruppe, dass man kurz weg ist, mit
-- Timer. Alle mit Addon sehen es am Elternknopf und im Raid-Reiter; für alle
-- anderen geht eine kurze Zeile in den Gruppenchat. Übertragen wird nur die
-- Restzeit, damit unterschiedliche Uhren keine Rolle spielen.
local _, ns = ...
local T = ns.Theme

local Away = { others = {} }
ns.Away = Away

BINDING_NAME_ELTERNABEND_KIND = "Kind wach (5 Min) / Wieder da"

local REASON = "Kind wach"
local FORGET_AFTER = 30 * 60 -- so lange nach Ablauf noch als „überfällig“ zeigen

local function Settings()
    return ns.db.away
end

-- „4:05“, „überfällig 1:20“
function Away.FormatLeft(left)
    local s = math.abs(math.floor(left + 0.5))
    local text = string.format("%d:%02d", math.floor(s / 60), s % 60)
    return left >= 0 and text or ("überfällig " .. text)
end

-- Eigener Status ---------------------------------------------------------------
function Away:IsAway()
    return self.me ~= nil
end

function Away:Left()
    return self.me and (self.me.ends - GetTime())
end

function Away:Start(minutes)
    minutes = math.max(1, math.min(60, math.floor(tonumber(minutes) or 5)))
    self.me = { reason = REASON, ends = GetTime() + minutes * 60 }
    self:Broadcast()
    if Settings().announce and IsInGroup() then
        ns.Announce(string.format("[Elternabend] Kind ist wach – bin in ca. %d Min. zurück.", minutes))
    end
    if ns.ChatLocked() then
        ns.Print("Gerade läuft ein Kampf: Die Gruppe sieht deinen Status, sobald er vorbei ist.")
    end
    ns:Fire("AWAY_UPDATE")
end

function Away:Extend(minutes)
    if not self.me then return self:Start(minutes) end
    self.me.ends = math.max(self.me.ends, GetTime()) + minutes * 60
    self:Broadcast()
    ns:Fire("AWAY_UPDATE")
end

function Away:Back()
    if not self.me then return end
    self.me = nil
    ns.Comm:Send("BACK")
    if Settings().announce and IsInGroup() then ns.Announce("[Elternabend] Bin wieder da!") end
    ns:Fire("AWAY_UPDATE")
end

function Away:Toggle()
    if self.me then self:Back() else self:Start(5) end
end

function Away:Broadcast(channel, target)
    local left = self:Left()
    if left then ns.Comm:Send("AWAY", math.max(0, math.floor(left)) .. "\t" .. self.me.reason, channel, target) end
end

-- Status der anderen -----------------------------------------------------------
function Away:Get(name)
    local m = ns.Raid:Find(name)
    local key = m and m.key or ns.NameKey(name)
    return key and self.others[key]
end

-- Sortiert nach Restzeit; Spieler, die nicht mehr in der Gruppe sind, fallen raus
function Away:List()
    local list = {}
    for key, a in pairs(self.others) do
        local left = a.ends - GetTime()
        if not ns.Raid:Find(key) or left < -FORGET_AFTER then
            self.others[key] = nil
        else
            table.insert(list, { key = key, name = a.name, reason = a.reason, left = left })
        end
    end
    table.sort(list, function(a, b) return a.left < b.left end)
    return list
end

ns.Comm.handlers.AWAY = function(sender, parts)
    local seconds = tonumber(parts[2])
    if not seconds then return end
    local m = ns.Raid:Find(sender)
    local key = m and m.key or ns.NameKey(sender)
    Away.others[key] = { name = ns.ShortName(m and m.name or sender), reason = parts[3] or REASON, ends = GetTime() + seconds }
    ns:Fire("AWAY_UPDATE")
end

ns.Comm.handlers.BACK = function(sender)
    local m = ns.Raid:Find(sender)
    Away.others[m and m.key or ns.NameKey(sender)] = nil
    ns:Fire("AWAY_UPDATE")
end

-- Wer neu in die Gruppe kommt, fragt mit HELLO – dann eigenen Status nachreichen
local helloHandler = ns.Comm.handlers.HELLO
ns.Comm.handlers.HELLO = function(sender, parts, channel)
    helloHandler(sender, parts, channel)
    if Away.me then Away:Broadcast("WHISPER", sender) end
end

-- Elternknopf auf dem Bildschirm -------------------------------------------------
function Away:CreateButton()
    local s = Settings()
    local f = CreateFrame("Frame", "ElternabendElternknopf", UIParent, "BackdropTemplate")
    f:SetSize(286, 58)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        s.left, s.top = self:GetLeft(), self:GetTop()
    end)
    T.Backdrop(f, T.colors.navy, 0.9, 0.6)

    f.kicker = T.Text(f, "kicker")
    f.kicker:SetPoint("TOPLEFT", 10, -8)
    f.kicker:SetText("ELTERNKNOPF")

    -- Bereit: drei Knöpfe für 5, 10 und 15 Minuten
    f.start = T.Button(f, "Kind wach · 5 Min", 150, "primary")
    f.start:SetPoint("TOPLEFT", 10, -22)
    f.start:SetScript("OnClick", function() Away:Start(5) end)
    f.ten = T.Button(f, "10", 52)
    f.ten:SetPoint("LEFT", f.start, "RIGHT", 6, 0)
    f.ten:SetScript("OnClick", function() Away:Start(10) end)
    f.fifteen = T.Button(f, "15", 52)
    f.fifteen:SetPoint("LEFT", f.ten, "RIGHT", 6, 0)
    f.fifteen:SetScript("OnClick", function() Away:Start(15) end)

    -- Weg: groß nur die Restzeit (der Grund steht oben), daneben +5 und „Wieder da“
    f.timer = T.Text(f, "heading")
    f.timer:SetPoint("TOPLEFT", 10, -26)
    f.timer:SetWidth(90)
    f.timer:SetWordWrap(false)
    f.more = T.Button(f, "+5 Min", 64)
    f.back = T.Button(f, "Wieder da", 100, "primary")
    f.back:SetPoint("TOPRIGHT", -10, -22)
    f.back:SetScript("OnClick", function() Away:Back() end)
    f.more:SetPoint("RIGHT", f.back, "LEFT", -8, 0)
    f.more:SetScript("OnClick", function() Away:Extend(5) end)

    -- Andere aus der Gruppe, die gerade weg sind
    f.lines = {}

    local elapsed = 0
    f:SetScript("OnUpdate", function(_, e)
        elapsed = elapsed + e
        if elapsed < 0.5 then return end
        elapsed = 0
        Away:UpdateButton()
    end)

    if s.left then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", s.left, s.top)
    else
        f:SetPoint("TOP", 0, -40)
    end
    self.button = f
    return f
end

-- Wirklich mit anderen in einer Gruppe? IsInGroup() allein reicht nicht: Wer
-- jemanden einlädt, ist schon vor dem Annehmen „in einer Gruppe“ (nur mit sich
-- selbst), und beim Verlassen meldet der Client kurz noch die alte Gruppe.
local function HasGroupmates()
    if IsInRaid() then return GetNumGroupMembers() > 1 end
    return IsInGroup() and UnitExists("party1")
end

function Away:UpdateButton()
    local s = Settings()
    local visible = s.showButton and (HasGroupmates() or self.me ~= nil)
    if not visible then
        if self.button then self.button:Hide() end
        return
    end
    local f = self.button or self:CreateButton()

    local away = self.me ~= nil
    f.start:SetShown(not away)
    f.ten:SetShown(not away)
    f.fifteen:SetShown(not away)
    f.timer:SetShown(away)
    f.more:SetShown(away)
    f.back:SetShown(away)
    if away then
        local left = self:Left()
        local s = math.abs(math.floor(left + 0.5))
        local clock = string.format("%s%d:%02d", left >= 0 and "" or "+", math.floor(s / 60), s % 60)
        f.kicker:SetText("ELTERNKNOPF  ·  " .. REASON:upper() .. (left >= 0 and "" or "  ·  ÜBERFÄLLIG"))
        f.timer:SetText(T.Hex(left >= 0 and "goldBright" or "orange", clock))
    else
        f.kicker:SetText("ELTERNKNOPF")
    end

    local list = self:List()
    for i, a in ipairs(list) do
        local line = f.lines[i]
        if not line then
            line = T.Text(f, "small")
            line:SetPoint("TOPLEFT", 10, -54 - (i - 1) * 16)
            line:SetPoint("RIGHT", f, "RIGHT", -10, 0)
            line:SetWordWrap(false)
            f.lines[i] = line
        end
        line:SetText(T.Hex("goldBright", a.name) .. "  " .. a.reason .. "  " .. T.Hex(a.left >= 0 and "muted" or "orange", Away.FormatLeft(a.left)))
        line:Show()
    end
    for i = #list + 1, #f.lines do f.lines[i]:Hide() end
    f:SetHeight(58 + (#list > 0 and (#list * 16 + 4) or 0))
    f:Show()
end

ns:Listen("AWAY_UPDATE", function()
    Away:UpdateButton()
    ns.UI:QueueRefresh()
end)
ns:Listen("ROSTER_UPDATE", function() Away:UpdateButton() end)
ns:On("PLAYER_LOGIN", function() Away:UpdateButton() end)
ns:On("GROUP_LEFT", function()
    wipe(Away.others)
    Away:UpdateButton()
    -- Der Client räumt die Gruppe nicht immer im selben Moment auf: kurz danach nachsehen
    C_Timer.After(0.5, function() Away:UpdateButton() end)
end)
