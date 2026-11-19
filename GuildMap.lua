-- Elternabend: Gildenmitglieder auf der Weltkarte
--
-- Wer den Schalter einschaltet (Einstellungen » „Gildenkarte“), teilt seinen Standort mit der Gilde
-- und sieht alle anderen, die ihn auch teilen, als Punkt in Klassenfarbe auf der Weltkarte – Name
-- und Stufe beim Darüberfahren. Standardmäßig aus. In Dungeons, Raids und Schlachtfeldern wird
-- nichts gesendet; Ausschalten nimmt dich sofort von den Karten der anderen.
--
-- Gesendet wird über den Addon-Kanal der Gilde (nicht im Chat): Kontinent und Weltkoordinaten,
-- Stufe und Klasse – alle 20 Sekunden, wenn man sich bewegt hat, sonst jede Minute.
local _, ns = ...
local T = ns.Theme

local Map = { peers = {}, pins = {} }
ns.GuildMap = Map

local SEND_MOVED, SEND_ALWAYS = 20, 60
local FORGET = 150 -- Sekunden ohne Meldung: Punkt verschwindet

function Map:Enabled()
    return ns.db and ns.db.settings.guildMap == true
end

-- Eigener Standort in Weltkoordinaten (oder nil in Instanzen und ohne Karte)
function Map.Position()
    if IsInInstance and IsInInstance() then return nil end
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then return nil end
    -- Verbirgt das Spiel den Ort (geheime Werte), wird nichts gesendet – und nichts davon geprüft
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or ns.IsSecret(mapID) or not mapID then return nil end
    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok2 or ns.IsSecret(pos) or not pos then return nil end
    local ok3, continent, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, pos)
    if not ok3 or not continent or not world then return nil end
    local x, y = world.x, world.y
    if world.GetXY then x, y = world:GetXY() end
    if not x or not y or ns.IsSecret(x) then return nil end
    return continent, x, y
end

function Map:Send(force)
    if not ns.Info:AtHome() then return end
    if not self:Enabled() then return end
    local continent, x, y = Map.Position()
    local now = GetTime()
    if not continent then
        if self.sentAt then
            ns.Comm:Send("POS", "off", "GUILD")
            self.sentAt, self.last = nil, nil
        end
        return
    end
    local moved = not self.last or math.abs(self.last[2] - x) + math.abs(self.last[3] - y) > 5 or self.last[1] ~= continent
    local due = force or not self.sentAt or (moved and now - self.sentAt >= SEND_MOVED) or now - self.sentAt >= SEND_ALWAYS
    if not due then return end
    local _, class = UnitClass("player")
    local level = UnitLevel("player")
    if ns.IsSecret(level) then level = 0 end
    if ns.IsSecret(class) then class = "" end
    ns.Comm:Send("POS", string.format("%d\t%.1f\t%.1f\t%d\t%s", continent, x, y, level or 0, class or ""), "GUILD", nil, true)
    self.sentAt, self.last = now, { continent, x, y }
end

-- Ausschalten: sofort von den Karten der anderen
function Map:Stop()
    if self.sentAt then ns.Comm:Send("POS", "off", "GUILD") end
    self.sentAt, self.last = nil, nil
    self.peers = {}
    self:Refresh()
end

ns.Comm.handlers.POS = function(sender, parts)
    if not Map:Enabled() or not ns.Members:Find(sender) then return end
    if ns.SameName(sender, ns.UnitFullName("player")) then return end
    local key = ns.NameKey(sender)
    if not key then return end
    if parts[2] == "off" then
        Map.peers[key] = nil
    else
        local continent, x, y = tonumber(parts[2]), tonumber(parts[3]), tonumber(parts[4])
        if not continent or not x or not y then return end
        Map.peers[key] = { name = sender, continent = continent, x = x, y = y, level = tonumber(parts[5]),
            class = parts[6], t = GetTime() }
    end
    Map:Refresh()
end

