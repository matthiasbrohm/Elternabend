-- Elternabend: Pause für den ganzen Raid
--
-- Die Raidleitung startet eine Pause (z. B. 5 Minuten). Alle mit Addon sehen oben
-- einen großen Countdown, alle anderen bekommen eine Zeile im Raidchat. Wie beim
-- Elternknopf wird nur die Restzeit übertragen.
--   PAUSE     Sekunden   Leitung → Gruppe
--   PAUSEEND             Leitung → Gruppe: weiter geht's
local _, ns = ...
local T = ns.Theme

local Pause = {}
ns.Pause = Pause

local SHOW_DONE = 15 -- so lange „Weiter geht's!“ nach Ablauf zeigen

function Pause:CanControl()
    return IsInGroup() and ns.IsTrusted(ns.UnitFullName("player"))
end

function Pause:Left()
    return self.ends and (self.ends - GetTime())
end

function Pause:IsRunning()
    local left = self:Left()
    return left ~= nil and left > 0
end

function Pause:Start(minutes)
    if not self:CanControl() then
        ns.Print("Eine Pause für alle kann nur die Raidleitung (Leiter oder Assistent) starten.")
        return
    end
    minutes = math.max(1, math.min(30, math.floor(tonumber(minutes) or 5)))
    self:Set(minutes * 60, ns.ShortName(ns.UnitFullName("player")))
    ns.Comm:Send("PAUSE", tostring(minutes * 60))
    ns.Announce(string.format("[Elternabend] %d Minuten Pause – weiter um %s Uhr.", minutes, date("%H:%M", time() + minutes * 60)), true)
end

function Pause:Extend(minutes)
    if not self:IsRunning() then return self:Start(minutes) end
    if not self:CanControl() then return end
    local left = math.floor(self:Left() + minutes * 60)
    self:Set(left, self.by)
    ns.Comm:Send("PAUSE", tostring(left))
    ns.Announce(string.format("[Elternabend] Pause verlängert – weiter um %s Uhr.", date("%H:%M", time() + left)))
end

function Pause:End()
    if not self.ends then return end
    if self:CanControl() then
        ns.Comm:Send("PAUSEEND")
        ns.Announce("[Elternabend] Pause vorbei – weiter geht's!", true)
    end
    self:Finish()
end

function Pause:Set(seconds, by)
    self.ends = GetTime() + seconds
    self.by = by
    self.finished = nil
    self:UpdateFrame()
end

-- Pause zu Ende (abgelaufen oder beendet): kurz „Weiter geht's!“ zeigen
function Pause:Finish()
    if not self.ends then return end
    self.ends = nil
    self.finished = GetTime()
    ns.Sound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master", true)
    self:UpdateFrame()
end

ns.Comm.handlers.PAUSE = function(sender, parts)
    local seconds = tonumber(parts[2])
    if not seconds or not ns.IsTrusted(sender) then return end
    if not Pause.ends then ns.Sound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master", true) end
    Pause:Set(seconds, ns.ShortName(sender))
end

ns.Comm.handlers.PAUSEEND = function(sender)
    if ns.IsTrusted(sender) then Pause:Finish() end
end

-- Wer während der Pause dazukommt, bekommt die Restzeit nachgereicht
local helloHandler = ns.Comm.handlers.HELLO
ns.Comm.handlers.HELLO = function(sender, parts, channel)
    helloHandler(sender, parts, channel)
    if Pause:IsRunning() and Pause:CanControl() then
        ns.Comm:Send("PAUSE", tostring(math.floor(Pause:Left())), "WHISPER", sender)
    end
end

-- Anzeige oben in der Mitte ------------------------------------------------------
function Pause:CreateFrame()
    local f = CreateFrame("Frame", "ElternabendPause", UIParent, "BackdropTemplate")
    f:SetSize(240, 74)
    f:SetPoint("TOP", 0, -110)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    T.Backdrop(f, T.colors.navy, 0.92, 0.7)

    f.kicker = T.Text(f, "kicker", "CENTER")
    f.kicker:SetPoint("TOP", 0, -10)
    f.timer = T.Text(f, "title", "CENTER")
    f.timer:SetPoint("TOP", f.kicker, "BOTTOM", 0, -4)

    -- Nur für die Leitung: verlängern und beenden
    f.more = T.Button(f, "+2 Min", 70)
    f.more:SetHeight(20)
    f.more:SetPoint("BOTTOMLEFT", 10, 8)
    f.more:SetScript("OnClick", function() Pause:Extend(2) end)
    f.stop = T.Button(f, "Beenden", 80)
    f.stop:SetHeight(20)
    f.stop:SetPoint("BOTTOMRIGHT", -10, 8)
    f.stop:SetScript("OnClick", function() Pause:End() end)

    local elapsed = 0
    f:SetScript("OnUpdate", function(_, e)
        elapsed = elapsed + e
        if elapsed < 0.25 then return end
        elapsed = 0
        Pause:UpdateFrame()
    end)
    self.frame = f
    return f
end

function Pause:UpdateFrame()
    local left = self:Left()
    if left and left <= 0 then
        self:Finish()
        return
    end
    local done = self.finished and GetTime() - self.finished < SHOW_DONE
    if not left and not done then
        if self.frame then self.frame:Hide() end
        return
    end
    local f = self.frame or self:CreateFrame()
    local leader = left ~= nil and self:CanControl()
    f.more:SetShown(leader)
    f.stop:SetShown(leader)
    f:SetHeight(leader and 96 or 74)
    if left then
        local s = math.floor(left + 0.5)
        f.kicker:SetText("PAUSE" .. (self.by and ("  ·  " .. self.by:upper()) or ""))
        f.timer:SetText(string.format("%d:%02d", math.floor(s / 60), s % 60))
    else
        f.kicker:SetText("PAUSE VORBEI")
        f.timer:SetText(T.Hex("green", "Weiter geht's!"))
    end
    f:Show()
end

ns:On("GROUP_LEFT", function()
    Pause.ends, Pause.finished = nil, nil
    Pause:UpdateFrame()
end)
