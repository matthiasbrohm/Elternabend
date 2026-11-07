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
-- Ein kleiner Knopf: Linksklick 5 Min, Rechtsklick 10 Min. Ist man weg, zeigt er die
-- Restzeit: Linksklick „Wieder da“, Rechtsklick +5 Min. Ziehen verschiebt ihn.
local BTN_W, BTN_H = 100, 24

local function ShowTooltip(f)
    GameTooltip:SetOwner(f, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Elternknopf", T.colors.goldBright[1], T.colors.goldBright[2], T.colors.goldBright[3])
    if Away.me then
        GameTooltip:AddLine(REASON .. " – zurück in " .. Away.FormatLeft(Away:Left()), 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Linksklick: wieder da", 0.84, 0.69, 0.35)
        GameTooltip:AddLine("Rechtsklick: 5 Minuten mehr", 0.84, 0.69, 0.35)
    else
        GameTooltip:AddLine("Kind wach? Die Gruppe sieht, wann du zurück bist.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Linksklick: 5 Minuten", 0.84, 0.69, 0.35)
        GameTooltip:AddLine("Rechtsklick: 10 Minuten", 0.84, 0.69, 0.35)
    end
    GameTooltip:AddLine("Ziehen: verschieben  ·  /ea knopf: ein- oder ausblenden", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function Away:CreateButton()
    local s = Settings()
    local f = CreateFrame("Button", "ElternabendElternknopf", UIParent, "BackdropTemplate")
    f:SetSize(BTN_W, BTN_H)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self.dragging = true; self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        s.left, s.top = self:GetLeft(), self:GetTop()
        C_Timer.After(0, function() self.dragging = false end)
    end)
    T.Backdrop(f, T.colors.navy, 0.92, 0.7)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(BTN_H - 4, BTN_H - 4)
    f.icon:SetPoint("LEFT", 2, 0)
    f.icon:SetTexture(ns.LOGO)
    f.label = T.Text(f, "small")
    f.label:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
    f.label:SetPoint("RIGHT", -4, 0)
    f.label:SetJustifyH("LEFT")
    f.label:SetWordWrap(false)

    f:SetScript("OnClick", function(self, button)
        if self.dragging then return end
        if Away.me then
            if button == "RightButton" then Away:Extend(5) else Away:Back() end
        else
            Away:Start(button == "RightButton" and 10 or 5)
        end
        if GameTooltip:IsOwned(self) then ShowTooltip(self) end
    end)
    f:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(T.colors.goldBright[1], T.colors.goldBright[2], T.colors.goldBright[3], 1)
        ShowTooltip(self)
    end)
    f:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(T.colors.gold[1], T.colors.gold[2], T.colors.gold[3], 0.7)
        GameTooltip_Hide()
    end)

    -- Andere aus der Gruppe, die gerade weg sind: kleine Zeilen unter dem Knopf
    f.lines = {}

    local elapsed = 0
    f:SetScript("OnUpdate", function(self, e)
        elapsed = elapsed + e
        if elapsed < 0.5 then return end
        elapsed = 0
        Away:UpdateButton()
        if Away.me and GameTooltip:IsOwned(self) then ShowTooltip(self) end
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

    if self.me then
        local left = self:Left()
        -- kurz halten: „4:32“, überfällig „+1:20“
        local sec = math.abs(math.floor(left + 0.5))
        f.label:SetText(T.Hex(left >= 0 and "goldBright" or "orange",
            string.format("%s%d:%02d", left >= 0 and "" or "+", math.floor(sec / 60), sec % 60)))
        f:SetBackdropColor(0.35, 0.22, 0.05, 0.95)
    else
        f.label:SetText("Kind wach")
        f:SetBackdropColor(T.colors.navy[1], T.colors.navy[2], T.colors.navy[3], 0.92)
    end

    local list = self:List()
    for i, a in ipairs(list) do
        local line = f.lines[i]
        if not line then
            line = T.Text(f, "small")
            line:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 2, -2 - (i - 1) * 15)
            line:SetWidth(220)
            line:SetJustifyH("LEFT")
            line:SetWordWrap(false)
            line:SetShadowOffset(1, -1)
            f.lines[i] = line
        end
        line:SetText(T.Hex("goldBright", a.name) .. "  " .. T.Hex(a.left >= 0 and "muted" or "orange", Away.FormatLeft(a.left)))
        line:Show()
    end
    for i = #list + 1, #f.lines do f.lines[i]:Hide() end
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
