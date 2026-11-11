-- Elternabend Raid: Design der Gilde (Farben und Bausteine wie auf gilde-elternabend.de)
local _, ns = ...

local T = {}
ns.Theme = T

local WHITE = "Interface\\Buttons\\WHITE8x8"
local SERIF = "Fonts\\MORPHEUS.TTF"     -- verschnörkelt: nur für den großen Titel
local DISPLAY = "Fonts\\FRIZQT__.TTF"   -- Friz Quadrata: gut lesbare Überschriften wie im Spiel
local SANS = "Fonts\\FRIZQT__.TTF"

-- Farben der Webseite (--ink, --navy, --gold, --gold-bright, --cream, --muted)
-- Die Tabellen bleiben dieselben; ein anderes Design (Skin) überschreibt nur ihre Werte.
T.colors = {
    ink        = { 0.027, 0.051, 0.102 },
    navy       = { 0.063, 0.098, 0.180 },
    panel      = { 0.055, 0.086, 0.165 },
    gold       = { 0.839, 0.694, 0.353 },
    goldBright = { 0.953, 0.863, 0.604 },
    cream      = { 0.969, 0.945, 0.902 },
    muted      = { 0.784, 0.745, 0.678 },
    skyBottom  = { 0.020, 0.035, 0.090 },
}

T.hex = {
    gold = "ffd6b15a", goldBright = "fff3dc9a", cream = "fff7f1e6", muted = "ffc8bead",
    dim = "ff7d7668", green = "ff8cd97f", red = "fff27366", orange = "ffffb35a",
}

-- Designs zum Auswählen ----------------------------------------------------
-- colors: wie T.colors (gold = Rahmen/Akzent, goldBright = Überschriften, cream = Text)
-- particles: Lichtpunkte im Kopfbereich { Anzahl, r, g, b } (Sterne, Glut …)
T.SKINS = {
    elternabend = {
        label = "Elternabend", text = "Nachtblau und Gold – unser Design",
        title = SERIF, particles = { 70, 1, 0.97, 0.88 },
        colors = {
            ink = { 0.027, 0.051, 0.102 }, navy = { 0.063, 0.098, 0.180 }, panel = { 0.055, 0.086, 0.165 },
            gold = { 0.839, 0.694, 0.353 }, goldBright = { 0.953, 0.863, 0.604 },
            cream = { 0.969, 0.945, 0.902 }, muted = { 0.784, 0.745, 0.678 }, skyBottom = { 0.020, 0.035, 0.090 },
        },
    },
    allianz = {
        label = "Allianz", text = "Königsblau und Silber",
        title = SERIF, particles = { 45, 0.85, 0.92, 1 },
        colors = {
            ink = { 0.016, 0.035, 0.086 }, navy = { 0.055, 0.118, 0.255 }, panel = { 0.043, 0.094, 0.208 },
            gold = { 0.718, 0.765, 0.839 }, goldBright = { 0.910, 0.937, 0.980 },
            cream = { 0.953, 0.961, 0.976 }, muted = { 0.663, 0.706, 0.776 }, skyBottom = { 0.016, 0.043, 0.122 },
        },
    },
    horde = {
        label = "Horde", text = "Dunkelrot und Bronze",
        title = "Fonts\\SKURRI.TTF", particles = { 55, 1, 0.55, 0.22 },
        colors = {
            ink = { 0.059, 0.020, 0.016 }, navy = { 0.165, 0.043, 0.035 }, panel = { 0.125, 0.035, 0.027 },
            gold = { 0.804, 0.510, 0.220 }, goldBright = { 0.961, 0.722, 0.420 },
            cream = { 0.965, 0.914, 0.855 }, muted = { 0.776, 0.682, 0.604 }, skyBottom = { 0.055, 0.012, 0.008 },
        },
    },
    klassisch = {
        label = "Klassisch", text = "Dunkles Leder und Blizzard-Gelb",
        title = SERIF, particles = { 0 },
        colors = {
            ink = { 0.047, 0.035, 0.024 }, navy = { 0.118, 0.090, 0.059 }, panel = { 0.090, 0.067, 0.043 },
            gold = { 0.784, 0.612, 0.271 }, goldBright = { 1, 0.820, 0 },
            cream = { 0.949, 0.922, 0.851 }, muted = { 0.733, 0.678, 0.584 }, skyBottom = { 0.059, 0.043, 0.027 },
        },
    },
}
T.SKIN_ORDER = { "elternabend", "allianz", "horde", "klassisch" }
T.skin = T.SKINS.elternabend