-- Punkte auf der Weltkarte -----------------------------------------------------------------------
-- Wer mit in der Gruppe oder im Raid ist, hat schon den Punkt des Spiels – dann keinen zweiten
function Map.InMyGroup(name)
    if not IsInGroup() then return false end
    local raid = IsInRaid()
    for i = 1, raid and GetNumGroupMembers() or 4 do
        local unit = raid and ("raid" .. i) or ("party" .. i)
        if UnitExists(unit) then
            local other = ns.UnitFullName(unit)
            if other and not ns.IsSecret(other) and ns.SameName(other, name) then return true end
        end
    end
    return false
end

local function Pin(i, canvas)
    local pin = Map.pins[i]
    if pin and pin:GetParent() == canvas then return pin end
    pin = CreateFrame("Frame", nil, canvas)
    pin:SetSize(10, 10)
    pin:SetFrameLevel(canvas:GetFrameLevel() + 2000) -- über den Kartenbildern
    pin:EnableMouse(true)
    pin.ring = pin:CreateTexture(nil, "ARTWORK")
    pin.ring:SetAllPoints()
    pin.ring:SetColorTexture(0, 0, 0, 1)
    T.Round(pin.ring, pin)
    pin.dot = pin:CreateTexture(nil, "OVERLAY")
    pin.dot:SetPoint("TOPLEFT", 1.5, -1.5)
    pin.dot:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
    T.Round(pin.dot, pin)
    pin:SetScript("OnEnter", function(self)
        if not self.peer then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("|c" .. (self.color or "ffffffff") .. (ns.ShortName(self.peer.name) or self.peer.name) .. "|r")
        if self.peer.level and self.peer.level > 0 then GameTooltip:AddLine("Stufe " .. self.peer.level, 0.85, 0.85, 0.85) end
        GameTooltip:AddLine("Elternabend", 0.84, 0.69, 0.35)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", GameTooltip_Hide)
    Map.pins[i] = pin
    return pin
end

function Map:Refresh()
    for _, pin in ipairs(self.pins) do pin:Hide() end
    local frame = WorldMapFrame
    if not self:Enabled() or not frame or not frame:IsShown() or not frame.GetCanvas or not frame.GetMapID then return end
    local canvas = frame:GetCanvas()
    local mapID = frame:GetMapID()
    if not canvas or not mapID or not C_Map.GetMapPosFromWorldPos then return end
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    local scale = frame.GetCanvasScale and frame:GetCanvasScale() or 1
    local now, i = GetTime(), 0
    for key, peer in pairs(self.peers) do
        if now - peer.t > FORGET then
            self.peers[key] = nil
        elseif Map.InMyGroup(peer.name) then -- nichts zeichnen
        else
            local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, peer.continent, CreateVector2D(peer.x, peer.y), mapID)
            local x, y
            if ok and pos then
                x, y = pos.x, pos.y
                if pos.GetXY then x, y = pos:GetXY() end
            end
            if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                i = i + 1
                local pin = Pin(i, canvas)
                local col = peer.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[peer.class]
                pin.color = col and col.colorStr or "ffffffff"
                pin.dot:SetColorTexture(col and col.r or 1, col and col.g or 1, col and col.b or 1, 1)
                pin.peer = peer
                pin:SetScale(1 / math.max(0.1, scale))
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", canvas, "TOPLEFT", x * width * scale, -y * height * scale)
                pin:Show()
            end
        end
    end
end

local hooked
local function Hook()
    if hooked or not WorldMapFrame then return end
    hooked = true
    WorldMapFrame:HookScript("OnShow", function() Map:Refresh() end)
    if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() Map:Refresh() end) end
    -- Beim Öffnen und Zoomen stellt die Karte ihren Maßstab erst nach und nach ein. Damit die Punkte
    -- gleich die richtige (kleine) Größe haben und beim Zoomen mitgehen: solange die Karte offen ist,
    -- viermal pro Sekunde nachziehen.
    local watch = CreateFrame("Frame", nil, WorldMapFrame)
    watch.elapsed = 0
    watch:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed < 0.25 then return end
        self.elapsed = 0
        if Map:Enabled() and next(Map.peers) then Map:Refresh() end
    end)
end

ns:Listen("INIT", function()
    Hook()
    C_Timer.NewTicker(5, function()
        if Map:Enabled() then Map:Send() end
    end)
end)
