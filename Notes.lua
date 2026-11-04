-- Elternabend: Notizen
--
-- Beliebig viele Notizen. Jede lässt sich als eigenes kleines Fenster auf den
-- Bildschirm heften; das bleibt stehen, auch wenn das Addon-Fenster zu ist.
-- Hintergrund von deckend bis ganz durchsichtig; fixierte Notizen lassen
-- Mausklicks durch, damit sie im Kampf nicht stören.
local _, ns = ...
local T = ns.Theme

local Notes = { frames = {} }
ns.Notes = Notes

local MIN_W, MIN_H, MAX_W, MAX_H = 140, 60, 900, 900
local FONT_MIN, FONT_MAX = 10, 22

local function DB()
    return ns.db.notes
end

function Notes:All()
    return DB().list
end

function Notes:Get(id)
    for _, n in ipairs(DB().list) do
        if n.id == id then return n end
    end
end

function Notes:New()
    local d = DB()
    local n = {
        id = d.nextId, title = "Neue Notiz", text = "", created = time(),
        pinned = false, locked = false, alpha = 85, fontSize = 13, width = 260, height = 160,
    }
    d.nextId = d.nextId + 1
    table.insert(d.list, 1, n)
    ns:Fire("NOTES_UPDATE")
    return n
end

function Notes:Delete(id)
    local list = DB().list
    for i = #list, 1, -1 do
        if list[i].id == id then table.remove(list, i) end
    end
    if self.frames[id] then self.frames[id]:Hide() end
    ns:Fire("NOTES_UPDATE")
end

-- Nach jeder Änderung: Bildschirm-Notiz und Reiter auffrischen
function Notes:Changed(n)
    n.fontSize = math.max(FONT_MIN, math.min(FONT_MAX, n.fontSize or 13))
    n.alpha = math.max(0, math.min(100, n.alpha or 85))
    self:UpdateFrame(n)
    ns:Fire("NOTES_UPDATE")
end

function Notes:SetPinned(n, pinned)
    n.pinned = pinned
    self:Changed(n)
end

-- Bildschirm-Notiz ------------------------------------------------------------
local function SavePosition(f, n)
    n.left, n.top = f:GetLeft(), f:GetTop()
    n.width, n.height = f:GetWidth(), f:GetHeight()
end

function Notes:CreateFrame(n)
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self, self.note)
    end)

    f.title = T.Text(f, "kicker")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetPoint("TOPRIGHT", -28, -8)
    f.title:SetWordWrap(false)

    f.body = f:CreateFontString(nil, "OVERLAY")
    f.body:SetFontObject(T.fonts.body)
    f.body:SetPoint("TOPLEFT", 10, -24)
    f.body:SetPoint("BOTTOMRIGHT", -10, 8)
    f.body:SetJustifyH("LEFT")
    f.body:SetJustifyV("TOP")
    f.body:SetWordWrap(true)
    f.body:SetNonSpaceWrap(true)
    f.body:SetSpacing(2)

    f.close = T.Button(f, "X", 18)
    f.close:SetHeight(18)
    f.close:SetPoint("TOPRIGHT", -4, -4)
    f.close:SetScript("OnClick", function(self) Notes:SetPinned(self:GetParent().note, false) end)

    f.grip = CreateFrame("Button", nil, f)
    f.grip:SetSize(14, 14)
    f.grip:SetPoint("BOTTOMRIGHT", -2, 2)
    f.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    f.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    f.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    f.grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    f.grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        SavePosition(f, f.note)
    end)

    -- Startposition: etwas versetzt zur Bildschirmmitte, damit neue Notizen nicht übereinander liegen
    if not n.left then
        local offset = ((n.id - 1) % 6) * 24
        n.left = UIParent:GetWidth() / 2 - (n.width or 260) / 2 + offset
        n.top = UIParent:GetHeight() / 2 + 120 - offset
    end

    self.frames[n.id] = f
    return f
end

function Notes:UpdateFrame(n)
    local f = self.frames[n.id]
    if not n.pinned then
        if f then f:Hide() end
        return
    end
    f = f or self:CreateFrame(n)
    f.note = n
    local c = T.colors
    local alpha = (n.alpha or 85) / 100

    T.Backdrop(f, c.navy, alpha, 0.45 * math.min(1, alpha * 2))
    f.title:SetText((n.title or ""):upper())

    -- Je durchsichtiger, desto wichtiger ein Rand um die Schrift
    local font = T.fonts.body:GetFont()
    f.body:SetFont(font, n.fontSize or 13, alpha < 0.4 and "OUTLINE" or "")
    f.body:SetText(n.text or "")

    -- Fixiert: lässt Mausklicks durch, keine Knöpfe
    f:EnableMouse(not n.locked)
    f.close:SetShown(not n.locked)
    f.grip:SetShown(not n.locked)

    f:ClearAllPoints()
    f:SetSize(n.width or 260, n.height or 160)
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", n.left, n.top)
    f:Show()
end

-- Angeheftete Notizen nach dem Einloggen wieder auf den Bildschirm bringen
ns:On("PLAYER_LOGIN", function()
    for _, n in ipairs(Notes:All()) do
        if n.pinned then Notes:UpdateFrame(n) end
    end
end)