local function ToHex(col, factor)
    factor = factor or 1
    return string.format("ff%02x%02x%02x", math.floor(col[1] * factor * 255 + 0.5),
        math.floor(col[2] * factor * 255 + 0.5), math.floor(col[3] * factor * 255 + 0.5))
end
T.ToHex = ToHex

function T.Hex(key, text)
    return "|c" .. (T.hex[key] or key) .. tostring(text) .. "|r"
end

local function Color(c, a)
    return c[1], c[2], c[3], a or 1
end

-- Schriften: Überschriften in Serifen, Text schlicht ---------------------
local function Font(name, path, size, color, shadow)
    local f = CreateFont(name)
    f:SetFont(path, size, "")
    f:SetTextColor(Color(color))
    if shadow ~= false then
        f:SetShadowColor(0, 0, 0, 0.8)
        f:SetShadowOffset(1, -1)
    end
    return f
end

local c = T.colors
T.fonts = {
    title       = Font("ElternabendFontTitle", SERIF, 32, c.goldBright),
    heading     = Font("ElternabendFontHeading", DISPLAY, 16, c.goldBright),
    value       = Font("ElternabendFontValue", DISPLAY, 15, c.goldBright),
    kicker      = Font("ElternabendFontKicker", SANS, 9, c.gold),
    body        = Font("ElternabendFontBody", SANS, 12, c.cream),
    small       = Font("ElternabendFontSmall", SANS, 11, c.cream),
    muted       = Font("ElternabendFontMuted", SANS, 11, c.muted),
    nav         = Font("ElternabendFontNav", SANS, 13, c.cream),
    navActive   = Font("ElternabendFontNavActive", SANS, 13, c.goldBright),
    btnDark     = Font("ElternabendFontBtnDark", SANS, 12, c.ink, false),
    btnLight    = Font("ElternabendFontBtnLight", SANS, 12, c.cream),
    btnDisabled = Font("ElternabendFontBtnDisabled", SANS, 12, { 0.5, 0.48, 0.44 }),
}
-- Schrift -> Farbname, damit ein Design die Farben austauschen kann
local FONT_COLOR = {
    title = "goldBright", heading = "goldBright", value = "goldBright", kicker = "gold", body = "cream",
    small = "cream", muted = "muted", nav = "cream", navActive = "goldBright", btnDark = "ink", btnLight = "cream",
}

-- Design anwenden: Werte der Farbtabellen überschreiben (alle Bausteine lesen sie beim
-- Erzeugen), Schriftfarben und Chat-Farbcodes anpassen. Wirkt auf alles, was danach
-- entsteht – deshalb beim Laden vor dem ersten Öffnen des Fensters, sonst neu laden.
function T.ApplySkin(key)
    local skin = T.SKINS[key] or T.SKINS.elternabend
    T.skin = skin
    for name, col in pairs(skin.colors) do
        local target = T.colors[name]
        target[1], target[2], target[3] = col[1], col[2], col[3]
    end
    T.hex.gold = ToHex(c.gold)
    T.hex.goldBright = ToHex(c.goldBright)
    T.hex.cream = ToHex(c.cream)
    T.hex.muted = ToHex(c.muted)
    T.hex.dim = ToHex(c.muted, 0.62)
    for name, colorName in pairs(FONT_COLOR) do
        T.fonts[name]:SetTextColor(Color(c[colorName]))
    end
    T.fonts.title:SetFont(skin.title or SERIF, 32, "")
end

-- Bausteine --------------------------------------------------------------
function T.Text(parent, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(T.fonts[font or "body"])
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

function T.Backdrop(frame, bg, alpha, borderAlpha)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(Color(bg or c.panel, alpha or 0.92))
    frame:SetBackdropBorderColor(Color(c.gold, borderAlpha or 0.45))
end

-- Dunkle Karte mit goldenem Rand (wie die Kacheln „Fraktion“, „Spiel“, …)
function T.Panel(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    T.Backdrop(f)
    return f
end

-- Goldene Linie, die zu den Rändern hin ausläuft
function T.GoldLine(parent, alpha)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(1)
    local left = f:CreateTexture(nil, "ARTWORK")
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMRIGHT", f, "BOTTOM")
    left:SetColorTexture(1, 1, 1, 1)
    left:SetGradient("HORIZONTAL", CreateColor(Color(c.gold, 0)), CreateColor(Color(c.gold, alpha or 0.9)))
    local right = f:CreateTexture(nil, "ARTWORK")
    right:SetPoint("TOPLEFT", f, "TOP")
    right:SetPoint("BOTTOMRIGHT")
    right:SetColorTexture(1, 1, 1, 1)
    right:SetGradient("HORIZONTAL", CreateColor(Color(c.gold, alpha or 0.9)), CreateColor(Color(c.gold, 0)))
    return f
end

-- Knöpfe: "primary" = goldene Fläche (wie „Discord beitreten“), sonst goldener Rahmen
function T.Button(parent, text, width, style)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 130, 26)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    if style == "primary" then
        b:SetBackdropColor(Color(c.gold))
        b:SetBackdropBorderColor(Color(c.goldBright, 0.9))
        local fill = b:CreateTexture(nil, "BORDER")
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", -1, 1)
        fill:SetColorTexture(1, 1, 1, 1)
        fill:SetGradient("VERTICAL", CreateColor(Color(c.gold)), CreateColor(Color(c.goldBright)))
        b:SetNormalFontObject(T.fonts.btnDark)
    else
        b:SetBackdropColor(Color(c.ink, 0.35))
        b:SetBackdropBorderColor(Color(c.gold, 0.85))
        b:SetNormalFontObject(T.fonts.btnLight)
    end
    b:SetDisabledFontObject(T.fonts.btnDisabled)
    b:SetText(text)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(1, 1, 1, 0.12)
    b:SetScript("OnDisable", function(self) self:SetAlpha(0.45) end)
    b:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    return b
end

-- Reiter in der Kopfzeile: aktiver Reiter golden und unterstrichen
function T.NavButton(parent, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetNormalFontObject(T.fonts.nav)
    b:SetHighlightFontObject(T.fonts.navActive)
    b:SetText(text)
    b:SetSize(b:GetFontString():GetStringWidth() + 18, 30)
    b.underline = b:CreateTexture(nil, "ARTWORK")
    b.underline:SetHeight(2)
    b.underline:SetPoint("BOTTOMLEFT", 10, 3)
    b.underline:SetPoint("BOTTOMRIGHT", -10, 3)
    b.underline:SetColorTexture(Color(c.gold))
    b.underline:Hide()
    function b:SetActive(active)
        self:SetNormalFontObject(active and T.fonts.navActive or T.fonts.nav)
        self.underline:SetShown(active)
    end
    return b
end

-- Kachel mit Überschrift, Wert und Unterzeile
function T.Card(parent, kicker)
    local f = T.Panel(parent)
    f.kicker = T.Text(f, "kicker", "CENTER")
    f.kicker:SetPoint("TOP", 0, -10)
    f.kicker:SetText(kicker:upper())
    f.value = T.Text(f, "value", "CENTER")
    f.value:SetPoint("TOPLEFT", 8, -24)
    f.value:SetPoint("TOPRIGHT", -8, -24)
    f.value:SetWordWrap(false)
    f.sub = T.Text(f, "muted", "CENTER")
    f.sub:SetPoint("TOPLEFT", 8, -46)
    f.sub:SetPoint("TOPRIGHT", -8, -46)
    f.sub:SetWordWrap(false)
    return f
end

function T.EditBox(parent, width, placeholder)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetSize(width or 140, 26)
    T.Backdrop(eb, c.ink, 0.9, 0.6)
    eb:SetFontObject(T.fonts.body)
    eb:SetTextInsets(8, 8, 0, 0)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnEnterPressed", eb.ClearFocus)
    if placeholder then
        local ph = T.Text(eb, "muted")
        ph:SetPoint("LEFT", 8, 0)
        ph:SetText(placeholder)
        local function Update() ph:SetShown(eb:GetText() == "" and not eb:HasFocus()) end
        eb:HookScript("OnTextChanged", Update)
        eb:HookScript("OnEditFocusGained", Update)
        eb:HookScript("OnEditFocusLost", Update)
    end
    return eb
end

-- Häkchen mit Beschriftung; onChange(checked) wird beim Klick aufgerufen
function T.Checkbox(parent, label)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(18)
    b.box = CreateFrame("Frame", nil, b, "BackdropTemplate")
    b.box:SetSize(14, 14)
    b.box:SetPoint("LEFT")
    T.Backdrop(b.box, c.ink, 0.9, 0.8)
    b.mark = b.box:CreateTexture(nil, "OVERLAY")
    b.mark:SetPoint("TOPLEFT", 3, -3)
    b.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    b.mark:SetColorTexture(Color(c.goldBright))
    b.text = T.Text(b, "small")
    b.text:SetPoint("LEFT", b.box, "RIGHT", 8, 0)
    b.text:SetText(label)
    b:SetWidth(b.text:GetStringWidth() + 24)
    function b:SetChecked(checked)
        self.checked = checked and true or false
        self.mark:SetShown(self.checked)
    end
    function b:GetChecked() return self.checked end
    b:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if self.onChange then self.onChange(self.checked) end
    end)
    return b
end

-- Kleines „X“ rechts im Feld, das den Text löscht (für Suchfelder)
function T.AddClearButton(eb)
    eb:SetTextInsets(8, 26, 0, 0)
    local b = CreateFrame("Button", nil, eb)
    b:SetSize(22, 22)
    b:SetPoint("RIGHT", -2, 0)
    b.text = T.Text(b, "muted")
    b.text:SetPoint("CENTER")
    b.text:SetText("X")
    b:SetScript("OnEnter", function(self)
        self.text:SetTextColor(Color(c.goldBright))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Suche löschen")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.text:SetTextColor(Color(c.muted))
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function()
        eb:SetText("")
        eb:ClearFocus()
    end)
    b:Hide()
    eb:HookScript("OnTextChanged", function() b:SetShown(eb:GetText() ~= "") end)
    return b
end

-- Schieberegler: goldener Griff auf dunkler Leiste
function T.Slider(parent, width, minValue, maxValue, step)
    local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width or 160, 12)
    T.Backdrop(s, c.ink, 0.9, 0.6)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 18)
    thumb:SetColorTexture(Color(c.goldBright))
    s:SetThumbTexture(thumb)
    s:SetMinMaxValues(minValue or 0, maxValue or 100)
    s:SetValueStep(step or 1)
    s:SetObeyStepOnDrag(true)
    return s
end

-- Scrollbereich mit Mausrad und schmaler goldener Leiste
function T.Scroll(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)
    sf.content = content

    local thumb = sf:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(Color(c.gold, 0.7))

    local function UpdateThumb()
        local range, height = sf:GetVerticalScrollRange(), sf:GetHeight()
        if range <= 0 or height <= 0 then
            thumb:Hide()
            return
        end
        local size = math.max(20, height * height / (height + range))
        thumb:SetHeight(size)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, -(sf:GetVerticalScroll() / range) * (height - size))
        thumb:Show()
    end
    sf.UpdateThumb = UpdateThumb

    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 44)))
        UpdateThumb()
    end)
    sf:SetScript("OnScrollRangeChanged", function(self)
        if self:GetVerticalScroll() > self:GetVerticalScrollRange() then
            self:SetVerticalScroll(self:GetVerticalScrollRange())
        end
        UpdateThumb()
    end)
    sf:SetScript("OnSizeChanged", function(_, w)
        content:SetWidth(math.max(1, w - 10))
        UpdateThumb()
    end)
    return sf
end

-- Sterne für den Nachthimmel im Kopfbereich (Farbe und Anzahl je nach Design)
function T.Stars(frame, count)
    local p = T.skin.particles or { count }
    count = p[1] or count
    for _ = 1, count do
        local s = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
        local size = math.random() < 0.85 and 1 or 2
        s:SetSize(size, size)
        s:SetColorTexture(p[2] or 1, p[3] or 0.97, p[4] or 0.88, 0.25 + math.random() * 0.6)
        s:SetPoint("TOPLEFT", math.random(4, 900), -math.random(2, 90))
    end
end

-- Runde Maske (für das Wappen)
-- Zähler-Plakette (roter Punkt mit Zahl), z. B. oben rechts an einem Reiter
function T.Badge(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(17, 17)
    f:SetFrameLevel(parent:GetFrameLevel() + 6)
    local ring = f:CreateTexture(nil, "BACKGROUND")
    ring:SetAllPoints()
    ring:SetColorTexture(Color(c.gold))
    T.Round(ring, f)
    local dot = f:CreateTexture(nil, "ARTWORK")
    dot:SetPoint("TOPLEFT", 1.5, -1.5)
    dot:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
    dot:SetColorTexture(0.72, 0.13, 0.10, 1)
    T.Round(dot, f)
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    f.text:SetPoint("CENTER", 0.5, 0)
    f.text:SetTextColor(1, 1, 1)
    function f:SetCount(n)
        n = tonumber(n) or 0
        self:SetShown(n > 0)
        if n <= 0 then return end
        self.text:SetText(n > 9 and "9+" or tostring(n))
        self:SetWidth(n > 9 and 22 or 17)
    end
    f:Hide()
    return f
end

function T.Round(texture, parent)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
end

-- Gewähltes Design laden, bevor irgendein Fenster entsteht
ns:Listen("INIT", function()
    if ns.db.skin and ns.db.skin ~= "elternabend" then T.ApplySkin(ns.db.skin) end
end)
