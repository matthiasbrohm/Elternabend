-- Elternabend Raid: Oberfläche (Hauptfenster mit Reitern, Textdialog, Minimap-Button)
local _, ns = ...
local T = ns.Theme

local UI = { panels = {}, tabs = {}, subTabs = {} }
ns.UI = UI

local ROW_H = 22
local TABS = {
    { key = "start", label = "Start" },
    { key = "mitglieder", label = "Gilde" },
    { key = "berufe", label = "Berufe" },
    { key = "gruppen", label = "Gruppen" },
    { key = "notizen", label = "Notizen" },
    { key = "raid", label = "Raid" },
    { key = "gilde", label = "Invite", invite = true },
    { key = "web", label = "Webseite", leaders = true },
}
-- Unterreiter von „Raid“: eigene Leiste unter der Kopfzeile
local RAID_TABS = {
    { key = "raid", label = "Übersicht" },
    { key = "sr", label = "Soft-Reserve" },
    { key = "loot", label = "Plündermeister" },
    { key = "history", label = "Loot" },
    { key = "taktik", label = "Taktik" },
    { key = "fame", label = "Ruhmeshalle" },
}
local IN_RAID_GROUP = { raid = true, sr = true, loot = true, history = true, taktik = true, fame = true }
local PANEL_TOP, SUBNAV_H = 116, 30

local LOOT_METHODS = {
    master = "Plündermeister", group = "Als Gruppe", freeforall = "Jeder gegen jeden",
    roundrobin = "Reihum", needbeforegreed = "Bedarf vor Gier", personal = "Persönlich",
}

local ROLE_NAMES = { tank = "Tank", heal = "Heiler", dd = "DD" }

local SIGNUP_STATES = {
    ok = { "Dabei", "green" },
    bench = { "Ersatzbank", "orange" },
    declined = { "Abgemeldet", "red" },
    unplanned = { "Nicht angemeldet", "muted" },
    missing = { "Fehlt noch", "red" },
    benchMissing = { "Ersatzbank", "dim" },
    maybe = { "Vielleicht", "orange" },
    maybeMissing = { "Vielleicht", "dim" },
}

-- Klassennamen aus dem Raidplaner (deutsch oder englisch) für die Klassenfarbe
local CLASS_FILES = {
    krieger = "WARRIOR", warrior = "WARRIOR", paladin = "PALADIN", ["jäger"] = "HUNTER", hunter = "HUNTER",
    schurke = "ROGUE", rogue = "ROGUE", priester = "PRIEST", priest = "PRIEST", schamane = "SHAMAN",
    shaman = "SHAMAN", magier = "MAGE", mage = "MAGE", hexenmeister = "WARLOCK", warlock = "WARLOCK",
    druide = "DRUID", druid = "DRUID",
}

-- Hilfsfunktionen ----------------------------------------------------------
local function ClassHex(classFile)
    local color = classFile and RAID_CLASS_COLORS[classFile]
    return color and color.colorStr or T.hex.cream
end

local function ClassFileFromName(name)
    return name and CLASS_FILES[ns.Lower(strtrim(name))]
end

local function ItemInfo(itemId)
    local name, link, quality, _, _, _, _, _, _, icon = ns.GetItemInfo(itemId)
    return name, link, quality, icon or ns.GetItemIcon(itemId)
end

local function ItemLabel(itemId, fallbackName)
    local name, link = ItemInfo(itemId)
    return link or ("[" .. (fallbackName or name or ("Item " .. itemId)) .. "]")
end

local function ShowItemTooltip(owner, itemId, link)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(link or ("item:" .. itemId))
    GameTooltip:Show()
end

-- Liste mit Spalten in einer dunklen Karte
local function CreateList(parent, columns, setup)
    local panel = T.Panel(parent)
    for _, col in ipairs(columns) do
        if col.label then
            local fs = T.Text(panel, "kicker")
            fs:SetPoint("TOPLEFT", col.x + 8, -9)
            fs:SetText(col.label:upper())
        end
    end
    local line = T.GoldLine(panel, 0.5)
    line:SetPoint("TOPLEFT", 8, -24)
    line:SetPoint("TOPRIGHT", -8, -24)

    local sf = T.Scroll(panel)
    sf:SetPoint("TOPLEFT", 8, -28)
    sf:SetPoint("BOTTOMRIGHT", -6, 6)
    local content = sf.content

    local list = { panel = panel, rows = {} }

    local function NewRow(i)
        local row = CreateFrame("Button", nil, content)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", content, "RIGHT")
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(T.colors.gold[1], T.colors.gold[2], T.colors.gold[3], 0.10)
        if i % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0.025)
        end
        row.cols = {}
        for _, col in ipairs(columns) do
            if col.icon then
                local t = row:CreateTexture(nil, "ARTWORK")
                t:SetSize(ROW_H - 4, ROW_H - 4)
                t:SetPoint("LEFT", col.x, 0)
                row.cols[col.key] = t
            else
                local fs = T.Text(row, "small")
                fs:SetPoint("LEFT", col.x, 0)
                if col.w then fs:SetWidth(col.w) else fs:SetPoint("RIGHT", col.right or -4, 0) end
                fs:SetHeight(ROW_H)
                fs:SetWordWrap(false)
                row.cols[col.key] = fs
            end
        end
        row:SetScript("OnEnter", function(self)
            if list.onEnter and self.data then list.onEnter(self, self.data) end
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnClick", function(self, button)
            if list.onClick and self.data then list.onClick(self, self.data, button) end
        end)
        if setup then setup(row) end
        return row
    end

    function list:SetData(data, update)
        for i, d in ipairs(data) do
            local row = self.rows[i] or NewRow(i)
            self.rows[i] = row
            row.data = d
            update(row, d, i)
            row:Show()
        end
        for i = #data + 1, #self.rows do
            self.rows[i]:Hide()
            self.rows[i].data = nil
        end
        content:SetHeight(math.max(1, #data * ROW_H))
        sf.UpdateThumb()
    end

    return list
end

-- Knöpfe nebeneinander anordnen
local function Row(parent, x, y, buttons)
    local prev
    for _, b in ipairs(buttons) do
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 8, 0) else b:SetPoint("TOPLEFT", x, y) end
        prev = b
    end
end

-- Hauptfenster ---------------------------------------------------------------
-- Fensterbreite; Inhalt = Breite minus 2 × 18 Rand
local WIN_W = 1120
local CONTENT_W = WIN_W - 36

function UI:Create()
    if self.frame then return end
    local c = T.colors

    local f = CreateFrame("Frame", "ElternabendFrame", UIParent, "BackdropTemplate")
    f:SetSize(WIN_W, 600 + SUBNAV_H)
    -- Auf kleinen Bildschirmen passend verkleinern
    local screenW = UIParent:GetWidth()
    if screenW and screenW > 0 and screenW < WIN_W + 40 then f:SetScale((screenW - 40) / WIN_W) end
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    T.Backdrop(f, c.navy, 0.97, 0.6)
    f:Hide()
    tinsert(UISpecialFrames, "ElternabendFrame")

    -- Kopfbereich: Nachthimmel, Wappen, Gildenname, Reiter
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(100)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local sky = header:CreateTexture(nil, "BACKGROUND")
    sky:SetAllPoints()
    sky:SetColorTexture(1, 1, 1, 1)
    sky:SetGradient("VERTICAL", CreateColor(c.navy[1], c.navy[2], c.navy[3], 1), CreateColor(0.02, 0.035, 0.09, 1))
    T.Stars(header, 70)

    -- Gildenwappen; der goldene Ring ist schon im Bild
    local ring = header:CreateTexture(nil, "ARTWORK")
    ring:SetSize(70, 70)
    ring:SetPoint("LEFT", 16, 4)
    ring:SetTexture(ns.LOGO)

    local kicker = T.Text(header, "kicker")
    kicker:SetPoint("TOPLEFT", ring, "TOPRIGHT", 16, -4)
    kicker:SetText("ALLIANZ · PVE · WOW FOREVER")
    local title = T.Text(header, "title")
    title:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -4)
    title:SetText("Elternabend")

    local close = T.Button(header, "X", 26)
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetScript("OnClick", function() f:Hide() end)

    for _, tab in ipairs(TABS) do
        local b = T.NavButton(header, tab.label)
        -- „Raid“ öffnet den zuletzt benutzten Unterreiter
        b:SetScript("OnClick", function() UI:Show(tab.key == "raid" and UI.lastRaidTab or tab.key) end)
        self.tabs[tab.key] = b
    end
    self.header = header

    local line = T.GoldLine(f, 0.9)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    line:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")

    -- Unterreiter für den Raid: Übersicht, Soft-Reserve, Plündermeister, Taktik
    local subnav = CreateFrame("Frame", nil, f)
    subnav:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 8, -4)
    subnav:SetPoint("TOPRIGHT", line, "BOTTOMRIGHT", -8, -4)
    subnav:SetHeight(SUBNAV_H)
    for _, tab in ipairs(RAID_TABS) do
        local b = T.NavButton(subnav, tab.label)
        b:SetScript("OnClick", function() UI:Show(tab.key) end)
        self.subTabs[tab.key] = b
    end
    local subline = T.GoldLine(subnav, 0.35)
    subline:SetPoint("BOTTOMLEFT", 10, -2)
    subline:SetPoint("BOTTOMRIGHT", -10, -2)
    subnav:Hide()
    self.subnav = subnav

    -- Fußzeile mit dem Motto der Gilde
    local quote = T.Text(f, "muted")
    quote:SetPoint("BOTTOMLEFT", 18, 12)
    quote:SetText("„Die Kinder schlafen. Die Helden erwachen.“")
    local site = T.Text(f, "kicker", "RIGHT")
    site:SetPoint("BOTTOMRIGHT", -18, 13)
    site:SetText(ns.WEBSITE:upper() .. "  ·  " .. ns.VERSION)

    self.frame = f
    self.panels.start = self:CreateStartPanel()
    self.panels.raid = self:CreateRaidPanel()
    self.panels.sr = self:CreateSRPanel()
    self.panels.loot = self:CreateLootPanel()
    self.panels.taktik = self:CreateTacticPanel()
    self.panels.gruppen = self:CreateGroupsPanel()
    self.panels.gilde = self:CreateGuildPanel()
    self.panels.mitglieder = self:CreateMembersPanel()
    self.panels.berufe = self:CreateProfessionsPanel()
    self.panels.notizen = self:CreateNotesPanel()
    self.panels.history = self:CreateHistoryPanel()
    self.panels.fame = self:CreateFamePanel()
    self.panels.web = self:CreateWebPanel()
    -- Die Raid-Reiter beginnen unter der Unterleiste
    for key in pairs(IN_RAID_GROUP) do
        local p = self.panels[key]
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", 18, -(PANEL_TOP + SUBNAV_H))
        p:SetPoint("BOTTOMRIGHT", -18, 36)
    end

    f:SetScript("OnShow", function() UI:Refresh() end)
end

function UI:NewPanel()
    local p = CreateFrame("Frame", nil, self.frame)
    p:SetPoint("TOPLEFT", 18, -PANEL_TOP)
    p:SetPoint("BOTTOMRIGHT", -18, 36)
    p:Hide()
    return p
end

-- Den Plündermeister-Reiter brauchen Plündermeister, Raidleitung und Assistenten,
-- Offiziere und Gildenleitung (immer, z. B. für Rückfragen) – und wer gerade Beute vergibt
function UI:LootTabVisible()
    return self.currentTab == "loot" or ns.IsMasterLooter() or ns.IsTrusted(ns.UnitFullName("player"))
        or self:IsLeader() or ns.Loot.current ~= nil or #ns.Loot.items > 0
end

-- Offiziere und Gildenleitung: dürfen Offiziersnotizen lesen oder haben einen der
-- obersten drei Ränge (Gildenmeister, Gildenleitung, Offizier)
function UI:IsLeader()
    if not IsInGuild() then return false end
    if ns.Members:CanView() then return true end
    local _, _, rankIndex = GetGuildInfo("player")
    return type(rankIndex) == "number" and rankIndex <= 2
end

-- Wer darf einen Reiter sehen? „Invite“ nur, wer in die Gilde einladen darf;
-- „Webseite“ nur Offiziere und Gildenleitung
local TAB_BY_KEY = {}
for _, tab in ipairs(TABS) do TAB_BY_KEY[tab.key] = tab end

function UI:CanSee(key)
    local tab = TAB_BY_KEY[key]
    if not tab then return true end
    if tab.invite then return IsInGuild() and CanGuildInvite() and true or false end
    if tab.leaders then return self:IsLeader() end
    return true
end

-- Reiter von rechts nach links anordnen; Unterreiter von links, ausgeblendete überspringen
function UI:LayoutTabs()
    local prev
    for i = #TABS, 1, -1 do
        local tab = TABS[i]
        local b = self.tabs[tab.key]
        local visible = self:CanSee(tab.key)
        b:SetShown(visible)
        b:ClearAllPoints()
        if visible then
            if prev then b:SetPoint("RIGHT", prev, "LEFT", 0, 0) else b:SetPoint("BOTTOMRIGHT", self.header, "BOTTOMRIGHT", -12, 2) end
            prev = b
        end
    end
    prev = nil
    for _, tab in ipairs(RAID_TABS) do
        local b = self.subTabs[tab.key]
        local visible = tab.key ~= "loot" or self:LootTabVisible()
        b:SetShown(visible)
        b:ClearAllPoints()
        if visible then
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 0, 0) else b:SetPoint("LEFT", self.subnav, "LEFT", 0, 0) end
            prev = b
        end
    end
end

function UI:Show(key)
    self:Create()
    if key and not self:CanSee(key) then
        ns.Print(key == "gilde" and "Den Reiter „Invite“ sieht nur, wer in die Gilde einladen darf."
            or "Der Reiter „Webseite“ ist nur für Offiziere und Gildenleitung.")
        key = nil
    end
    self.currentTab = key or self.currentTab or "start"
    local inRaid = IN_RAID_GROUP[self.currentTab] or false
    if inRaid then self.lastRaidTab = self.currentTab end
    self:LayoutTabs()
    for k, panel in pairs(self.panels) do panel:SetShown(k == self.currentTab) end
    for k, b in pairs(self.tabs) do b:SetActive(k == self.currentTab or (k == "raid" and inRaid)) end
    for k, b in pairs(self.subTabs) do b:SetActive(k == self.currentTab) end
    self.subnav:SetShown(inRaid)
    self.frame:Show()
    self:Refresh()
end

function UI:ShowFame()
    self:Show("fame")
end

function UI:Toggle()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Show()
    end
end

function UI:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    self:LayoutTabs()
    local panel = self.panels[self.currentTab]
    if panel then panel:Refresh() end
end

-- Mehrere Events kurz hintereinander nur einmal neu zeichnen
function UI:QueueRefresh()
    if self.refreshQueued then return end
    self.refreshQueued = true
    C_Timer.After(0.1, function()
        UI.refreshQueued = false
        UI:Refresh()
    end)
end

for _, msg in ipairs({ "ROSTER_UPDATE", "SR_UPDATE", "LOOT_UPDATE", "ROLL_UPDATE", "HISTORY_UPDATE", "SESSION_UPDATE", "NOTES_UPDATE", "INFO_UPDATE", "MEMBERS_UPDATE", "JOIN_UPDATE", "PROF_UPDATE",
    "GROUPS_UPDATE", "ORDERS_UPDATE", "FAME_UPDATE", "READY_UPDATE" }) do
    ns:Listen(msg, function() UI:QueueRefresh() end)
end
ns:On("GET_ITEM_INFO_RECEIVED", function() UI:QueueRefresh() end)

-- Reiter: Start (Begrüßung, Gildeninfos, was das Addon kann) -----------------
-- Link zum Kopieren: WoW kann keine Webseiten öffnen, also markieren und Strg+C
local function LinkBox(parent, url, width)
    local eb = T.EditBox(parent, width)
    eb:SetText(url)
    eb:SetCursorPosition(0)
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    eb:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(url)
            self:HighlightText()
        end
    end)
    return eb
end

local function StartCard(parent, kicker, height)
    local card = T.Panel(parent)
    card:SetHeight(height)
    local k = T.Text(card, "kicker")
    k:SetPoint("TOPLEFT", 16, -12)
    k:SetText(kicker:upper())
    card.kicker = k
    return card
end

function UI:CreateStartPanel()
    local p = self:NewPanel()
    local G = ns.Info.GUILD
    local leftWidth = 440

    -- Willkommen
    local welcome = StartCard(p, "Willkommen bei " .. G.name, 140)
    welcome:SetPoint("TOPLEFT")
    welcome:SetWidth(leftWidth)
    p.hello = T.Text(welcome, "heading")
    p.hello:SetPoint("TOPLEFT", welcome.kicker, "BOTTOMLEFT", 0, -4)
    local about = T.Text(welcome, "small")
    about:SetPoint("TOPLEFT", p.hello, "BOTTOMLEFT", 0, -8)
    about:SetWidth(leftWidth - 32)
    about:SetSpacing(3)
    about:SetText(G.about)
    local motto = T.Text(welcome, "muted")
    motto:SetPoint("BOTTOMLEFT", 16, 12)
    motto:SetText(G.motto)

    -- Nachricht des Tages (live aus dem Spiel)
    local motd = StartCard(p, "Nachricht des Tages", 74)
    motd:SetPoint("TOPLEFT", welcome, "BOTTOMLEFT", 0, -10)
    motd:SetWidth(leftWidth)
    p.motd = T.Text(motd, "body")
    p.motd:SetPoint("TOPLEFT", motd.kicker, "BOTTOMLEFT", 0, -6)
    p.motd:SetWidth(leftWidth - 32)
    p.motd:SetHeight(40)
    p.motd:SetJustifyV("TOP")
    p.motd:SetSpacing(2)
    p.motdCard = motd
    -- Noch nicht in der Gilde: ein Klick schickt die Beitrittsanfrage an alle Einladenden
    p.joinBtn = T.Button(motd, "Der Gilde beitreten", 170, "primary")
    p.joinBtn:SetPoint("RIGHT", -16, -6)
    p.joinBtn:SetScript("OnClick", function() ns.Join:Click() end)
    -- Notlösung zum Kopieren, falls gerade niemand erreichbar ist: „/w Name ginv“
    p.joinCopy = T.EditBox(motd, leftWidth - 32 - 186)
    p.joinCopy:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    p.joinCopy:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    p.joinCopy:HookScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(self.value or "")
            self:HighlightText()
        end
    end)
    p.joinCopy:SetPoint("BOTTOMLEFT", 16, 10)
    p.joinCopy:Hide()

    -- Raidzeiten
    local raid = StartCard(p, "Raidzeiten", 66)
    raid:SetPoint("TOPLEFT", motd, "BOTTOMLEFT", 0, -10)
    raid:SetWidth(leftWidth)
    local times = T.Text(raid, "body")
    times:SetPoint("TOPLEFT", raid.kicker, "BOTTOMLEFT", 0, -6)
    times:SetWidth(leftWidth - 32)
    times:SetText(T.Hex("goldBright", G.raidTimes))
    p.nextRaid = T.Text(raid, "muted")
    p.nextRaid:SetPoint("TOPLEFT", times, "BOTTOMLEFT", 0, -4)
    p.nextRaid:SetWidth(leftWidth - 32)
    p.nextRaid:SetWordWrap(false)

    -- Discord und Webseite
    local links = StartCard(p, "Discord & Webseite", 0)
    links:SetPoint("TOPLEFT", raid, "BOTTOMLEFT", 0, -10)
    links:SetPoint("BOTTOMLEFT")
    links:SetWidth(leftWidth)
    local discordLabel = T.Text(links, "small")
    discordLabel:SetPoint("TOPLEFT", 16, -32)
    discordLabel:SetWidth(80)
    discordLabel:SetText("Discord")
    local discord = LinkBox(links, G.discord, leftWidth - 128)
    discord:SetPoint("LEFT", discordLabel, "RIGHT", 8, 0)
    local siteLabel = T.Text(links, "small")
    siteLabel:SetPoint("TOPLEFT", discordLabel, "BOTTOMLEFT", 0, -20)
    siteLabel:SetWidth(80)
    siteLabel:SetText("Webseite")
    local site = LinkBox(links, G.website, leftWidth - 128)
    site:SetPoint("LEFT", siteLabel, "RIGHT", 8, 0)
    local copyHint = T.Text(links, "muted")
    copyHint:SetPoint("TOPLEFT", siteLabel, "BOTTOMLEFT", 0, -16)
    copyHint:SetText("Ins Feld klicken und mit Strg+C kopieren.")

    -- Rechts: Was gerade los ist – mit Sprung in den passenden Reiter
    local now = StartCard(p, "Aktuell", 0)
    now:SetPoint("TOPLEFT", welcome, "TOPRIGHT", 12, 0)
    now:SetPoint("BOTTOMRIGHT")
    local NOW_ROWS = {
        { key = "online", title = "Gilde", button = "Öffnen", tab = "mitglieder" },
        { key = "orders", title = "Aufträge", button = "Öffnen", tab = "berufe" },
        { key = "groups", title = "Gruppen", button = "Öffnen", tab = "gruppen" },
        { key = "fame", title = "Ruhmeshalle", button = "Öffnen", tab = "fame" },
        { key = "away", title = "Elternknopf", button = "An/Aus" },
    }
    local rowHeight = 46
    p.now = {}
    for i, r in ipairs(NOW_ROWS) do
        local row = CreateFrame("Frame", nil, now)
        row:SetPoint("TOPLEFT", 16, -30 - (i - 1) * rowHeight)
        row:SetPoint("TOPRIGHT", -16, -30 - (i - 1) * rowHeight)
        row:SetHeight(rowHeight)
        local title = T.Text(row, "body")
        title:SetPoint("TOPLEFT", 0, -6)
        title:SetText(T.Hex("goldBright", r.title))
        -- Kurze Zusatzinfo neben der Überschrift (z. B. Anzahl der Gesuche)
        row.extra = T.Text(row, "muted")
        row.extra:SetPoint("LEFT", title, "RIGHT", 10, 0)
        row.text = T.Text(row, "muted")
        row.text:SetPoint("TOPLEFT", 0, -24)
        row.text:SetPoint("TOPRIGHT", -94, -24)
        row.text:SetWordWrap(false)
        local open = T.Button(row, r.button, 86)
        open:SetHeight(22)
        open:SetPoint("RIGHT", 0, 0)
        open:SetScript("OnClick", function()
            if r.key == "away" then
                ns.db.away.showButton = not ns.db.away.showButton
                ns.Print("Elternknopf: " .. (ns.db.away.showButton and "an – er erscheint, sobald du in einer Gruppe bist" or "aus"))
                ns.Away:UpdateButton()
                p:Refresh()
            else
                UI:Show(r.tab)
            end
        end)
        if i > 1 then
            local line = row:CreateTexture(nil, "ARTWORK")
            line:SetHeight(1)
            line:SetPoint("TOPLEFT")
            line:SetPoint("TOPRIGHT")
            line:SetColorTexture(T.colors.gold[1], T.colors.gold[2], T.colors.gold[3], 0.15)
        end
        p.now[r.key] = row
    end

    function p:RefreshNow()
        -- Gesuche der anderen, neuestes zuerst (die Liste ist schon so sortiert)
        local others = {}
        for _, g in ipairs(ns.Groups:List()) do
            if g ~= ns.Groups.mine then table.insert(others, g) end
        end
        local function Cut(text, max)
            if #text <= max then return text end
            -- nicht mitten in einem Umlaut abschneiden
            return (text:sub(1, max):gsub("[\192-\255][\128-\191]*$", "")) .. "…"
        end
        local m = ns.Groups.mine
        local row = p.now.groups
        if m then
            -- Eigenes Gesuch: wofür, wer noch fehlt, neue Meldungen; daneben die Gesuche der anderen
            local new = 0
            for _, ap in ipairs(ns.Groups:Applicants()) do
                if ap.state == "new" then new = new + 1 end
            end
            -- Neben der Überschrift: neue Meldungen und Gesuche der anderen (dort ist Platz)
            local extra = {}
            if new > 0 then table.insert(extra, T.Hex("goldBright", new == 1 and "1 neue Meldung" or (new .. " neue Meldungen"))) end
            if #others > 0 then table.insert(extra, #others == 1 and "+1 weiteres Gesuch" or ("+" .. #others .. " weitere Gesuche")) end
            row.extra:SetText(table.concat(extra, "  ·  "))
            row.text:SetText(T.Hex("green", "Dein Gesuch: " .. Cut(m.what, 22)) .. "  ·  " .. ns.Groups.NeedText(m.need))
        elseif #others > 0 then
            local g = others[1]
            local name = ns.ShortName(g.leader) or "?"
            name = name:match("^(%S+)") or name
            row.extra:SetText(#others > 1 and (#others .. " offene Gesuche") or "")
            row.text:SetText(T.Hex("cream", name .. ": " .. Cut(g.what, 22)) .. "  ·  " .. ns.Groups.NeedText(g.need))
        else
            row.extra:SetText("")
            row.text:SetText("Gerade sucht niemand eine Gruppe.")
        end

        local orders = ns.Orders:OpenCount()
        p.now.orders.text:SetText(orders > 0 and T.Hex("goldBright", orders == 1 and "1 offener Auftrag an dich"
            or (orders .. " offene Aufträge an dich")) or "Keine offenen Aufträge an dich.")

        local online = 0
        for _, m in ipairs(ns.Members.mains) do
            if m.onlineAs then online = online + 1 end
        end
        p.now.online.text:SetText(not IsInGuild() and "Du bist noch in keiner Gilde."
            or online == 1 and "1 Spieler gerade online" or (online .. " Spieler gerade online"))

        local last = ns.Fame:List()[1]
        p.now.fame.text:SetText(last and ("Zuletzt: " .. last.name .. (last.diffName ~= "" and (" (" .. last.diffName .. ")") or "")
            .. " am " .. date("%d.%m.", last.time)) or "Noch kein Erstkill – der erste Boss wartet.")

        p.now.away.text:SetText(ns.db.away.showButton and "Knopf auf dem Bildschirm: " .. T.Hex("green", "an")
            or "Knopf auf dem Bildschirm: aus  ·  /ea kind geht immer")
    end

    function p:Refresh()
        local first = ns.ShortName(ns.UnitFullName("player")) or ""
        first = first:match("^(%S+)") or first
        p.hello:SetText("Schön, dass du da bist, " .. first .. "!")

        if ns.Comm.newest then
            p.hello:SetText("Schön, dass du da bist, " .. first .. "!  " .. T.Hex("green", "Update " .. ns.Comm.newest .. " auf " .. ns.DOWNLOAD))
        end
        if IsInGuild() then
            local text = ns.Info:MOTD()
            p.motdCard.kicker:SetText("NACHRICHT DES TAGES")
            p.motd:SetWidth(leftWidth - 32)
            p.motd:SetText(text ~= "" and text or T.Hex("dim", "Gerade keine Nachricht des Tages."))
            p.joinBtn:Hide()
            p.joinCopy:Hide()
            p.motd:SetHeight(40)
        else
            local status = ns.Join:StatusText()
            p.motdCard.kicker:SetText("MITMACHEN")
            p.motd:SetWidth(leftWidth - 32 - 186)
            p.motd:SetText(status and T.Hex(ns.Join.state == "nobody" and "orange" or "goldBright", status)
                or "Noch nicht in der Gilde? Ein Klick genügt.")
            local fallback = ns.Join.state == "nobody" and ns.Join:FallbackCommand()
            if fallback and p.joinCopy.value ~= fallback then
                p.joinCopy.value = fallback
                p.joinCopy:SetText(fallback)
                p.joinCopy:SetCursorPosition(0)
            end
            p.joinCopy:SetShown(fallback and true or false)
            p.motd:SetHeight(fallback and 16 or 40)
            p.joinBtn:Show()
            p.joinBtn:SetText(ns.Join.state == "confirm" and "Ja, beitreten" or "Der Gilde beitreten")
            p.joinBtn:SetEnabled(ns.Join.state ~= "sending")
        end

        local plan = ns.db.plan
        local nextRaid = ns.Ready:NextRaid()
        if nextRaid then
            p.nextRaid:SetText("Nächster Raid: " .. (nextRaid.title or "?") .. "  ·  " .. date("%d.%m. %H:%M Uhr", nextRaid.at))
        elseif plan and plan.title then
            p.nextRaid:SetText("Geladen: " .. plan.title .. (plan.date and ("  ·  " .. plan.date) or ""))
        else
            p.nextRaid:SetText(G.raidHint)
        end
        p:RefreshNow()
    end

    return p
end

-- Reiter: Mitglieder (Mains und Twinks) ------------------------------------------
function UI:CreateMembersPanel()
    local p = self:NewPanel()
    local M = ns.Members
    local rightWidth = 330

    -- Kopierfeld: Addons dürfen nicht in die Zwischenablage schreiben und keine
    -- Offiziersnotizen ändern. „Kopieren“ legt den Namen markiert hierher; Strg+C,
    -- dann im Blizzard-Gildenmenü einfügen.
    local copyCard = StartCard(p, "Name kopieren", 104)
    copyCard:SetPoint("TOPRIGHT")
    copyCard:SetWidth(rightWidth)
    p.copyBox = T.EditBox(copyCard, rightWidth - 32, "„Kopieren“ in der Liste klicken")
    p.copyBox:SetPoint("TOPLEFT", 16, -32)
    p.copyBox:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    p.copyBox:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    p.copyBox:HookScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(self.value or "")
            self:HighlightText()
        end
    end)
    local copyHint = T.Text(copyCard, "muted")
    copyHint:SetPoint("TOPLEFT", 16, -68)
    copyHint:SetText("Strg+C – dann im Gildenmenü einfügen.")

    local function Copy(name)
        p.copyBox.value = name
        p.copyBox:SetText(name)
        p.copyBox:SetFocus()
        p.copyBox:HighlightText()
    end

    -- Links: Übersicht
    p.summary = T.Text(p, "body")
    p.summary:SetPoint("TOPLEFT", 2, -6)
    local search = T.EditBox(p, 180, "Name suchen …")
    T.AddClearButton(search)
    search:SetPoint("TOPRIGHT", -(rightWidth + 12), 0)
    search:HookScript("OnTextChanged", function() p:Refresh() end)
    -- Unter der Liste: Aktualisieren und der Stand der Twink-Zuordnung
    local reload = T.Button(p, "Aktualisieren", 120)
    reload:SetPoint("BOTTOMLEFT", 0, 0)
    reload:SetScript("OnClick", function() C_GuildInfo.GuildRoster() end)
    -- Addon-Check: alle Gildenmitglieder mit Addon melden ihre Version
    local check = T.Button(p, "Addon-Check", 120)
    check:SetPoint("LEFT", reload, "RIGHT", 8, 0)
    check:SetScript("OnClick", function()
        ns.Comm:Send("HELLO", ns.VERSION, "GUILD")
        ns.Print("Addon-Check gesendet – die Versionen erscheinen gleich in der Spalte „Status“.")
    end)
    p.stand = T.Text(p, "muted")
    p.stand:SetPoint("LEFT", check, "RIGHT", 12, 0)
    p.stand:SetWidth(CONTENT_W - rightWidth - 12 - 120 - 8 - 120 - 12)
    p.stand:SetWordWrap(false)

    local columns = {
        { key = "name", label = "Charakter", x = 4, w = 140 },
        { key = "rank", label = "Rang", x = 146, w = 80 },
        { key = "class", label = "Klasse", x = 228, w = 76 },
        { key = "status", label = "Status", x = 306, w = 92 },
        { key = "issue", label = "Hinweis", x = 400, right = -74 },
    }
    local list = CreateList(p, columns, function(row)
        row.copy = T.Button(row, "Kopieren", 66)
        row.copy:SetHeight(19)
        row.copy:SetPoint("RIGHT", -4, 0)
        row.copy:SetScript("OnClick", function(self) Copy(self:GetParent().data.display) end)
    end)
    list.panel:SetPoint("TOPLEFT", 0, -36)
    list.panel:SetPoint("BOTTOMRIGHT", -(rightWidth + 12), 36)
    list.onClick = function(_, e)
        p.selected = (p.selected ~= e.key) and e.key or nil
        p:Refresh()
    end
    list.onEnter = function(row, e)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine("|c" .. ClassHex(e.classFile) .. e.display .. "|r")
        GameTooltip:AddLine((e.class or "") .. (e.level and (", Stufe " .. e.level) or ""), 0.78, 0.75, 0.68)
        GameTooltip:AddLine(e.main and ("Twink von " .. e.main.display) or "Main", 1, 1, 1)
        if e.fromAccount then GameTooltip:AddLine("Auf deinem Account – noch ohne Offiziersnotiz", 0.78, 0.75, 0.68) end
        if #e.twinks > 0 then
            local names = {}
            for _, t in ipairs(e.twinks) do table.insert(names, t.display) end
            GameTooltip:AddLine("Twinks: " .. table.concat(names, ", "), 0.78, 0.75, 0.68, true)
        end
        if not M:CanView() and not ns.db.twinkMap then
            GameTooltip:AddLine("Wer wessen Twink ist, kommt automatisch, sobald ein Offizier mit Addon online ist.", 0.78, 0.75, 0.68, true)
        end
        if M:CanView() then
            if e.note ~= "" then GameTooltip:AddLine("Offiziersnotiz: " .. e.note, 0.6, 0.6, 0.6) end
            for _, issue in ipairs(e.issues) do GameTooltip:AddLine(issue.long, 1, 0.7, 0.35, true) end
        end
        GameTooltip:Show()
    end

    local noAccess = T.Text(p, "muted", "CENTER")
    noAccess:SetPoint("CENTER", list.panel, "CENTER")
    noAccess:SetWidth(420)

    -- Rechts unten: eigene Charaktere (für alle)
    local mine = StartCard(p, "Meine Charaktere", 150)
    mine:SetPoint("BOTTOMRIGHT")
    mine:SetWidth(rightWidth)
    p.mine = T.Text(mine, "small")
    p.mine:SetPoint("TOPLEFT", mine.kicker, "BOTTOMLEFT", 0, -6)
    p.mine:SetWidth(rightWidth - 32)
    p.mine:SetSpacing(3)
    local setMine = T.Button(mine, "Diesen Charakter als Main festlegen", rightWidth - 32, "primary")
    setMine:SetPoint("BOTTOMLEFT", 16, 12)
    setMine:SetScript("OnClick", function() M:SetMyMain() end)

    -- Rechts Mitte: Vorschläge aus dem Addon („Twink » Main“; kopiert wird der Main-Name)
    local sugg = StartCard(p, "Vorschläge aus dem Addon", 0)
    sugg:SetPoint("TOPRIGHT", copyCard, "BOTTOMRIGHT", 0, -10)
    sugg:SetPoint("BOTTOMRIGHT", mine, "TOPRIGHT", 0, 10)
    sugg:SetWidth(rightWidth)
    p.suggEmpty = T.Text(sugg, "muted")
    p.suggEmpty:SetPoint("TOPLEFT", 16, -34)
    p.suggEmpty:SetWidth(rightWidth - 32)
    p.suggEmpty:SetText("Keine offenen Vorschläge. Sie entstehen, wenn Spieler mit Addon ihren Main festlegen.")
    p.suggLines = {}
    for i = 1, 6 do
        local row = CreateFrame("Frame", nil, sugg)
        row:SetPoint("TOPLEFT", 16, -32 - (i - 1) * 24)
        row:SetPoint("TOPRIGHT", -12, -32 - (i - 1) * 24)
        row:SetHeight(22)
        row.text = T.Text(row, "small")
        row.text:SetPoint("LEFT")
        row.text:SetWidth(rightWidth - 120)
        row.text:SetWordWrap(false)
        row.take = T.Button(row, "Kopieren", 76)
        row.take:SetHeight(19)
        row.take:SetPoint("RIGHT")
        row.take:SetScript("OnClick", function(self)
            local s = self:GetParent().suggestion
            if s then Copy(ns.ShortName(s.main)) end
        end)
        row:SetScript("OnEnter", function(self)
            local s = self.suggestion
            if not s then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(ns.ShortName(s.twink) .. " ist ein Twink von " .. ns.ShortName(s.main))
            GameTooltip:AddLine("„Kopieren“ legt den Main-Namen bereit – im Gildenmenü bei " .. ns.ShortName(s.twink) .. " in die Offiziersnotiz einfügen.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        p.suggLines[i] = row
    end

    function p:Refresh()
        local canView, canEdit = M:CanView(), M:CanEdit()

        -- Rechts unten: Main und Twinks des ausgewählten Spielers, sonst die eigenen Charaktere
        local selected = p.selected and M.byKey[p.selected]
        if p.selected and not selected then p.selected = nil end
        if selected then
            local m = selected.main or selected
            local function Name(e)
                local text = "|c" .. ClassHex(e.classFile) .. e.display .. "|r"
                return e.online and (text .. T.Hex("green", " (online)")) or text
            end
            local twinks = {}
            for _, t in ipairs(m.twinks) do table.insert(twinks, Name(t)) end
            mine.kicker:SetText("CHARAKTERE VON " .. m.display:upper())
            p.mine:SetText("Main: " .. Name(m) .. "\n" ..
                (#twinks > 0 and ("Twinks: " .. table.concat(twinks, ", ")) or T.Hex("muted", "Keine Twinks eingetragen.")))
        else
            local main = M:MyMain()
            local here = ns.db.myChars[ns.PlayerKey()]
            local names = {}
            for key, c in pairs(ns.db.myChars) do
                if here and c.guild == here.guild then
                    table.insert(names, ns.ShortName(c.name) .. (key == ns.db.myMain and " (Main)" or ""))
                end
            end
            table.sort(names)
            mine.kicker:SetText("MEINE CHARAKTERE")
            p.mine:SetText((main and ("Main: " .. T.Hex("goldBright", ns.ShortName(main.name))) or T.Hex("orange", "Noch kein Main festgelegt.")) ..
                "\n" .. T.Hex("muted", "Bekannt: " .. table.concat(names, ", ")) ..
                (IsInGuild() and ("\n" .. T.Hex("dim", "Tipp: Spieler links anklicken, um seine Charaktere zu sehen.")) or ""))
        end
        setMine:SetShown(not selected)

        -- Alle sehen die Übersicht; Offiziere aus den Notizen, alle anderen aus der verteilten Zuordnung
        local map = ns.db.twinkMap
        list.panel:SetShown(IsInGuild())
        search:SetShown(IsInGuild())
        reload:SetShown(IsInGuild())
        p.stand:SetShown(IsInGuild())
        noAccess:SetShown(not IsInGuild())
        noAccess:SetText(IsInGuild()
            and "Noch keine Twink-Zuordnung empfangen.\n\nSie kommt automatisch, sobald ein Offizier mit Addon online ist."
            or "Du bist in keiner Gilde.\n\nSobald du in einer Gilde bist, siehst du hier alle Mitglieder mit ihren Twinks.")
        copyCard:SetShown(canEdit)
        sugg:SetShown(canEdit)
        mine:ClearAllPoints()
        if canEdit then mine:SetPoint("BOTTOMRIGHT") else mine:SetPoint("TOPRIGHT") end
        if not IsInGuild() then
            p.summary:SetText(T.Hex("orange", "Du bist in keiner Gilde."))
            return
        end

        local twinks, online = 0, 0
        for _, e in ipairs(M.list) do
            if e.main then twinks = twinks + 1 end
        end
        for _, m in ipairs(M.mains) do
            if m.onlineAs then online = online + 1 end
        end
        p.summary:SetText(string.format("%d Spieler  ·  %d Twinks  ·  %d gerade online", #M.mains, twinks, online))
        if canView then
            p.stand:SetText("Twinks aus den Offiziersnotizen")
        elseif map then
            p.stand:SetText("Twinks: Stand " .. date("%d.%m. %H:%M", map.time) .. " von " .. map.from)
        else
            -- Namen und Ränge darf jeder sehen; nur wer wessen Twink ist, kommt von den Offizieren
            p.stand:SetText(T.Hex("orange", "Twinks noch unbekannt – kommen, sobald ein Offizier mit Addon online ist."))
        end

        -- Mains mit ihren Twinks darunter; Suche findet die ganze Gruppe
        local filter = ns.Lower(strtrim(search:GetText() or ""))
        local rows = {}
        for _, m in ipairs(M.mains) do
            local match = filter == "" or m.key:find(filter, 1, true)
            for _, t in ipairs(m.twinks) do
                if not match and t.key:find(filter, 1, true) then match = true end
            end
            if match then
                table.insert(rows, m)
                for _, t in ipairs(m.twinks) do table.insert(rows, t) end
            end
        end

        list:SetData(rows, function(row, e)
            local c = row.cols
            local name = "|c" .. ClassHex(e.classFile) .. e.display .. "|r"
            if e.key == p.selected then name = T.Hex("goldBright", "» ") .. name end
            if e.main then name = "      " .. name end
            c.name:SetText(name)
            c.rank:SetText(e.main and T.Hex("muted", e.rank or "") or (e.rank or ""))
            c.class:SetText(T.Hex("muted", e.class or ""))
            if e.online then
                -- Mit Addon die Version dazu: grün = aktuell, orange = veraltet
                local version = e.key == ns.PlayerKey() and ns.VERSION or ns.Comm.versions[e.key]
                if version then
                    local newest = ns.Comm.newest and ns.CompareVersions(ns.Comm.newest, ns.VERSION) > 0 and ns.Comm.newest or ns.VERSION
                    local old = ns.CompareVersions(version, newest) < 0
                    c.status:SetText(T.Hex(old and "orange" or "green", "online · " .. version))
                else
                    c.status:SetText(T.Hex("green", "online"))
                end
            elseif not e.main and e.onlineAs then
                c.status:SetText(T.Hex("green", "als " .. e.onlineAs.display))
            else
                c.status:SetText("")
            end
            -- Unstimmigkeiten sind Sache der Offiziere; ausführlich im Tooltip
            local short = {}
            if canView then
                for _, issue in ipairs(e.issues) do table.insert(short, issue.short) end
            end
            c.issue:SetText(T.Hex("orange", table.concat(short, ", ")))
            row.copy:SetShown(canEdit)
        end)

        -- Vorschläge
        local suggestions = M:Suggestions()
        p.suggEmpty:SetShown(#suggestions == 0)
        for i, row in ipairs(p.suggLines) do
            local s = suggestions[i]
            row.suggestion = s
            if s then
                row.text:SetText(ns.ShortName(s.twink) .. T.Hex("muted", " » ") .. T.Hex("goldBright", ns.ShortName(s.main)))
                row:Show()
            else
                row:Hide()
            end
        end
    end

    return p
end

-- Reiter: Raid -------------------------------------------------------------
function UI:CreateRaidPanel()
    local p = self:NewPanel()

    -- Vier Kacheln wie auf der Startseite der Webseite
    local cards = {}
    local cardW = (CONTENT_W - 3 * 12) / 4
    for i, label in ipairs({ "Raid", "Anwesend", "Beute", "Soft-Reserves" }) do
        local card = T.Card(p, label)
        card:SetSize(cardW, 66)
        card:SetPoint("TOPLEFT", (i - 1) * (cardW + 12), 0)
        cards[i] = card
    end

    local rc = T.Button(p, "Bereitschaftscheck", 150, "primary")
    rc:SetScript("OnClick", function() C_PartyInfo.DoReadyCheck() end)
    local prep = T.Button(p, "Vorbereitung", 120)
    prep:SetScript("OnClick", function() ns.Ready:Check(ns.IsTrusted(ns.UnitFullName("player"))) end)
    prep:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Vorbereitung prüfen")
        GameTooltip:AddLine("Fläschchen, Essen, Haltbarkeit und Verzauberungen aller mit Addon. " ..
            "Als Leitung wird danach angesagt, was fehlt.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    prep:SetScript("OnLeave", GameTooltip_Hide)
    p.pause = T.Button(p, "Pause 5 Min", 110)
    p.pause:SetScript("OnClick", function()
        if ns.Pause:IsRunning() then ns.Pause:End() else ns.Pause:Start(5) end
    end)
    local ms = T.Button(p, "Fehlende Anmeldungen", 160)
    ms:SetScript("OnClick", function() ns.Raid:AnnounceMissingSignups() end)
    local msr = T.Button(p, "Fehlende SR ansagen", 150)
    msr:SetScript("OnClick", function() ns.Raid:AnnounceMissingSR() end)
    Row(p, 0, -78, { rc, prep, p.pause, ms, msr })

    -- Klassenverteilung im Tooltip der Kachel „Anwesend“
    cards[2]:EnableMouse(true)
    cards[2]:SetScript("OnEnter", function(self)
        if not p.classLines or #p.classLines == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Klassen im Raid")
        for _, line in ipairs(p.classLines) do GameTooltip:AddLine(line) end
        GameTooltip:Show()
    end)
    cards[2]:SetScript("OnLeave", GameTooltip_Hide)

    local columns = {
        { key = "grp", label = "Gr.", x = 4, w = 24 },
        { key = "name", label = "Name", x = 30, w = 118 },
        { key = "role", label = "Rolle", x = 150, w = 50 },
        { key = "class", label = "Klasse", x = 202, w = 84 },
        { key = "rank", label = "Rang", x = 288, w = 92 },
        { key = "signup", label = "Anmeldung", x = 382, w = 104 },
        { key = "status", label = "Status", x = 488, w = 84 },
        { key = "addon", label = "Addon", x = 574, w = 42 },
        { key = "prep", label = "Vorbereitung", x = 618, w = 92 },
        { key = "sr", label = "Soft-Reserve", x = 712 },
    }
    local list = CreateList(p, columns)
    list.panel:SetPoint("TOPLEFT", 0, -114)
    list.panel:SetPoint("BOTTOMRIGHT")

    list.onEnter = function(row, r)
        local classFile = r.member and r.member.classFile or ClassFileFromName(r.signup and r.signup.class)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine("|c" .. ClassHex(classFile) .. ns.ShortName(r.name) .. "|r")
        if r.member and r.member.zone then GameTooltip:AddLine(r.member.zone, 0.78, 0.75, 0.68) end
        local state = ns.Ready:Get(r.key)
        if state then
            local problems = ns.Ready.Problems(state)
            if #problems == 0 then
                GameTooltip:AddLine("Vorbereitung: alles da", 0.55, 0.85, 0.5)
            else
                GameTooltip:AddLine("Fehlt: " .. table.concat(problems, " · "), 1, 0.7, 0.35, true)
            end
        end
        local items = ns.SR:GetPlayerItems(r.key)
        if #items == 0 then
            GameTooltip:AddLine("Keine Soft-Reserve", 0.6, 0.6, 0.6)
        else
            for _, itemId in ipairs(items) do GameTooltip:AddLine(ItemLabel(itemId)) end
        end
        GameTooltip:Show()
    end

    local elapsed = 0
    p:SetScript("OnUpdate", function(_, e)
        elapsed = elapsed + e
        if elapsed > 3 then
            elapsed = 0
            ns.Raid:Update()
        end
    end)

    function p:Refresh()
        local members = ns.Raid.members
        local plan = ns.db.plan
        local hasSR = ns.SR:Count() > 0
        local playerKey = ns.PlayerKey()

        local online, classCount, classNames = 0, {}, {}
        for _, m in ipairs(members) do
            if m.online then online = online + 1 end
            if m.classFile then
                classCount[m.classFile] = (classCount[m.classFile] or 0) + 1
                classNames[m.classFile] = m.class
            end
        end

        local instName, instType, _, diffName = GetInstanceInfo()
        if plan and plan.title then
            cards[1].value:SetText(plan.title)
            cards[1].sub:SetText(plan.date or "aus dem Raidplaner")
        else
            cards[1].value:SetText(instType == "raid" and instName or "Kein Raid geladen")
            cards[1].sub:SetText(instType == "raid" and (diffName or "") or "Raidplaner: Reiter „Webseite“")
        end

        local planned = 0
        if plan then
            for _, s in pairs(plan.signups) do
                if s.status == "dabei" then planned = planned + 1 end
            end
        end
        cards[2].value:SetText(string.format("%d / %d", online, #members))
        cards[2].sub:SetText(plan and (planned .. " angemeldet") or "online / in der Gruppe")

        local method = ns.GetLootMethod()
        local ml = method == "master" and ns.Raid:GetMasterLooterName()
        cards[3].value:SetText(LOOT_METHODS[method] or method or "–")
        cards[3].sub:SetText(ml and ns.ShortName(ml) or " ")

        local players = 0
        for _ in pairs(ns.SR.byPlayer) do players = players + 1 end
        cards[4].value:SetText(hasSR and ns.SR:Count() or "–")
        cards[4].sub:SetText(hasSR and (players .. " Spieler") or "noch keine Liste")

        local parts = {}
        for classFile, n in pairs(classCount) do
            table.insert(parts, "|c" .. ClassHex(classFile) .. n .. " " .. classNames[classFile] .. "|r")
        end
        table.sort(parts)
        p.classLines = parts

        p.pause:SetText(ns.Pause:IsRunning() and "Pause beenden" or "Pause 5 Min")
        p.pause:SetEnabled(ns.Pause:CanControl())

        local rows = ns.Raid:GetOverview()
        table.sort(rows, function(a, b)
            local ga = a.member and a.member.group or 99
            local gb = b.member and b.member.group or 99
            if ga ~= gb then return ga < gb end
            return a.name < b.name
        end)

        list:SetData(rows, function(row, r)
            local col, m, s = row.cols, r.member, r.signup
            local classFile = m and m.classFile or ClassFileFromName(s and s.class)
            local nameText = "|c" .. ClassHex(classFile) .. ns.ShortName(r.name) .. "|r"
            col.grp:SetText(m and m.group or T.Hex("dim", "–"))
            col.name:SetText(m and nameText or T.Hex("dim", ns.ShortName(r.name)))
            col.role:SetText(ROLE_NAMES[(s and s.role) or (m and m.combatRole)] or "")
            col.class:SetText((m and m.class) or (s and s.class) or "")

            local rank = ""
            if m then
                rank = m.rank == 2 and "Leitung" or (m.rank == 1 and "Assistent" or "")
                if m.isML then rank = rank ~= "" and (rank .. ", PM") or "Plündermeister" end
                if m.role == "MAINTANK" then rank = rank ~= "" and (rank .. ", MT") or "Main-Tank" end
            end
            col.rank:SetText(rank)

            local state = SIGNUP_STATES[r.state]
            col.signup:SetText((plan and state) and T.Hex(state[2], state[1]) or "")

            local ready = ns.Raid.ready[r.key]
            local awayLeft
            if m then
                local other = ns.Away:Get(m.key)
                awayLeft = (r.key == playerKey and ns.Away:Left()) or (other and other.ends - GetTime())
            end
            if not m then
                col.status:SetText("")
            elseif not m.online then
                col.status:SetText(T.Hex("dim", "Offline"))
            elseif awayLeft then
                local s = math.abs(math.floor(awayLeft + 0.5))
                col.status:SetText(T.Hex(awayLeft >= 0 and "orange" or "red",
                    string.format("Kind · %s%d:%02d", awayLeft >= 0 and "" or "+", math.floor(s / 60), s % 60)))
            elseif m.dead then
                col.status:SetText(T.Hex("red", "Tot"))
            elseif ready == "ready" then
                col.status:SetText(T.Hex("green", "Bereit"))
            elseif ready == "notready" then
                col.status:SetText(T.Hex("red", "Nicht bereit"))
            elseif ready == "waiting" then
                col.status:SetText(T.Hex("goldBright", "Wartet …"))
            elseif ready == "afk" then
                col.status:SetText(T.Hex("orange", "AFK – Kind ruft?"))
            else
                col.status:SetText(T.Hex("green", "Da"))
            end

            local version = m and (r.key == playerKey and ns.VERSION or ns.Comm.versions[m.key])
            col.addon:SetText(m and (version and T.Hex("green", version) or T.Hex("dim", "–")) or "")

            local prepState = m and ns.Ready:Get(r.key)
            if prepState then
                local short = ns.Ready.Short(prepState)
                col.prep:SetText(#short == 0 and T.Hex("green", "alles da") or T.Hex("orange", table.concat(short, ", ")))
            else
                col.prep:SetText("")
            end

            local items = ns.SR:GetPlayerItems(r.key)
            if #items > 0 then
                local names = {}
                for _, itemId in ipairs(items) do
                    table.insert(names, ItemInfo(itemId) or ("#" .. itemId))
                end
                col.sr:SetText(T.Hex("goldBright", table.concat(names, ", ")))
            else
                col.sr:SetText(hasSR and T.Hex("red", "keine") or "")
            end
        end)
    end

    return p
end

-- Reiter: Soft-Reserve -----------------------------------------------------
function UI:CreateSRPanel()
    local p = self:NewPanel()

    local imp = T.Button(p, "Raid einfügen", 130, "primary")
    imp:SetScript("OnClick", function() UI:ShowImport() end)
    local send = T.Button(p, "An Gruppe senden", 140)
    send:SetScript("OnClick", function() ns.SR:Broadcast() end)
    local mine = T.Button(p, "Meine Reserves", 120)
    mine:SetScript("OnClick", function() ns.SR:PrintOwn() end)
    local clear = T.Button(p, "Leeren", 80)
    clear:SetScript("OnClick", function() StaticPopup_Show("ELTERNABEND_CLEAR_SR") end)
    Row(p, 0, 0, { imp, send, mine, clear })

    local search = T.EditBox(p, 200, "Spieler oder Item suchen …")
    T.AddClearButton(search)
    search:SetPoint("TOPRIGHT", 0, 0)
    search:HookScript("OnTextChanged", function() p:Refresh() end)

    p.info = T.Text(p, "muted")
    p.info:SetPoint("TOPLEFT", 2, -38)

    local columns = {
        { key = "icon", x = 4, icon = true },
        { key = "item", label = "Item", x = 26, w = 260 },
        { key = "boss", label = "Boss", x = 290, w = 150 },
        { key = "who", label = "Reserviert von", x = 444 },
    }
    local list = CreateList(p, columns)
    list.panel:SetPoint("TOPLEFT", 0, -58)
    list.panel:SetPoint("BOTTOMRIGHT")
    list.onEnter = function(row, d) ShowItemTooltip(row, d.itemId) end
    list.onClick = function(_, d)
        local _, link = ItemInfo(d.itemId)
        if link then HandleModifiedItemClick(link) end
    end

    function p:Refresh()
        local data = ns.SR:Data()
        local filter = ns.Lower(strtrim(search:GetText() or ""))
        local rows = {}
        for itemId, entries in pairs(data.items) do
            local name = ItemInfo(itemId) or entries[1].itemName or ("Item " .. itemId)
            local reservers = ns.SR:GetReserverNames(itemId)
            local match = filter == "" or ns.Lower(name):find(filter, 1, true)
            if not match then
                for _, r in ipairs(reservers) do
                    if r.key:find(filter, 1, true) then
                        match = true
                        break
                    end
                end
            end
            if match then
                table.insert(rows, { itemId = itemId, name = name, boss = entries[1].boss or "", reservers = reservers })
            end
        end
        table.sort(rows, function(a, b)
            if a.boss ~= b.boss then return a.boss < b.boss end
            return a.name < b.name
        end)

        local total = ns.SR:Count()
        if total == 0 then
            p.info:SetText("Noch keine Soft-Reserves. „Raid einfügen“ und den Text aus dem Raidplaner einfügen.")
        else
            p.info:SetText(string.format("%d Reservierungen auf %d Items  ·  %s  ·  %s",
                total, #rows, data.source or "?", data.importedAt and date("%d.%m. %H:%M", data.importedAt) or "?"))
        end

        list:SetData(rows, function(row, d)
            local _, _, _, icon = ItemInfo(d.itemId)
            row.cols.icon:SetTexture(icon or 134400)
            row.cols.item:SetText(ItemLabel(d.itemId, d.name))
            row.cols.boss:SetText(T.Hex("muted", d.boss))
            local parts = {}
            for _, r in ipairs(d.reservers) do
                if r.won then
                    table.insert(parts, T.Hex("dim", r.label .. " (erhalten)"))
                elseif ns.Raid:IsMember(r.key) then
                    table.insert(parts, "|c" .. ClassHex(ns.Raid:Find(r.key).classFile) .. r.label .. "|r")
                else
                    table.insert(parts, T.Hex("dim", r.label))
                end
            end
            row.cols.who:SetText(table.concat(parts, ", "))
        end)
    end

    return p
end

-- Reiter: Plündermeister ------------------------------------------------
function UI:CreateLootPanel()
    local p = self:NewPanel()

    p.mlInfo = T.Text(p, "body")
    p.mlInfo:SetPoint("TOPLEFT", 2, -2)
    local rules = T.Text(p, "muted", "RIGHT")
    rules:SetPoint("TOPRIGHT", 0, -2)
    rules:SetText("Reserviert: nur SR würfelt, bei einer Person direkt  ·  sonst Hauptspec vor Off-Spec & Twinks")

    local lootColumns = {
        { key = "icon", x = 4, icon = true },
        { key = "item", label = "Beute", x = 26, w = 270 },
        { key = "sr", label = "Soft-Reserve", x = 300, right = -190 },
    }
    local lootList = CreateList(p, lootColumns, function(row)
        row.rollBtn = T.Button(row, "Würfeln", 84, "primary")
        row.rollBtn:SetHeight(19)
        row.rollBtn:SetPoint("RIGHT", -4, 0)
        row.rollBtn:SetScript("OnClick", function(self) ns.Loot:StartRoll(self:GetParent().data) end)
        row.srBtn = T.Button(row, "An SR", 84)
        row.srBtn:SetHeight(19)
        row.srBtn:SetPoint("RIGHT", row.rollBtn, "LEFT", -6, 0)
        row.srBtn:SetScript("OnClick", function(self)
            local d = self:GetParent().data
            StaticPopup_Show("ELTERNABEND_AWARD", d.link, d.srWinner.label, { name = d.srWinner.name, item = d })
        end)
    end)
    lootList.panel:SetPoint("TOPLEFT", 0, -22)
    lootList.panel:SetPoint("RIGHT")
    lootList.panel:SetHeight(36 + ROW_H * 5)
    lootList.onEnter = function(row, d) ShowItemTooltip(row, d.itemId, d.link) end
    lootList.onClick = function(_, d) HandleModifiedItemClick(d.link) end

    -- Aktuelle Würfelrunde
    local top = -22 - (36 + ROW_H * 5) - 14
    local kicker = T.Text(p, "kicker")
    kicker:SetPoint("TOPLEFT", 2, top)
    kicker:SetText("AKTUELLE WÜRFELRUNDE")
    p.rollTitle = T.Text(p, "heading")
    p.rollTitle:SetPoint("TOPLEFT", 2, top - 14)
    p.rollTitle:SetWidth(600)
    p.rollTitle:SetWordWrap(false)
    p.timer = T.Text(p, "title", "RIGHT")
    p.timer:SetPoint("TOPRIGHT", -4, top - 2)

    local endBtn = T.Button(p, "Beenden", 100, "primary")
    endBtn:SetScript("OnClick", function() ns.Loot:EndRoll() end)
    local cancelBtn = T.Button(p, "Abbrechen", 100)
    cancelBtn:SetScript("OnClick", function() ns.Loot:CancelRoll() end)
    local manual = T.EditBox(p, 150, "Spielername")
    local giveBtn = T.Button(p, "Vergeben", 100)
    giveBtn:SetScript("OnClick", function()
        local cur = ns.Loot.current
        local name = strtrim(manual:GetText() or "")
        if cur and name ~= "" then
            StaticPopup_Show("ELTERNABEND_AWARD", cur.link, name, { name = name })
        end
    end)
    Row(p, 0, top - 44, { endBtn, cancelBtn, manual, giveBtn })
    p.endBtn, p.cancelBtn, p.giveBtn = endBtn, cancelBtn, giveBtn

    p.warning = T.Text(p, "small")
    p.warning:SetPoint("LEFT", giveBtn, "RIGHT", 12, 0)
    p.warning:SetPoint("RIGHT", -4, 0)

    local rollColumns = {
        { key = "pos", label = "#", x = 4, w = 22 },
        { key = "name", label = "Spieler", x = 28, w = 150 },
        { key = "roll", label = "Wurf", x = 180, w = 50 },
        { key = "type", label = "Art", x = 232, w = 80 },
        { key = "sr", label = "SR", x = 314, w = 40 },
        { key = "note", label = "Hinweis", x = 356 },
    }
    local rollList = CreateList(p, rollColumns)
    rollList.panel:SetPoint("TOPLEFT", 0, top - 80)
    rollList.panel:SetPoint("BOTTOMRIGHT")
    rollList.onClick = function(_, r)
        local cur = ns.Loot.current
        if cur then StaticPopup_Show("ELTERNABEND_AWARD", cur.link, ns.ShortName(r.name), { name = r.name }) end
    end
    rollList.onEnter = function(row)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Klicken, um das Item an diesen Spieler zu vergeben")
        GameTooltip:Show()
    end

    local elapsed = 0
    p:SetScript("OnUpdate", function(_, e)
        elapsed = elapsed + e
        if elapsed < 0.2 then return end
        elapsed = 0
        local cur = ns.Loot.current
        if cur and cur.active then
            p.timer:SetText(math.max(0, math.ceil(cur.endsAt - GetTime())))
        else
            p.timer:SetText("")
        end
    end)

    function p:Refresh()
        local method = ns.GetLootMethod()
        if ns.IsMasterLooter() then
            p.mlInfo:SetText(T.Hex("green", "Du bist Plündermeister.") .. T.Hex("muted", "  Öffne eine Leiche, um die Beute hier zu sehen."))
        elseif method == "master" then
            p.mlInfo:SetText("Plündermeister: " .. T.Hex("goldBright", ns.ShortName(ns.Raid:GetMasterLooterName()) or "?"))
        else
            p.mlInfo:SetText(T.Hex("goldBright", "Kein Plündermeister aktiv") .. T.Hex("muted", " – Würfelrunden per /ea roll gehen trotzdem."))
        end

        local rolling = ns.Loot.current and ns.Loot.current.active
        lootList:SetData(ns.Loot.items, function(row, d)
            local _, _, _, icon = ItemInfo(d.itemId)
            row.cols.icon:SetTexture(icon)
            row.cols.item:SetText(d.link)
            local present = ns.Loot:GetPresentReservers(d.itemId)
            local names = {}
            for _, n in ipairs(present) do table.insert(names, n.label) end
            row.cols.sr:SetText(#names > 0 and T.Hex("green", table.concat(names, ", ")) or T.Hex("dim", "–"))
            d.srWinner = #present == 1 and present[1] or nil
            row.srBtn:SetShown(d.srWinner ~= nil)
            row.rollBtn:SetEnabled(not rolling)
        end)

        local cur = ns.Loot.current
        if cur then
            p.rollTitle:SetText((cur.active and "" or T.Hex("muted", "Beendet: ")) .. cur.link)
        else
            p.rollTitle:SetText(T.Hex("dim", "Gerade wird nichts ausgewürfelt"))
        end
        p.endBtn:SetEnabled(cur ~= nil and cur.active == true)
        p.cancelBtn:SetEnabled(cur ~= nil)
        p.giveBtn:SetEnabled(cur ~= nil)
        p.warning:SetText(cur and cur.secretRolls and T.Hex("orange", "Chat-Sperre: Würfe während des Kampfes sind nicht lesbar – bitte danach würfeln.") or "")

        local playerHex = {}
        for _, m in ipairs(ns.Raid.members) do playerHex[m.key] = ClassHex(m.classFile) end

        rollList:SetData(ns.Loot:GetSortedRolls(), function(row, r, i)
            local col = row.cols
            col.pos:SetText(T.Hex("muted", i))
            col.name:SetText("|c" .. (playerHex[r.key] or T.hex.cream) .. ns.ShortName(r.name) .. "|r")
            col.roll:SetText(T.Hex("goldBright", r.roll))
            local typeColor = r.label == "SR" and "green" or (r.label == "MS" and "cream" or (r.valid and "muted" or "red"))
            col.type:SetText(T.Hex(typeColor, r.label))
            col.sr:SetText(r.sr and T.Hex("green", "ja") or "")
            local notes = {}
            if not r.valid then table.insert(notes, string.format("Bereich %d-%d", r.min, r.max)) end
            if r.rerolls then table.insert(notes, "mehrfach gewürfelt (" .. (r.rerolls + 1) .. "x)") end
            col.note:SetText(T.Hex("orange", table.concat(notes, ", ")))
        end)
    end

    return p
end

-- Reiter: Verlauf ----------------------------------------------------------
function UI:CreateHistoryPanel()
    local p = self:NewPanel()

    local export = T.Button(p, "Bericht für die Webseite", 190, "primary")
    export:SetScript("OnClick", function() UI:ShowReport() end)
    local csv = T.Button(p, "Als CSV", 90)
    csv:SetScript("OnClick", function() UI:ShowExport() end)
    local clear = T.Button(p, "Leeren", 80)
    clear:SetScript("OnClick", function() StaticPopup_Show("ELTERNABEND_CLEAR_HISTORY") end)
    Row(p, 0, 0, { export, csv, clear })

    local columns = {
        { key = "time", label = "Zeit", x = 4, w = 96 },
        { key = "item", label = "Item", x = 102, w = 260 },
        { key = "winner", label = "Gewinner", x = 366, w = 120 },
        { key = "type", label = "Art", x = 488, w = 80 },
        { key = "roll", label = "Wurf", x = 570, w = 40 },
        { key = "note", label = "Hinweis", x = 612 },
    }
    local list = CreateList(p, columns)
    list.panel:SetPoint("TOPLEFT", 0, -38)
    list.panel:SetPoint("BOTTOMRIGHT")
    list.onEnter = function(row, h) ShowItemTooltip(row, h.itemId, h.link) end
    list.onClick = function(_, h) HandleModifiedItemClick(h.link) end
    p.empty = T.Text(list.panel, "muted", "CENTER")
    p.empty:SetPoint("CENTER")
    p.empty:SetText("Noch keine Beute vergeben. Was im Raid verteilt wird, steht hier.")

    function p:Refresh()
        -- Den Bericht für die Webseite erstellt die Leitung
        local leader = UI:IsLeader()
        export:SetShown(leader)
        csv:ClearAllPoints()
        if leader then csv:SetPoint("LEFT", export, "RIGHT", 8, 0) else csv:SetPoint("TOPLEFT", 0, 0) end
        p.empty:SetShown(#ns.db.history == 0)
        list:SetData(ns.db.history, function(row, h)
            local col = row.cols
            col.time:SetText(T.Hex("muted", date("%d.%m. %H:%M", h.time)))
            col.item:SetText(h.link)
            col.winner:SetText(h.winner)
            col.type:SetText(h.sr and T.Hex("green", "SR") or h.label)
            col.roll:SetText(h.roll or "")
            local notes = {}
            if h.trade then table.insert(notes, T.Hex("goldBright", "per Handel")) end
            if h.zone and h.zone ~= "" then table.insert(notes, T.Hex("muted", h.zone)) end
            col.note:SetText(table.concat(notes, "  "))
        end)
    end

    return p
end

-- Reiter: Ruhmeshalle – die Erstkills der Gilde ------------------------------
function UI:CreateFamePanel()
    local p = self:NewPanel()
    local title = T.Text(p, "heading")
    title:SetPoint("TOPLEFT", 2, -4)
    title:SetText("Ruhmeshalle – die Erstkills der Gilde")

    local fameList = CreateList(p, {
        { key = "time", label = "Datum", x = 4, w = 80 },
        { key = "boss", label = "Erstkill", x = 86, w = 190 },
        { key = "diff", label = "Schwierigkeit", x = 278, w = 100 },
        { key = "raid", label = "Raid", x = 380, w = 150 },
        { key = "players", label = "Dabei", x = 532 },
    })
    fameList.panel:SetPoint("TOPLEFT", 0, -38)
    fameList.panel:SetPoint("BOTTOMRIGHT")
    fameList.onEnter = function(row, e)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(e.name)
        GameTooltip:AddLine(e.instance .. (e.diffName ~= "" and ("  ·  " .. e.diffName) or ""), 0.78, 0.75, 0.68)
        GameTooltip:AddLine(date("%d.%m.%Y %H:%M", e.time), 0.6, 0.6, 0.6)
        if e.players ~= "" then GameTooltip:AddLine(e.players, 1, 1, 1, true) end
        GameTooltip:Show()
    end
    p.empty = T.Text(fameList.panel, "muted", "CENTER")
    p.empty:SetPoint("CENTER")
    p.empty:SetText("Noch keine Erstkills. Fällt ein Raidboss zum ersten Mal in einer Gildengruppe, steht er hier.")

    function p:Refresh()
        local entries = ns.Fame:List()
        p.empty:SetShown(#entries == 0)
        fameList:SetData(entries, function(row, e)
            row.cols.time:SetText(T.Hex("muted", date("%d.%m.%Y", e.time)))
            row.cols.boss:SetText(T.Hex("goldBright", e.name))
            row.cols.diff:SetText(e.diffName)
            row.cols.raid:SetText(T.Hex("muted", e.instance))
            row.cols.players:SetText(e.players)
        end)
    end

    return p
end

-- Reiter: Webseite ---------------------------------------------------------
local function InfoCard(parent, kicker, heading, body)
    local card = T.Panel(parent)
    local k = T.Text(card, "kicker")
    k:SetPoint("TOPLEFT", 20, -18)
    k:SetText(kicker:upper())
    local h = T.Text(card, "heading")
    h:SetPoint("TOPLEFT", k, "BOTTOMLEFT", 0, -6)
    h:SetText(heading)
    local b = T.Text(card, "body")
    b:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -12)
    b:SetPoint("RIGHT", -20, 0)
    b:SetSpacing(4)
    b:SetText(body)
    card.status = T.Text(card, "small")
    card.status:SetPoint("BOTTOMLEFT", 20, 60)
    card.status:SetPoint("RIGHT", -20, 0)
    card.status:SetSpacing(4)
    return card
end

function UI:CreateWebPanel()
    local p = self:NewPanel()
    local half = (CONTENT_W - 16) / 2

    local left = InfoCard(p, "Vom Raidplaner", "Raid ins Spiel holen",
        "1.  Auf " .. ns.WEBSITE .. " den Raidplaner öffnen.\n" ..
        "2.  Beim Raid den Text „Für das Addon“ kopieren.\n" ..
        "3.  Hier „Raid einfügen“ klicken und mit Strg+V einfügen.\n\n" ..
        T.Hex("muted", "Danach siehst du Anmeldungen, Ersatzbank und Soft-Reserves direkt im Spiel – " ..
        "und wer angemeldet ist, aber noch fehlt."))
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(half)
    local imp = T.Button(left, "Raid einfügen", 140, "primary")
    imp:SetScript("OnClick", function() UI:ShowImport() end)
    local drop = T.Button(left, "Raid entfernen", 130)
    drop:SetScript("OnClick", function()
        ns.db.plan = nil
        ns:Fire("ROSTER_UPDATE")
    end)
    imp:SetPoint("BOTTOMLEFT", 20, 20)
    drop:SetPoint("LEFT", imp, "RIGHT", 8, 0)

    local right = InfoCard(p, "Für die Webseite", "Raid-Bericht",
        "Während des Raids schreibt das Addon mit, wer da ist, welche Bosse fallen und wer welche Beute bekommt.\n\n" ..
        "Nach dem Raid „Bericht erzeugen“ klicken, den Text kopieren und im Raidplaner unter " ..
        "„Für die Gildenleitung“ einfügen. So landen Anwesenheit und Beute auf der Webseite.")
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetWidth(half)
    local report = T.Button(right, "Bericht erzeugen", 150, "primary")
    report:SetScript("OnClick", function() UI:ShowReport() end)
    local toggle = T.Button(right, "Protokoll starten", 150)
    toggle:SetScript("OnClick", function()
        if ns.Web:IsRunning() then ns.Web:EndSession() else ns.Web:StartSession() end
    end)
    report:SetPoint("BOTTOMLEFT", 20, 20)
    toggle:SetPoint("LEFT", report, "RIGHT", 8, 0)

    function p:Refresh()
        local plan = ns.db.plan
        if plan then
            local counts = {}
            for _, s in pairs(plan.signups) do counts[s.status] = (counts[s.status] or 0) + 1 end
            left.status:SetText(T.Hex("goldBright", plan.title or "Raid") .. "  " .. T.Hex("muted", plan.date or "") .. "\n" ..
                string.format("%d dabei  ·  %d Ersatzbank  ·  %d vielleicht  ·  %d Soft-Reserves",
                    counts.dabei or 0, counts.ersatz or 0, counts.vielleicht or 0, ns.SR:Count()))
        else
            left.status:SetText(T.Hex("dim", "Noch kein Raid geladen."))
        end
        drop:SetEnabled(plan ~= nil)

        local s = ns.db.session
        if s then
            local players, kills, loot = 0, 0, 0
            for _ in pairs(s.players) do players = players + 1 end
            for _, b in ipairs(s.bosses) do if b.kill then kills = kills + 1 end end
            for _, h in ipairs(ns.db.history) do if h.session == s.id then loot = loot + 1 end end
            local head = s.ended and T.Hex("muted", "Beendet: ") or T.Hex("green", "Läuft seit ")
            right.status:SetText(head .. date("%d.%m. %H:%M", s.start) .. (s.instance and ("  ·  " .. s.instance) or "") .. "\n" ..
                string.format("%d Spieler  ·  %d Bosse besiegt  ·  %d Items vergeben", players, kills, loot))
        else
            right.status:SetText(T.Hex("dim", "Noch kein Protokoll. Es startet von selbst, sobald ihr eine Raid-Instanz betretet."))
        end
        report:SetEnabled(s ~= nil)
        toggle:SetText(ns.Web:IsRunning() and "Raid beenden" or "Protokoll starten")
    end

    return p
end

-- Reiter: Taktik ------------------------------------------------------------
function UI:CreateTacticPanel()
    local p = self:NewPanel()

    local columns = {
        { key = "boss", label = "Boss", x = 4, w = 150 },
        { key = "raid", label = "Raid", x = 156 },
    }
    local list = CreateList(p, columns)
    list.panel:SetPoint("TOPLEFT")
    list.panel:SetPoint("BOTTOMLEFT")
    list.panel:SetWidth(250)
    list.onClick = function(_, t)
        p.selected = t.id
        p:Refresh()
    end

    local view = T.Panel(p)
    view:SetPoint("TOPLEFT", list.panel, "TOPRIGHT", 12, 0)
    view:SetPoint("BOTTOMRIGHT")

    local kicker = T.Text(view, "kicker")
    kicker:SetPoint("TOPLEFT", 18, -16)
    local title = T.Text(view, "heading")
    title:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -4)

    local show = T.Button(view, "Dem Raid zeigen", 150, "primary")
    show:SetPoint("TOPRIGHT", -16, -16)
    show:SetScript("OnClick", function() if p.current then ns.Tactics:ShowToRaid(p.current) end end)
    local big = T.Button(view, "Groß anzeigen", 130)
    big:SetPoint("RIGHT", show, "LEFT", -8, 0)
    big:SetScript("OnClick", function() if p.current then UI:ShowTactic(p.current) end end)

    local image = view:CreateTexture(nil, "ARTWORK")
    image:SetPoint("TOP", 0, -64)
    local imageButton = CreateFrame("Button", nil, view)
    imageButton:SetAllPoints(image)
    imageButton:SetScript("OnClick", function() if p.current then UI:ShowTactic(p.current) end end)

    local text = T.Text(view, "body")
    text:SetSpacing(3)

    function p:Refresh()
        local all = ns.Tactics:All()
        local current = ns.Tactics:Get(p.selected) or all[1]
        p.current = current

        list:SetData(all, function(row, t)
            row.cols.boss:SetText(t == current and T.Hex("goldBright", t.boss) or t.boss)
            row.cols.raid:SetText(T.Hex("muted", t.raid))
        end)

        local top = 64
        if not current then
            kicker:SetText("TAKTIK")
            title:SetText("Noch keine Taktikbilder")
            image:Hide()
            imageButton:Hide()
            show:Hide()
            big:Hide()
            text:SetText(T.Hex("muted", "Sobald die Taktikbilder auf " .. ns.WEBSITE .. " stehen, kommen sie mit einer neuen Addon-Version hierher."))
        else
            p.selected = current.id
            kicker:SetText(current.raid:upper())
            title:SetText(current.boss)
            show:Show()
            big:Show()
            show:SetEnabled(IsInGroup() and ns.IsTrusted(ns.UnitFullName("player")))
            local width, height = view:GetWidth() - 36, view:GetHeight() - top - 80
            if width <= 0 or height <= 0 then width, height = 600, 300 end
            ns.Tactics:Fit(image, current, width, height)
            image:Show()
            imageButton:Show()
            top = top + image:GetHeight() + 12
            text:SetText(current.text or "")
        end
        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", 18, -top)
        text:SetPoint("TOPRIGHT", -18, -top)
    end

    return p
end

-- Großansicht, auch wenn die Raidleitung eine Taktik zeigt
function UI:ShowTactic(t, from)
    local v = self.tacticViewer
    if not v then
        v = CreateFrame("Frame", "ElternabendTaktikFrame", UIParent, "BackdropTemplate")
        v:SetFrameStrata("DIALOG")
        v:SetToplevel(true)
        v:SetMovable(true)
        v:SetClampedToScreen(true)
        v:EnableMouse(true)
        v:RegisterForDrag("LeftButton")
        v:SetScript("OnDragStart", v.StartMoving)
        v:SetScript("OnDragStop", v.StopMovingOrSizing)
        T.Backdrop(v, T.colors.navy, 0.97, 0.7)
        tinsert(UISpecialFrames, "ElternabendTaktikFrame")

        v.kicker = T.Text(v, "kicker")
        v.kicker:SetPoint("TOPLEFT", 16, -14)
        v.title = T.Text(v, "heading")
        v.title:SetPoint("TOPLEFT", v.kicker, "BOTTOMLEFT", 0, -4)
        local close = T.Button(v, "X", 26)
        close:SetPoint("TOPRIGHT", -12, -12)
        close:SetScript("OnClick", function() v:Hide() end)
        v.image = v:CreateTexture(nil, "ARTWORK")
        v.image:SetPoint("TOPLEFT", 16, -58)
        v.text = T.Text(v, "body")
        v.text:SetPoint("TOPLEFT", v.image, "BOTTOMLEFT", 0, -10)
        v.text:SetSpacing(3)
        self.tacticViewer = v
    end

    v.kicker:SetText(t.raid:upper() .. (from and ("  ·  GEZEIGT VON " .. from:upper()) or ""))
    v.title:SetText(t.boss)
    ns.Tactics:Fit(v.image, t, UIParent:GetWidth() * 0.8, UIParent:GetHeight() * 0.72)
    v.text:SetWidth(v.image:GetWidth())
    v.text:SetText(t.text or "")
    local textHeight = (t.text and t.text ~= "") and (v.text:GetStringHeight() + 14) or 0
    v:SetSize(v.image:GetWidth() + 32, v.image:GetHeight() + 72 + textHeight)
    v:ClearAllPoints()
    v:SetPoint("CENTER")
    v:Show()
    if from then PlaySound(SOUNDKIT.READY_CHECK) end
end

-- Reiter: Gilde (Flüster-Einladung) -------------------------------------------
local RECRUIT_COLORS = {
    angefragt = "goldBright", ["angefragt (Addon)"] = "goldBright", eingeladen = "cream", beigetreten = "green",
    abgelehnt = "red", verworfen = "dim", ["schon in einer Gilde"] = "orange",
}

function UI:CreateGuildPanel()
    local p = self:NewPanel()
    local function S() return ns.db.recruit end

    local card = T.Panel(p)
    card:SetPoint("TOPLEFT")
    card:SetPoint("BOTTOMLEFT")
    card:SetWidth(330)

    local kicker = T.Text(card, "kicker")
    kicker:SetPoint("TOPLEFT", 18, -16)
    kicker:SetText("FLÜSTER-EINLADUNG")
    local heading = T.Text(card, "heading")
    heading:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -4)
    heading:SetText("Neue Mitglieder")
    local intro = T.Text(card, "small")
    intro:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -10)
    intro:SetWidth(294)
    intro:SetSpacing(3)
    intro:SetText("Wer dich mit einem Stichwort anflüstert, landet in der Liste. „Einladen“ zeigt den Befehl /ginvite Name markiert zum Kopieren – dann im Chat einfügen und Enter. Einladen darf in WoW Forever nur man selbst, kein Addon.")

    local toggle = T.Button(card, "", 294, "primary")
    toggle:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -14)
    toggle:SetScript("OnClick", function()
        S().enabled = not S().enabled
        p:Refresh()
    end)

    local kwLabel = T.Text(card, "kicker")
    kwLabel:SetPoint("TOPLEFT", toggle, "BOTTOMLEFT", 0, -16)
    kwLabel:SetText("STICHWÖRTER, MIT KOMMA GETRENNT")
    local keywords = T.EditBox(card, 294)
    keywords:SetPoint("TOPLEFT", kwLabel, "BOTTOMLEFT", 0, -6)
    keywords:HookScript("OnEditFocusLost", function(self) S().keywords = self:GetText() end)

    local replyLabel = T.Text(card, "kicker")
    replyLabel:SetPoint("TOPLEFT", keywords, "BOTTOMLEFT", 0, -14)
    replyLabel:SetText("ANTWORT NACH DER EINLADUNG (LEER = KEINE)")
    local reply = T.EditBox(card, 294)
    reply:SetPoint("TOPLEFT", replyLabel, "BOTTOMLEFT", 0, -6)
    reply:SetMaxLetters(240)
    reply:HookScript("OnEditFocusLost", function(self) S().reply = strtrim(self:GetText()) end)

    local hint = T.Text(card, "muted")
    hint:SetPoint("BOTTOMLEFT", 18, 16)
    hint:SetWidth(294)
    hint:SetSpacing(3)
    hint:SetText("Noch schneller: In den Tastaturbelegungen unter AddOns » Elternabend eine Taste für „Nächste Gildenanfrage einladen“ festlegen. Dann markiert ein Tastendruck den Befehl für die nächste Anfrage zum Kopieren.")

    p.summary = T.Text(p, "body")
    p.summary:SetPoint("TOPLEFT", card, "TOPRIGHT", 14, -6)
    local nextBtn = T.Button(p, "Nächste einladen", 150, "primary")
    nextBtn:SetPoint("TOPRIGHT", 0, 0)
    ns.Recruit:SetupInviteButton(nextBtn, function() return ns.Recruit:NextName() end)

    local columns = {
        { key = "name", label = "Spieler", x = 4, w = 140 },
        { key = "time", label = "Zeit", x = 146, w = 90 },
        { key = "status", label = "Status", x = 238, right = -200 },
    }
    local list = CreateList(p, columns, function(row)
        row.inviteBtn = T.Button(row, "Einladen", 90, "primary")
        row.inviteBtn:SetHeight(19)
        row.inviteBtn:SetPoint("RIGHT", -4, 0)
        ns.Recruit:SetupInviteButton(row.inviteBtn, function(self)
            local d = self:GetParent().data
            return d and d.pending and d.name or nil
        end)
        row.dropBtn = T.Button(row, "Verwerfen", 90)
        row.dropBtn:SetHeight(19)
        row.dropBtn:SetPoint("RIGHT", row.inviteBtn, "LEFT", -6, 0)
        row.dropBtn:SetScript("OnClick", function(self) ns.Recruit:Decline(self:GetParent().data.name) end)
    end)
    list.panel:SetPoint("TOPLEFT", card, "TOPRIGHT", 12, -36)
    list.panel:SetPoint("BOTTOMRIGHT")

    function p:Refresh()
        local s = S()
        toggle:SetText(s.enabled and "Flüster-Einladung ist an" or "Flüster-Einladung ist aus")
        if not keywords:HasFocus() then keywords:SetText(s.keywords or "") end
        if not reply:HasFocus() then reply:SetText(s.reply or "") end

        local queue = ns.Recruit.queue
        if not IsInGuild() then
            p.summary:SetText(T.Hex("orange", "Du bist in keiner Gilde."))
        elseif not CanGuildInvite() then
            p.summary:SetText(T.Hex("orange", "Dein Gildenrang darf niemanden einladen."))
        else
            p.summary:SetText(#queue == 0 and T.Hex("muted", "Keine offenen Anfragen")
                or T.Hex("goldBright", #queue == 1 and "1 offene Anfrage" or (#queue .. " offene Anfragen")))
        end
        nextBtn:SetEnabled(#queue > 0)

        local rows, pending = {}, {}
        for _, q in ipairs(queue) do
            pending[q.key] = true
            table.insert(rows, { name = q.name, time = q.time, status = "angefragt", pending = true })
        end
        for _, e in ipairs(s.log) do
            if not pending[e.key] then table.insert(rows, e) end
        end

        list:SetData(rows, function(row, d)
            row.cols.name:SetText(ns.ShortName(d.name))
            row.cols.time:SetText(T.Hex("muted", date("%d.%m. %H:%M", d.time)))
            row.cols.status:SetText(T.Hex(RECRUIT_COLORS[d.status] or "cream", d.status))
            row.inviteBtn:SetShown(d.pending == true)
            row.dropBtn:SetShown(d.pending == true)
        end)
    end

    return p
end

-- Kleines Fenster, sobald jemand per Flüstern in die Gilde möchte
function UI:UpdateRecruitToast(focusName)
    local queue = ns.Recruit.queue
    local t = self.recruitToast
    if #queue == 0 then
        if t then t:Hide() end
        return
    end
    if not t then
        t = CreateFrame("Frame", "ElternabendGildenanfrage", UIParent, "BackdropTemplate")
        t:SetSize(420, 132)
        t:SetPoint("TOP", 0, -150)
        t:SetFrameStrata("DIALOG")
        t:SetMovable(true)
        t:SetClampedToScreen(true)
        t:EnableMouse(true)
        t:RegisterForDrag("LeftButton")
        t:SetScript("OnDragStart", t.StartMoving)
        t:SetScript("OnDragStop", t.StopMovingOrSizing)
        T.Backdrop(t, T.colors.navy, 0.97, 0.8)

        local kicker = T.Text(t, "kicker")
        kicker:SetPoint("TOPLEFT", 16, -12)
        kicker:SetText("GILDENANFRAGE · ELTERNABEND")
        t.name = T.Text(t, "heading")
        t.name:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -4)
        -- Befehl zum Kopieren: Addons dürfen weder einladen noch in die Eingabezeile schreiben
        -- noch in die Zwischenablage. Hier steht er markiert – Cmd/Strg+C, dann im Chat
        -- Enter, einfügen, Enter. Selbst eingefügt gilt er als selbst getippt.
        local copyKey = (IsMacClient and IsMacClient()) and "Cmd" or "Strg"
        t.cmdBox = T.EditBox(t, 270)
        t.cmdBox:SetPoint("TOPLEFT", t.name, "BOTTOMLEFT", 0, -8)
        t.cmdBox:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
        t.cmdBox:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        t.cmdBox:HookScript("OnTextChanged", function(self, userInput)
            if userInput then
                self:SetText(self.value or "")
                self:HighlightText()
            end
        end)
        -- Nach dem Kopieren den Fokus abgeben, damit Enter gleich den Chat öffnet
        t.cmdBox:SetScript("OnKeyUp", function(self, key)
            if key == "C" and (IsControlKeyDown() or (IsMetaKeyDown and IsMetaKeyDown())) then
                C_Timer.After(0, function() self:ClearFocus() end)
            end
        end)
        t.hint = T.Text(t, "muted")
        t.hint:SetPoint("BOTTOMLEFT", 16, 16)
        t.hint:SetWidth(270)
        t.hint:SetJustifyH("LEFT")
        t.hint:SetText("Ins Feld klicken, " .. copyKey .. "+C – dann Enter, " .. copyKey .. "+V, Enter")
        t.more = T.Text(t, "muted", "RIGHT")
        t.more:SetPoint("TOPRIGHT", -46, -12)

        local close = T.Button(t, "X", 24)
        close:SetHeight(24)
        close:SetPoint("TOPRIGHT", -10, -8)
        close:SetScript("OnClick", function()
            local q = ns.Recruit.queue
            t.dismissedKey = q[#q] and q[#q].key
            t:Hide()
        end)
        -- Ein „Einladen“-Knopf geht in WoW Forever nicht (siehe Recruit.lua) – der Befehl steht oben
        local drop = T.Button(t, "Verwerfen", 100)
        drop:SetPoint("BOTTOMRIGHT", -12, 12)
        drop:SetScript("OnClick", function()
            local q = ns.Recruit.queue[1]
            if q then ns.Recruit:Decline(q.name) end
        end)
        self.recruitToast = t
    end

    -- Geschlossen? Erst bei einer neuen Anfrage wieder zeigen (oder nach Klick auf „Einladen“)
    if focusName then t.dismissedKey = nil end
    if t.dismissedKey and queue[#queue].key == t.dismissedKey then return end
    t.dismissedKey = nil
    local target = focusName or queue[1].name
    t.name:SetText(ns.ShortName(target) .. " möchte in die Gilde")
    local cmd = ns.Recruit:Command(target)
    if t.cmdBox.value ~= cmd then
        t.cmdBox.value = cmd
        t.cmdBox:SetText(cmd)
        t.cmdBox:SetCursorPosition(0)
    end
    t.more:SetText(#queue > 1 and ("+" .. (#queue - 1) .. " weitere") or "")
    t:Show()
    -- Nach Klick auf „Einladen“ (Reiter Invite oder Taste): Befehl gleich markieren
    if focusName then
        t.cmdBox:SetFocus()
        t.cmdBox:HighlightText()
    end
end

ns:Listen("RECRUIT_COPY", function(name) UI:UpdateRecruitToast(name) end)

ns:Listen("RECRUIT_UPDATE", function()
    UI:UpdateRecruitToast()
    UI:QueueRefresh()
end)

-- Reiter: Gruppen (Gruppensuche in der Gilde) -----------------------------------------
function UI:CreateGroupsPanel()
    local p = self:NewPanel()
    local G = ns.Groups
    local rightWidth = 330
    local leftWidth = CONTENT_W - rightWidth - 12
    local SENT = { sent = { "gemeldet", "goldBright" }, invited = { "Einladung kommt", "green" }, full = { "schon voll", "red" } }

    -- Links: offene Gesuche der Gilde
    local list = CreateList(p, {
        { key = "who", label = "Wer", x = 4, w = 100 },
        { key = "what", label = "Wofür", x = 106, w = 190 },
        { key = "need", label = "Gesucht", x = 298, w = 130 },
        { key = "status", label = "Status", x = 430 },
    })
    list.panel:SetPoint("TOPLEFT")
    list.panel:SetPoint("BOTTOMRIGHT", -(rightWidth + 12), 76)
    list.onEnter = function(row, g)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.ShortName(g.leader) .. ": " .. g.what)
        GameTooltip:AddLine("Gesucht: " .. G.NeedText(g.need), 1, 1, 1)
        if g.note ~= "" then GameTooltip:AddLine("„" .. g.note .. "“", 1, 1, 1, true) end
        GameTooltip:AddLine("Seit " .. math.floor((GetTime() - g.started) / 60) .. " Minuten", 0.6, 0.6, 0.6)
        if g ~= G:Mine() then GameTooltip:AddLine("Klick: auswählen  ·  Rechtsklick: anflüstern", 0.84, 0.69, 0.35) end
        GameTooltip:Show()
    end
    list.onClick = function(_, g, button)
        if button == "RightButton" then
            if ChatFrame_SendTell then ChatFrame_SendTell(g.leader) elseif ChatFrameUtil and ChatFrameUtil.SendTell then ChatFrameUtil.SendTell(g.leader) end
        else
            p.selected = g.id
            p:Refresh()
        end
    end
    p.empty = T.Text(list.panel, "muted", "CENTER")
    p.empty:SetPoint("CENTER")
    p.empty:SetWidth(leftWidth - 60)
    p.empty:SetText("Gerade sucht niemand eine Gruppe. Trag rechts ein, wofür du Mitspieler suchst – die Gilde sieht es sofort.")

    -- Darunter: beim ausgewählten Gesuch melden
    p.joinButtons = {}
    local prev
    for _, role in ipairs({ "tank", "heal", "dd" }) do
        local b = T.Button(p, "Als " .. G.ROLES[role], 100)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 8, 0) else b:SetPoint("BOTTOMLEFT", 0, 40) end
        b:SetScript("OnClick", function() if p.selected then G:Join(p.selected, role) end end)
        p.joinButtons[role] = b
        prev = b
    end
    p.selText = T.Text(p, "small")
    p.selText:SetPoint("LEFT", prev, "RIGHT", 12, 0)
    p.selText:SetPoint("RIGHT", list.panel, "RIGHT")
    p.selText:SetWordWrap(false)

    local siteLabel = T.Text(p, "muted")
    siteLabel:SetPoint("BOTTOMLEFT", 2, 8)
    siteLabel:SetText("Dungeonfinder auf der Webseite:")
    local site = LinkBox(p, G.WEBSITE, leftWidth - 210)
    site:SetPoint("LEFT", siteLabel, "RIGHT", 10, 0)

    -- Rechts oben: eigene Gruppe suchen
    local own = StartCard(p, "Gruppe suchen", 232)
    own:SetPoint("TOPRIGHT")
    own:SetWidth(rightWidth)
    local inner = rightWidth - 32
    p.what = T.EditBox(own, inner, "Wofür? z. B. „Barrow Deeps“")
    p.what:SetPoint("TOPLEFT", 16, -30)
    p.need = { tank = 1, heal = 1, dd = 3 }
    local MAX = { tank = 2, heal = 3, dd = 9 }
    p.needButtons = {}
    prev = nil
    for _, role in ipairs({ "tank", "heal", "dd" }) do
        local b = T.Button(own, "", (inner - 16) / 3)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 8, 0) else b:SetPoint("TOPLEFT", p.what, "BOTTOMLEFT", 0, -8) end
        b:SetScript("OnClick", function(_, button)
            local n = p.need[role] + (button == "RightButton" and -1 or 1)
            if n > MAX[role] then n = 0 elseif n < 0 then n = MAX[role] end
            p.need[role] = n
            p:Refresh()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine("Klick: mehr  ·  Rechtsklick: weniger")
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        p.needButtons[role] = b
        prev = b
    end
    p.note = T.EditBox(own, inner, "Notiz, z. B. „gemütlich, mit Erklärung“")
    p.note:SetPoint("TOPLEFT", p.needButtons.tank, "BOTTOMLEFT", 0, -8)
    -- Für Mitglieder ohne Addon: Gesuch einmal in den Gildenchat schreiben (Wahl wird gemerkt)
    p.toChat = T.Checkbox(own, "Auch im Gildenchat posten")
    p.toChat:SetPoint("TOPLEFT", p.note, "BOTTOMLEFT", 0, -8)
    p.toChat:SetChecked(ns.db.groups.chat)
    p.toChat.onChange = function(checked) ns.db.groups.chat = checked end
    p.toChat:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Auch im Gildenchat posten")
        GameTooltip:AddLine("Beim Start einmal: „Suche Gruppe für … Mit Addon über /ea gruppen melden, sonst anflüstern!“ – so sehen es auch Mitglieder ohne Addon.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p.toChat:SetScript("OnLeave", GameTooltip_Hide)
    p.post = T.Button(own, "Gruppe suchen", 170, "primary")
    p.post:SetPoint("TOPLEFT", p.toChat, "BOTTOMLEFT", 0, -8)
    p.post:SetScript("OnClick", function()
        p.what:ClearFocus()
        p.note:ClearFocus()
        G:Post(p.what:GetText(), p.need, p.note:GetText())
    end)
    p.close = T.Button(own, "Beenden", inner - 178)
    p.close:SetPoint("LEFT", p.post, "RIGHT", 8, 0)
    p.close:SetScript("OnClick", function() G:Close() end)
    p.ownState = T.Text(own, "muted")
    p.ownState:SetPoint("TOPLEFT", p.post, "BOTTOMLEFT", 0, -10)
    p.ownState:SetWidth(inner)
    p.ownState:SetWordWrap(false)

    -- Rechts unten: wer möchte mit?
    local apps = StartCard(p, "Meldungen", 0)
    apps:SetPoint("TOPRIGHT", own, "BOTTOMRIGHT", 0, -10)
    apps:SetPoint("BOTTOMRIGHT")
    apps:SetWidth(rightWidth)
    p.appsHint = T.Text(apps, "muted")
    p.appsHint:SetPoint("TOPLEFT", apps.kicker, "BOTTOMLEFT", 0, -6)
    p.appsHint:SetWidth(inner)
    p.appsHint:SetSpacing(3)
    p.appRows = {}
    local APP_H = 30
    local function AppRow(i)
        local row = CreateFrame("Frame", nil, apps)
        row:SetPoint("TOPLEFT", 16, -28 - (i - 1) * APP_H)
        row:SetPoint("TOPRIGHT", -16, -28 - (i - 1) * APP_H)
        row:SetHeight(APP_H)
        row.text = T.Text(row, "small")
        row.text:SetPoint("LEFT")
        row.text:SetPoint("RIGHT", -150, 0)
        row.text:SetWordWrap(false)
        row.no = T.Button(row, "Absagen", 70)
        row.no:SetHeight(20)
        row.no:SetPoint("RIGHT")
        row.yes = T.Button(row, "Einladen", 74, "primary")
        row.yes:SetHeight(20)
        row.yes:SetPoint("RIGHT", row.no, "LEFT", -6, 0)
        p.appRows[i] = row
        return row
    end

    function p:Refresh()
        local mine = G:Mine()
        local groups = G:List()
        if not p.selected or not G.list[p.selected] then
            p.selected = nil
            for _, g in ipairs(groups) do
                if g ~= mine then p.selected = g.id; break end
            end
        end
        p.empty:SetShown(#groups == 0)
        list:SetData(groups, function(row, g)
            local selected = g.id == p.selected
            row.cols.who:SetText((selected and T.Hex("goldBright", "» ") or "") .. ns.ShortName(g.leader))
            -- Notiz dezent hinter dem Ziel; zu lang wird sie gekürzt, im Tooltip steht sie ganz
            row.cols.what:SetText(T.Hex("goldBright", g.what) .. (g.note ~= "" and T.Hex("muted", "  ·  " .. g.note) or ""))
            row.cols.need:SetText(G.NeedText(g.need))
            local sent = G.sent[g.id]
            if g == mine then
                row.cols.status:SetText(T.Hex("green", "deine Gruppe"))
            elseif sent and SENT[sent.state] then
                row.cols.status:SetText(T.Hex(SENT[sent.state][2], SENT[sent.state][1]))
            else
                row.cols.status:SetText(T.Hex("muted", math.floor((GetTime() - g.started) / 60) .. " Min"))
            end
        end)

        local sel = p.selected and G.list[p.selected]
        -- Beim eigenen Gesuch kann man sich nicht melden: Knöpfe aus, kurzer Hinweis
        local own = sel ~= nil and sel == mine
        for role, b in pairs(p.joinButtons) do
            b:SetEnabled(sel ~= nil and not own and sel.need[role] > 0)
        end
        if own then
            p.selText:SetText(T.Hex("muted", "Das ist dein eigenes Gesuch."))
        else
            p.selText:SetText(sel and ("bei " .. T.Hex("goldBright", ns.ShortName(sel.leader)) .. ": " .. sel.what)
                or T.Hex("muted", "Erst oben ein Gesuch anklicken."))
        end

        for role, b in pairs(p.needButtons) do b:SetText(G.ROLES[role] .. ": " .. p.need[role]) end
        p.post:SetText(mine and "Aktualisieren" or "Gruppe suchen")
        p.close:SetEnabled(mine ~= nil)
        local applicants = G:Applicants()
        if mine then
            p.ownState:SetText(T.Hex("green", "Läuft") .. "  ·  seit " .. math.floor((GetTime() - mine.started) / 60) ..
                " Min  ·  noch " .. G.NeedText(mine.need))
        else
            p.ownState:SetText("Die Gilde sieht dein Gesuch sofort.")
        end

        p.appsHint:SetShown(#applicants == 0)
        p.appsHint:SetText(mine and "Noch hat sich niemand gemeldet." or
            "Wer sich auf dein Gesuch meldet, steht hier – mit Knopf zum Einladen.")
        local maxRows = 6
        for i = 1, math.max(#applicants, #p.appRows) do
            local a = applicants[i]
            local row = p.appRows[i] or (a and i <= maxRows and AppRow(i))
            if row then
                row:SetShown(a ~= nil and i <= maxRows)
                if a and i <= maxRows then
                    local state = a.state == "invited" and T.Hex("green", "  eingeladen")
                        or (a.state == "declined" and T.Hex("dim", "  abgesagt") or "")
                    row.text:SetText("|c" .. ClassHex(a.classFile ~= "" and a.classFile or nil) .. ns.ShortName(a.name) .. "|r  " ..
                        T.Hex("muted", G.ROLES[a.role]) .. state)
                    row.yes:SetEnabled(a.state == "new")
                    row.no:SetEnabled(a.state == "new")
                    row.yes:SetScript("OnClick", function() G:Invite(a) end)
                    row.no:SetScript("OnClick", function() G:Decline(a) end)
                end
            end
        end
    end

    -- Laufzeiten aktuell halten, solange der Reiter offen ist
    local elapsed = 0
    p:SetScript("OnUpdate", function(_, e)
        elapsed = elapsed + e
        if elapsed > 15 then
            elapsed = 0
            p:Refresh()
        end
    end)

    return p
end

-- Reiter: Berufe ---------------------------------------------------------------
-- Flüsterfenster an einen Spieler öffnen
local function Whisper(name)
    if ChatFrame_SendTell then
        ChatFrame_SendTell(name)
    elseif ChatFrameUtil and ChatFrameUtil.SendTell then
        ChatFrameUtil.SendTell(name)
    end
end

function UI:CreateProfessionsPanel()
    local p = self:NewPanel()
    local P, M = ns.Professions, ns.Members
    local rightWidth = 330
    local leftWidth = CONTENT_W - rightWidth - 12

    local FILTER_W, VIEW_W = 180, 136
    local search = T.EditBox(p, leftWidth - FILTER_W - VIEW_W - 16, "Rezept oder Gegenstand suchen …")
    T.AddClearButton(search)
    search:SetPoint("TOPLEFT", 0, 0)
    search:HookScript("OnTextChanged", function(_, userInput)
        if userInput then p.detailRecipe = nil end
        p:Refresh()
    end)

    -- Filter nach Beruf: zeigt nur Charaktere (bzw. Rezepte) mit diesem Beruf
    p.profFilter = nil
    local filterBtn = T.Button(p, "Alle Berufe", FILTER_W)
    filterBtn:SetPoint("LEFT", search, "RIGHT", 8, 0)
    local menu = T.Panel(p)
    menu:SetFrameStrata("DIALOG")
    menu:SetPoint("TOPLEFT", filterBtn, "BOTTOMLEFT", 0, -2)
    menu:SetWidth(FILTER_W)
    menu:EnableMouse(true)
    menu:Hide()
    menu.buttons = {}
    local function KnownProfessions()
        local count = {}
        for key, c in pairs(ns.db.professions) do
            if #M.list == 0 or M.byKey[key] then
                for _, pr in ipairs(c.profs) do
                    if pr.name then count[pr.name] = (count[pr.name] or 0) + 1 end
                end
            end
        end
        local names = {}
        for n in pairs(count) do table.insert(names, n) end
        table.sort(names)
        return names, count
    end
    local function OpenMenu()
        local names, count = KnownProfessions()
        local entries = { { label = "Alle Berufe" } }
        for _, n in ipairs(names) do table.insert(entries, { label = n .. "  (" .. count[n] .. ")", value = n }) end
        for i, e in ipairs(entries) do
            local b = menu.buttons[i]
            if not b then
                b = T.Button(menu, "", FILTER_W - 12)
                b:SetHeight(22)
                b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 24)
                menu.buttons[i] = b
            end
            b:SetText(e.value == p.profFilter and T.Hex("goldBright", e.label) or e.label)
            b:SetScript("OnClick", function()
                p.profFilter = e.value
                p.detail, p.detailRecipe = nil, nil -- zurück zur Übersicht mit allen, die diesen Beruf haben
                menu:Hide()
                p:Refresh()
            end)
            b:Show()
        end
        for i = #entries + 1, #menu.buttons do menu.buttons[i]:Hide() end
        menu:SetHeight(10 + #entries * 24)
        menu:Show()
    end
    filterBtn:SetScript("OnClick", function()
        if menu:IsShown() then menu:Hide() else OpenMenu() end
    end)

    -- Ansicht umschalten: nach Personen (wer hat welche Berufe) oder nach Rezepten (wer kann was)
    p.byRecipe = false
    local viewBtn = T.Button(p, "Nach Rezepten", VIEW_W)
    viewBtn:SetPoint("LEFT", filterBtn, "RIGHT", 8, 0)
    viewBtn:SetScript("OnClick", function()
        p.byRecipe = not p.byRecipe
        p.detail, p.detailRecipe = nil, nil
        menu:Hide()
        p:Refresh()
    end)
    p:HookScript("OnHide", function() menu:Hide() end)

    local function Online(key)
        local m = M.byKey[key]
        local main = m and (m.main or m)
        if m and m.online then return T.Hex("green", "online") end
        if main and main.onlineAs then return T.Hex("green", "als " .. main.onlineAs.display) end
        return ""
    end

    -- Tooltip zu einem Rezept: hergestellter Gegenstand wie im Spiel, sonst der Zauber; dazu Materialien
    local function RecipeTooltip(owner, id, crafters, hint)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        local sch = P:Schematic(id)
        if sch and sch.item and GameTooltip.SetItemByID then
            GameTooltip:SetItemByID(sch.item)
        elseif GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(id)
        else
            GameTooltip:AddLine(P:RecipeName(id) or ("Rezept " .. id))
        end
        if sch and #sch.reagents > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Materialien", 0.84, 0.69, 0.35)
            for _, r in ipairs(sch.reagents) do
                GameTooltip:AddLine(r[2] .. "× " .. (P:ItemName(r[1]) or ("Gegenstand " .. r[1])), 1, 1, 1)
            end
        end
        if crafters and #crafters > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Hergestellt von", 0.84, 0.69, 0.35)
            GameTooltip:AddLine(crafters, 1, 1, 1, true)
        end
        if hint then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(hint, 0.84, 0.69, 0.35)
        end
        GameTooltip:Show()
    end

    -- Suchergebnisse: wer kann das herstellen?
    local hitList = CreateList(p, {
        { key = "recipe", label = "Rezept", x = 4, w = 300 },
        { key = "char", label = "Wer kann es?", x = 306, w = 160 },
        { key = "prof", label = "Beruf", x = 468, w = 130 },
        { key = "status", label = "Status", x = 600 },
    })
    hitList.panel:SetPoint("TOPLEFT", 0, -36)
    hitList.panel:SetPoint("BOTTOMRIGHT", -(rightWidth + 12), 30)
    hitList.onEnter = function(row, h)
        RecipeTooltip(row, h.id, nil, "Klick: Auftrag an " .. ns.ShortName(h.char) .. "  ·  Rechtsklick: anflüstern")
    end
    hitList.onClick = function(_, h, button)
        if button == "RightButton" then
            Whisper(h.char)
        elseif ns.db.professions[h.key] and ns.db.professions[h.key].mine then
            ns.Print("Das ist dein eigener Charakter.")
        else
            UI:TextDialog("Auftrag an " .. ns.ShortName(h.char),
                "Rezept: " .. h.recipe .. "\nSchreib eine kurze Notiz dazu, z. B. „Mats habe ich“ oder „eilt nicht“ – oder lass das Feld leer.",
                "", function(note)
                    ns.Orders:Send(h.char, h.id, ((note or ""):gsub("[\r\n]+", " ")))
                end, "Auftrag schicken")
        end
    end

    -- Ohne Suche: Übersicht, wer welche Berufe hat
    local allList = CreateList(p, {
        { key = "char", label = "Charakter", x = 4, w = 160 },
        { key = "profs", label = "Berufe", x = 166, w = 452 },
        { key = "status", label = "Status", x = 620 },
    })
    allList.panel:SetPoint("TOPLEFT", 0, -36)
    allList.panel:SetPoint("BOTTOMRIGHT", -(rightWidth + 12), 30)
    allList.onEnter = function(row, c)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.ShortName(c.name))
        for _, pr in ipairs(c.profs) do
            GameTooltip:AddLine(pr.name .. " " .. (pr.level or "?") .. "/" .. (pr.max or "?") .. "  ·  " .. #(pr.recipes or {}) .. " Rezepte", 1, 1, 1)
        end
        if c.time then GameTooltip:AddLine("Stand " .. date("%d.%m. %H:%M", c.time) .. (c.from and (" von " .. c.from) or ""), 0.6, 0.6, 0.6) end
        GameTooltip:AddLine("Klick: Rezepte anzeigen  ·  Rechtsklick: anflüstern", 0.84, 0.69, 0.35)
        GameTooltip:Show()
    end
    allList.onClick = function(_, c, button)
        if button == "RightButton" then
            Whisper(c.name)
        else
            p.detail = c.key
            p:Refresh()
        end
    end

    -- Nach Rezepten: jedes Rezept einmal, daneben alle, die es herstellen können
    local recipeList = CreateList(p, {
        { key = "recipe", label = "Rezept", x = 4, w = 290 },
        { key = "who", label = "Wer kann es?", x = 296, w = 320 },
        { key = "prof", label = "Beruf", x = 620 },
    })
    recipeList.panel:SetPoint("TOPLEFT", 0, -36)
    recipeList.panel:SetPoint("BOTTOMRIGHT", -(rightWidth + 12), 30)
    recipeList.onEnter = function(row, r)
        RecipeTooltip(row, r.id, r.whoText, "Klick: alle Hersteller mit Auftrag  ·  Rechtsklick: " .. (r.firstOnline and (ns.ShortName(r.firstOnline) .. " anflüstern") or "anflüstern"))
    end
    recipeList.onClick = function(_, r, button)
        if button == "RightButton" then
            Whisper(r.firstOnline or r.crafters[1].name)
        else
            p.detailRecipe = r.id
            p:Refresh()
        end
    end

    -- Unten: zurück zur Übersicht (nur in der Rezeptliste eines Charakters) und Zusammenfassung
    local back = T.Button(p, "« Alle Berufe", 120)
    back:SetPoint("BOTTOMLEFT", 0, 0)
    back:SetScript("OnClick", function()
        p.detail, p.detailRecipe = nil, nil
        p:Refresh()
    end)
    p.summary = T.Text(p, "muted")

    -- Rechts: eigene Berufe und Erklärung
    local mine = StartCard(p, "Meine Berufe", 214)
    mine:SetPoint("TOPRIGHT")
    mine:SetWidth(rightWidth)
    p.mine = T.Text(mine, "small")
    p.mine:SetPoint("TOPLEFT", mine.kicker, "BOTTOMLEFT", 0, -6)
    p.mine:SetWidth(rightWidth - 32)
    p.mine:SetSpacing(3)
    local export = T.Button(mine, "Für die Webseite exportieren", rightWidth - 32)
    export:SetPoint("BOTTOMLEFT", 16, 12)
    local ask = T.Button(mine, "Berufe der Gilde neu anfragen", rightWidth - 32)
    ask:SetPoint("BOTTOMLEFT", export, "TOPLEFT", 0, 8)
    ask:SetScript("OnClick", function() P:RequestAll() end)

    -- Export: Addons dürfen nicht in die Zwischenablage schreiben, also markiert
    -- ins Feld legen – Strg+C bzw. Cmd+C, dann auf der Webseite einfügen
    local box = T.Panel(p)
    box:SetFrameStrata("DIALOG")
    box:SetSize(560, 168)
    box:SetPoint("CENTER", p, "CENTER", 0, 40)
    box:EnableMouse(true)
    box:Hide()
    box.kicker = T.Text(box, "kicker")
    box.kicker:SetPoint("TOPLEFT", 16, -14)
    box.kicker:SetText("EXPORT FÜR DIE WEBSEITE")
    box.info = T.Text(box, "small")
    box.info:SetPoint("TOPLEFT", box.kicker, "BOTTOMLEFT", 0, -8)
    box.info:SetWidth(528)
    box.info:SetSpacing(3)
    box.edit = T.EditBox(box, 528)
    box.edit:SetPoint("TOPLEFT", 16, -88)
    box.edit:SetMaxLetters(0)
    box.edit:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box.edit:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    box.edit:HookScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(box.value or "")
            self:HighlightText()
        end
    end)
    local close = T.Button(box, "Schließen", 120)
    close:SetPoint("BOTTOMRIGHT", -16, 14)
    close:SetScript("OnClick", function() box:Hide() end)
    p:HookScript("OnHide", function() box:Hide() end)
    export:SetScript("OnClick", function()
        if export.busy then return end
        local only
        if #M.list > 0 then only = M.byKey end
        export.busy = true
        export:SetText("Gegenstände werden geladen …")
        P:PrepareExport(only, function(ready, total)
            export:SetText("Gegenstände werden geladen … " .. ready .. "/" .. total)
        end, function(text, count)
            export.busy = false
            export:SetText("Für die Webseite exportieren")
            box.value = text
            box.info:SetText(count .. (count == 1 and " Beruf" or " Berufe") .. " von Gildenmitgliedern, mit Werten und Materialien. "
                .. "Text kopieren (Strg+C bzw. Cmd+C) und auf " .. T.Hex("goldBright", "gilde-elternabend.de/berufe.php")
                .. " unter „Aus dem Addon importieren“ einfügen.")
            box.edit:SetText(text)
            box.edit:SetCursorPosition(0)
            box:Show()
            box.edit:SetFocus()
            box.edit:HighlightText()
        end)
    end)

    -- Aufträge: an mich (mit Knöpfen) und von mir
    local orders = StartCard(p, "Aufträge", 0)
    orders:SetPoint("TOPRIGHT", mine, "BOTTOMRIGHT", 0, -10)
    orders:SetPoint("BOTTOMRIGHT")
    orders:SetWidth(rightWidth)
    p.ordersHint = T.Text(orders, "muted")
    p.ordersHint:SetPoint("TOPLEFT", orders.kicker, "BOTTOMLEFT", 0, -6)
    p.ordersHint:SetWidth(rightWidth - 32)
    p.ordersHint:SetSpacing(3)
    p.ordersHint:SetText("Klick auf ein Rezept schickt dem Hersteller einen Auftrag, Rechtsklick öffnet ein Flüsterfenster.\n\n" ..
        "Damit deine Rezepte in der Liste stehen, öffne einmal dein Berufsfenster. Du siehst nur Rezepte von Mitgliedern mit Addon.")
    p.orderRows = {}
    local ORDER_H = 44
    local function OrderRow(i)
        local row = CreateFrame("Frame", nil, orders)
        row:SetPoint("TOPLEFT", 16, -28 - (i - 1) * ORDER_H)
        row:SetPoint("TOPRIGHT", -16, -28 - (i - 1) * ORDER_H)
        row:SetHeight(ORDER_H)
        row.text = T.Text(row, "small")
        row.text:SetPoint("TOPLEFT", 0, -4)
        row.text:SetPoint("RIGHT")
        row.text:SetWordWrap(false)
        row.state = T.Text(row, "muted")
        row.state:SetPoint("TOPLEFT", 0, -22)
        row.state:SetPoint("RIGHT", -150, 0)
        row.state:SetWordWrap(false)
        row.b2 = T.Button(row, "", 72)
        row.b2:SetHeight(20)
        row.b2:SetPoint("TOPRIGHT", 0, -19)
        row.b1 = T.Button(row, "", 72)
        row.b1:SetHeight(20)
        row.b1:SetPoint("RIGHT", row.b2, "LEFT", -6, 0)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            local o = self.order
            if not o then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(o.recipeId) else GameTooltip:AddLine(o.recipe or "") end
            if o.note ~= "" then GameTooltip:AddLine("„" .. o.note .. "“", 1, 1, 1, true) end
            GameTooltip:AddLine(date("%d.%m. %H:%M", o.time), 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        local line = row:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT")
        line:SetColorTexture(T.colors.gold[1], T.colors.gold[2], T.colors.gold[3], 0.15)
        p.orderRows[i] = row
        return row
    end
    local function SetButton(b, label, fn)
        b:SetShown(label ~= nil)
        if label then
            b:SetText(label)
            b:SetScript("OnClick", fn)
        end
    end
    function p:RefreshOrders()
        local O = ns.Orders
        local rows = {}
        for _, o in ipairs(O:Incoming()) do table.insert(rows, { o = o, inc = true }) end
        for _, o in ipairs(O:Outgoing()) do table.insert(rows, { o = o }) end
        local maxRows = 5
        p.ordersHint:SetShown(#rows == 0)
        for i = 1, math.max(#rows, #p.orderRows) do
            local r = rows[i]
            local row = p.orderRows[i] or (r and i <= maxRows and OrderRow(i))
            if row then
                row:SetShown(r ~= nil and i <= maxRows)
                if r and i <= maxRows then
                    local o = r.o
                    row.order = o
                    local st = O.STATES[o.state] or { o.state, "muted" }
                    local recipe = T.Hex("goldBright", o.recipe or ("Rezept " .. o.recipeId))
                    if r.inc then
                        row.text:SetText(ns.ShortName(o.from) .. " » " .. recipe)
                        row.state:SetText("an dich  ·  " .. T.Hex(st[2], st[1]))
                        if o.state == "neu" then
                            SetButton(row.b1, "Annehmen", function() O:SetState(o.id, "angenommen") end)
                            SetButton(row.b2, "Ablehnen", function() O:SetState(o.id, "abgelehnt") end)
                        elseif o.state == "angenommen" then
                            SetButton(row.b1, "Flüstern", function() Whisper(o.from) end)
                            SetButton(row.b2, "Fertig", function() O:SetState(o.id, "fertig") end)
                        else
                            SetButton(row.b1, nil)
                            SetButton(row.b2, "Weg", function() O:Remove(o.id) end)
                        end
                    else
                        row.text:SetText("Du » " .. ns.ShortName(o.crafter) .. ": " .. recipe)
                        row.state:SetText(T.Hex(st[2], st[1]))
                        local done = o.state == "fertig" or o.state == "abgelehnt"
                        SetButton(row.b1, (o.state == "fertig" or o.state == "angenommen") and "Flüstern" or nil,
                            function() Whisper(o.crafter) end)
                        SetButton(row.b2, done and "Weg" or "Zurück", function() O:Cancel(o.id) end)
                    end
                end
            end
        end
        orders.kicker:SetText(#rows > maxRows and ("AUFTRÄGE  ·  " .. #rows .. " INSGESAMT, " .. maxRows .. " GEZEIGT") or "AUFTRÄGE")
    end

    function p:Refresh()
        -- Eigene Berufe (alle Charaktere dieses Accounts)
        local lines = {}
        for _, c in pairs(ns.db.professions) do
            if c.mine then
                local profs = {}
                for _, pr in ipairs(c.profs) do table.insert(profs, pr.name) end
                table.insert(lines, T.Hex("goldBright", ns.ShortName(c.name)) .. ": " .. table.concat(profs, ", "))
            end
        end
        table.sort(lines)
        p.mine:SetText(#lines > 0 and table.concat(lines, "\n")
            or T.Hex("orange", "Noch keine Berufe erfasst – öffne einmal dein Berufsfenster."))

        local chars, recipes = P:Count()
        local summary = chars .. " Charaktere  ·  " .. recipes .. " Rezepte bekannt"
        for _, t in ipairs({ "PROF2", "PROF" }) do
            for _, e in ipairs(ns.Comm:Progress(t)) do
                summary = summary .. "  ·  " .. T.Hex("goldBright", string.format("empfange %s: %d von %d",
                    ns.ShortName(e.sender), e.got, e.total))
            end
        end
        p.summary:SetText(summary)
        p:RefreshOrders()

        local filter = p.profFilter
        filterBtn:SetText(filter and T.Hex("goldBright", filter) or "Alle Berufe")

        viewBtn:SetText(p.byRecipe and T.Hex("goldBright", "Nach Rezepten") or "Nach Personen")
        local text = strtrim(search:GetText() or "")
        local searching = text ~= ""
        local detail = not p.byRecipe and not searching and p.detail and ns.db.professions[p.detail] or nil
        if not detail then p.detail = nil end
        local recipeDetail = p.byRecipe and p.detailRecipe or nil
        local recipeView = p.byRecipe and not recipeDetail
        hitList.panel:SetShown(not recipeView and (searching or detail ~= nil or recipeDetail ~= nil))
        allList.panel:SetShown(not p.byRecipe and not searching and not detail)
        recipeList.panel:SetShown(recipeView)
        back:SetText(recipeDetail and "« Alle Rezepte" or "« Alle Berufe")
        back:SetShown((detail or recipeDetail) and true or false)
        p.summary:ClearAllPoints()
        if detail or recipeDetail then p.summary:SetPoint("LEFT", back, "RIGHT", 12, 0) else p.summary:SetPoint("BOTTOMLEFT", 2, 8) end

        local function Colored(id, name)
            local hex = P:RecipeColor(id)
            return hex and (hex .. name .. "|r") or T.Hex("goldBright", name)
        end
        local function IsOnline(key)
            local m = M.byKey[key]
            local main = m and (m.main or m)
            return (m and m.online) or (main and main.onlineAs) and true or false
        end

        if recipeView then
            -- Alle Rezepte der Gilde (gefiltert nach Beruf und Suchtext), je Rezept alle Hersteller
            local byId, rows = {}, {}
            local needle = ns.Lower(text)
            for key, c in pairs(ns.db.professions) do
                if #M.list == 0 or M.byKey[key] then
                    for _, pr in ipairs(c.profs) do
                        if not filter or pr.name == filter then
                            for _, id in ipairs(pr.recipes or {}) do
                                local name = P:RecipeName(id)
                                if name and (needle == "" or ns.Lower(name):find(needle, 1, true)) then
                                    local r = byId[id]
                                    if not r then
                                        r = { id = id, recipe = name, prof = pr.name, crafters = {} }
                                        byId[id] = r
                                        table.insert(rows, r)
                                    end
                                    table.insert(r.crafters, { name = c.name, key = key, online = IsOnline(key) })
                                end
                            end
                        end
                    end
                end
            end
            for _, r in ipairs(rows) do
                table.sort(r.crafters, function(a, b)
                    if a.online ~= b.online then return a.online end
                    return a.name < b.name
                end)
                local parts = {}
                for _, cr in ipairs(r.crafters) do
                    if cr.online and not r.firstOnline then r.firstOnline = cr.name end
                    table.insert(parts, cr.online and T.Hex("green", ns.ShortName(cr.name)) or ns.ShortName(cr.name))
                end
                r.who = table.concat(parts, ", ")
                r.whoText = r.who
            end
            table.sort(rows, function(a, b)
                if a.prof ~= b.prof then return a.prof < b.prof end
                return a.recipe < b.recipe
            end)
            recipeList:SetData(rows, function(row, r)
                row.cols.recipe:SetText(Colored(r.id, r.recipe))
                row.cols.who:SetText(r.who)
                row.cols.prof:SetText(T.Hex("muted", r.prof))
            end)
            p.summary:SetText(#rows == 0 and T.Hex("orange", "Kein passendes Rezept gefunden.")
                or (#rows .. (#rows == 1 and " Rezept" or " Rezepte") .. (filter and (" in " .. T.Hex("goldBright", filter)) or "")
                    .. "  ·  " .. T.Hex("green", "grün") .. " = online  ·  Klick zeigt alle Hersteller"))
        elseif recipeDetail then
            -- Alle Hersteller eines Rezepts, mit Auftrag per Klick
            local rows, name = {}, P:RecipeName(recipeDetail) or ("Rezept " .. recipeDetail)
            for key, c in pairs(ns.db.professions) do
                if #M.list == 0 or M.byKey[key] then
                    for _, pr in ipairs(c.profs) do
                        for _, id in ipairs(pr.recipes or {}) do
                            if id == recipeDetail then
                                table.insert(rows, { recipe = name, id = id, char = c.name, key = key, prof = pr.name, online = IsOnline(key) })
                            end
                        end
                    end
                end
            end
            table.sort(rows, function(a, b)
                if a.online ~= b.online then return a.online end
                return a.char < b.char
            end)
            hitList:SetData(rows, function(row, h)
                local m = M.byKey[h.key]
                row.cols.recipe:SetText(Colored(h.id, h.recipe))
                row.cols.char:SetText(m and ("|c" .. ClassHex(m.classFile) .. ns.ShortName(h.char) .. "|r") or ns.ShortName(h.char))
                row.cols.prof:SetText(T.Hex("muted", h.prof))
                row.cols.status:SetText(Online(h.key))
            end)
            p.summary:SetText(Colored(recipeDetail, name) .. "  ·  " .. #rows .. (#rows == 1 and " Hersteller" or " Hersteller") .. "  ·  Klick schickt einen Auftrag")
        elseif detail then
            -- Alle Rezepte eines Charakters, nach Beruf und Name
            local rows = {}
            for _, pr in ipairs(detail.profs) do
                for _, id in ipairs((not filter or pr.name == filter) and pr.recipes or {}) do
                    table.insert(rows, { recipe = P:RecipeName(id) or ("Rezept " .. id), id = id, char = detail.name, key = p.detail, prof = pr.name })
                end
            end
            table.sort(rows, function(a, b)
                if a.prof ~= b.prof then return a.prof < b.prof end
                return a.recipe < b.recipe
            end)
            hitList:SetData(rows, function(row, h)
                row.cols.recipe:SetText(T.Hex("goldBright", h.recipe))
                row.cols.char:SetText(ns.ShortName(h.char))
                row.cols.prof:SetText(T.Hex("muted", h.prof))
                row.cols.status:SetText(Online(h.key))
            end)
            p.summary:SetText("Rezepte von " .. T.Hex("goldBright", ns.ShortName(detail.name)) .. "  ·  " .. #rows .. " Rezepte")
        elseif searching then
            local hits = P:Search(text, 200)
            if filter then
                local only = {}
                for _, h in ipairs(hits) do if h.prof == filter then table.insert(only, h) end end
                hits = only
            end
            hitList:SetData(hits, function(row, h)
                local m = M.byKey[h.key]
                row.cols.recipe:SetText(T.Hex("goldBright", h.recipe))
                row.cols.char:SetText(m and ("|c" .. ClassHex(m.classFile) .. ns.ShortName(h.char) .. "|r") or ns.ShortName(h.char))
                row.cols.prof:SetText(T.Hex("muted", h.prof))
                row.cols.status:SetText(Online(h.key))
            end)
            if #hits == 0 then
                p.summary:SetText(T.Hex("orange", "Niemand gefunden, der „" .. text .. "“ herstellen kann"
                    .. (filter and (" (" .. filter .. ")") or "") .. "."))
            end
        else
            local rows = {}
            for key, c in pairs(ns.db.professions) do
                if #c.profs > 0 and (#M.list == 0 or M.byKey[key]) then
                    local match
                    for _, pr in ipairs(c.profs) do if pr.name == filter then match = pr end end
                    if not filter or match then
                        table.insert(rows, { key = key, name = c.name, profs = c.profs, time = c.time, from = c.from, match = match })
                    end
                end
            end
            -- Mit Filter: höchste Stufe zuerst, sonst alphabetisch
            table.sort(rows, function(a, b)
                local la, lb = a.match and a.match.level or 0, b.match and b.match.level or 0
                if la ~= lb then return la > lb end
                return a.name < b.name
            end)
            allList:SetData(rows, function(row, c)
                local m = M.byKey[c.key]
                row.cols.char:SetText(m and ("|c" .. ClassHex(m.classFile) .. ns.ShortName(c.name) .. "|r") or ns.ShortName(c.name))
                local names = {}
                if c.match then
                    local pr = c.match
                    table.insert(names, T.Hex("goldBright", pr.name .. " " .. (pr.level or "?") .. "/" .. (pr.max or "?"))
                        .. T.Hex("muted", "  ·  " .. #(pr.recipes or {}) .. " Rezepte"))
                end
                for _, pr in ipairs(c.profs) do
                    if pr ~= c.match then table.insert(names, c.match and T.Hex("muted", pr.name) or pr.name) end
                end
                row.cols.profs:SetText(table.concat(names, c.match and "  ·  " or ", "))
                row.cols.status:SetText(Online(c.key))
            end)
            if filter then
                p.summary:SetText(#rows == 0 and T.Hex("orange", "Niemand mit " .. filter .. " gefunden.")
                    or (#rows .. (#rows == 1 and " Charakter" or " Charaktere") .. " mit " .. T.Hex("goldBright", filter)
                        .. "  ·  Klick auf einen Namen zeigt seine Rezepte"))
            end
        end
    end

    return p
end

-- Reiter: Notizen -------------------------------------------------------------
function UI:CreateNotesPanel()
    local p = self:NewPanel()
    local function Current() return ns.Notes:Get(p.selected) end

    local new = T.Button(p, "Neue Notiz", 130, "primary")
    new:SetPoint("TOPLEFT")
    new:SetScript("OnClick", function()
        local n = ns.Notes:New()
        p.selected = n.id
        p:Refresh()
        p.title:SetFocus()
        p.title:HighlightText()
    end)
    local del = T.Button(p, "Löschen", 110)
    del:SetPoint("LEFT", new, "RIGHT", 8, 0)
    del:SetScript("OnClick", function()
        local n = Current()
        if n then StaticPopup_Show("ELTERNABEND_DELETE_NOTE", n.title, nil, n.id) end
    end)

    local list = CreateList(p, { { key = "title", label = "Notiz", x = 4, w = 168 }, { key = "pin", x = 176 } })
    list.panel:SetPoint("TOPLEFT", 0, -36)
    list.panel:SetPoint("BOTTOMLEFT")
    list.panel:SetWidth(248)
    list.onClick = function(_, n)
        p.selected = n.id
        p:Refresh()
    end

    -- Bearbeiten
    local editor = T.Panel(p)
    editor:SetPoint("TOPLEFT", list.panel, "TOPRIGHT", 12, 36)
    editor:SetPoint("BOTTOMRIGHT")

    local titleLabel = T.Text(editor, "kicker")
    titleLabel:SetPoint("TOPLEFT", 18, -16)
    titleLabel:SetText("TITEL")
    p.title = T.EditBox(editor, 300)
    p.title:SetPoint("TOPLEFT", 18, -32)
    p.title:SetPoint("TOPRIGHT", -18, -32)
    p.title:SetMaxLetters(60)
    p.title:SetScript("OnTextChanged", function(self, userInput)
        local n = Current()
        if userInput and n then
            n.title = self:GetText()
            ns.Notes:Changed(n)
        end
    end)

    local textLabel = T.Text(editor, "kicker")
    textLabel:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -14)
    textLabel:SetText("TEXT")

    local box = T.Panel(editor)
    box:SetBackdropColor(T.colors.ink[1], T.colors.ink[2], T.colors.ink[3], 0.9)
    box:SetPoint("TOPLEFT", textLabel, "BOTTOMLEFT", 0, -6)
    box:SetPoint("BOTTOMRIGHT", -18, 96)
    local sf = T.Scroll(box)
    sf:SetPoint("TOPLEFT", 8, -8)
    sf:SetPoint("BOTTOMRIGHT", -6, 8)
    local text = CreateFrame("EditBox", nil, sf.content)
    text:SetPoint("TOPLEFT")
    text:SetPoint("RIGHT", sf.content, "RIGHT")
    text:SetHeight(200)
    text:SetMultiLine(true)
    text:SetAutoFocus(false)
    text:SetMaxLetters(0)
    text:SetFontObject(T.fonts.body)
    text:SetScript("OnEscapePressed", text.ClearFocus)
    text:SetScript("OnTextChanged", function(self, userInput)
        sf.content:SetHeight(math.max(self:GetHeight(), 1))
        sf.UpdateThumb()
        local n = Current()
        if userInput and n then
            n.text = self:GetText()
            ns.Notes:Changed(n)
        end
    end)
    text:SetScript("OnCursorChanged", function(_, _, y, _, h)
        local offset, view, cur = -y, sf:GetHeight(), sf:GetVerticalScroll()
        if offset < cur then
            sf:SetVerticalScroll(offset)
        elseif offset + h > cur + view then
            sf:SetVerticalScroll(math.min(sf:GetVerticalScrollRange(), offset + h - view))
        end
        sf.UpdateThumb()
    end)
    sf:SetScript("OnMouseDown", function() text:SetFocus() end)
    p.text = text

    -- Anzeige auf dem Bildschirm
    local showLabel = T.Text(editor, "kicker")
    showLabel:SetPoint("BOTTOMLEFT", 18, 72)
    showLabel:SetText("AUF DEM BILDSCHIRM")

    local pin = T.Button(editor, "", 170, "primary")
    pin:SetPoint("BOTTOMLEFT", 18, 40)
    pin:SetScript("OnClick", function()
        local n = Current()
        if n then ns.Notes:SetPinned(n, not n.pinned) end
    end)
    local lock = T.Button(editor, "", 130)
    lock:SetPoint("LEFT", pin, "RIGHT", 8, 0)
    lock:SetScript("OnClick", function()
        local n = Current()
        if n then
            n.locked = not n.locked
            ns.Notes:Changed(n)
        end
    end)
    local smaller = T.Button(editor, "A-", 34)
    smaller:SetPoint("LEFT", lock, "RIGHT", 16, 0)
    smaller:SetScript("OnClick", function()
        local n = Current()
        if n then
            n.fontSize = (n.fontSize or 13) - 1
            ns.Notes:Changed(n)
        end
    end)
    local bigger = T.Button(editor, "A+", 34)
    bigger:SetPoint("LEFT", smaller, "RIGHT", 4, 0)
    bigger:SetScript("OnClick", function()
        local n = Current()
        if n then
            n.fontSize = (n.fontSize or 13) + 1
            ns.Notes:Changed(n)
        end
    end)
    local sizeText = T.Text(editor, "muted")
    sizeText:SetPoint("LEFT", bigger, "RIGHT", 8, 0)

    local alphaText = T.Text(editor, "small")
    alphaText:SetPoint("BOTTOMLEFT", 18, 16)
    local slider = T.Slider(editor, 200, 0, 100, 5)
    slider:SetPoint("LEFT", alphaText, "LEFT", 150, 0)
    slider:SetScript("OnValueChanged", function(_, value, userInput)
        local n = Current()
        if userInput and n then
            n.alpha = value
            ns.Notes:Changed(n)
        end
    end)
    local hint = T.Text(editor, "muted")
    hint:SetPoint("LEFT", slider, "RIGHT", 14, 0)
    hint:SetText("0 % = ganz durchsichtig")

    local empty = T.Text(editor, "muted", "CENTER")
    empty:SetPoint("CENTER")
    empty:SetText("Noch keine Notizen – „Neue Notiz“ klicken.")
    local editorParts = { titleLabel, p.title, textLabel, box, showLabel, pin, lock, smaller, bigger, sizeText, alphaText, slider, hint }

    function p:Refresh()
        local all = ns.Notes:All()
        local n = Current() or all[1]
        p.selected = n and n.id

        list:SetData(all, function(row, note)
            local title = note.title ~= "" and note.title or "(ohne Titel)"
            row.cols.title:SetText(note == n and T.Hex("goldBright", title) or title)
            row.cols.pin:SetText(note.pinned and T.Hex("green", "angezeigt") or "")
        end)

        for _, part in ipairs(editorParts) do part:SetShown(n ~= nil) end
        empty:SetShown(n == nil)
        del:SetEnabled(n ~= nil)
        if not n then return end

        if not p.title:HasFocus() then p.title:SetText(n.title or "") end
        if not text:HasFocus() then text:SetText(n.text or "") end
        pin:SetText(n.pinned and "Vom Bildschirm nehmen" or "Auf dem Bildschirm zeigen")
        lock:SetText(n.locked and "Fixiert" or "Verschiebbar")
        lock:SetEnabled(n.pinned)
        sizeText:SetText("Schrift " .. (n.fontSize or 13))
        alphaText:SetText(string.format("Hintergrund: %d %%", n.alpha or 85))
        slider:SetValue(n.alpha or 85)
    end

    return p
end

-- Textdialog (Import / Export) ---------------------------------------------
function UI:TextDialog(title, hint, text, onAccept, acceptLabel)
    local d = self.dialog
    if not d then
        local c = T.colors
        d = CreateFrame("Frame", "ElternabendTextDialog", UIParent, "BackdropTemplate")
        d:SetSize(620, 440)
        d:SetPoint("CENTER")
        d:SetFrameStrata("DIALOG")
        d:SetToplevel(true)
        d:SetMovable(true)
        d:EnableMouse(true)
        d:RegisterForDrag("LeftButton")
        d:SetScript("OnDragStart", d.StartMoving)
        d:SetScript("OnDragStop", d.StopMovingOrSizing)
        T.Backdrop(d, c.navy, 0.98, 0.7)
        tinsert(UISpecialFrames, "ElternabendTextDialog")

        local kicker = T.Text(d, "kicker")
        kicker:SetPoint("TOPLEFT", 20, -18)
        kicker:SetText("ELTERNABEND · " .. ns.WEBSITE:upper())
        d.title = T.Text(d, "heading")
        d.title:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -6)
        d.hint = T.Text(d, "muted")
        d.hint:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -8)
        d.hint:SetPoint("RIGHT", -20, 0)
        d.hint:SetSpacing(3)

        local box = T.Panel(d)
        box:SetBackdropColor(c.ink[1], c.ink[2], c.ink[3], 0.9)
        box:SetPoint("TOPLEFT", 20, -100)
        box:SetPoint("BOTTOMRIGHT", -20, 56)

        local sf = T.Scroll(box)
        sf:SetPoint("TOPLEFT", 8, -8)
        sf:SetPoint("BOTTOMRIGHT", -6, 8)
        local eb = CreateFrame("EditBox", nil, sf.content)
        eb:SetPoint("TOPLEFT")
        eb:SetPoint("RIGHT", sf.content, "RIGHT")
        eb:SetHeight(300)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(0)
        eb:SetFontObject(T.fonts.small)
        eb:SetScript("OnEscapePressed", eb.ClearFocus)
        eb:SetScript("OnTextChanged", function(self)
            sf.content:SetHeight(math.max(self:GetHeight(), 1))
            sf.UpdateThumb()
        end)
        eb:SetScript("OnCursorChanged", function(_, _, y, _, h)
            local offset = -y
            local view = sf:GetHeight()
            local cur = sf:GetVerticalScroll()
            if offset < cur then
                sf:SetVerticalScroll(offset)
            elseif offset + h > cur + view then
                sf:SetVerticalScroll(math.min(sf:GetVerticalScrollRange(), offset + h - view))
            end
            sf.UpdateThumb()
        end)
        sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
        d.edit = eb

        d.close = T.Button(d, "Schließen", 110)
        d.close:SetPoint("BOTTOMRIGHT", -20, 18)
        d.close:SetScript("OnClick", function() d:Hide() end)
        d.ok = T.Button(d, "OK", 140, "primary")
        d.ok:SetPoint("RIGHT", d.close, "LEFT", -8, 0)
        d.ok:SetScript("OnClick", function()
            if d.onAccept and d.onAccept(d.edit:GetText()) ~= false then d:Hide() end
        end)
        self.dialog = d
    end

    d.title:SetText(title)
    d.hint:SetText(hint or "")
    d.onAccept = onAccept
    d.ok:SetShown(onAccept ~= nil)
    d.ok:SetText(acceptLabel or "OK")
    d.edit:SetText(text or "")
    d:Show()
    d.edit:SetFocus()
    if text and text ~= "" then d.edit:HighlightText() end
end

function UI:ShowImport()
    self:TextDialog("Raid einfügen",
        "Im Raidplaner auf " .. ns.WEBSITE .. " den Text „Für das Addon“ kopieren und hier mit Strg+V einfügen.\n" ..
        "Ein CSV-Export von softres.it funktioniert auch.",
        "", function(text) return ns.Web:Import(text) end, "Einfügen")
end

function UI:ShowReport()
    local report = ns.Web:BuildReport()
    if not report then
        ns.Print("Noch kein Raid-Protokoll vorhanden.")
        return
    end
    self:TextDialog("Raid-Bericht für die Webseite",
        "Der Text ist markiert: mit Strg+C kopieren und im Raidplaner unter „Für die Gildenleitung“ einfügen.",
        report)
end

function UI:ShowExport()
    local lines = { "Datum,ItemId,Item,Gewinner,Art,Wurf,SR,Handel,Zone" }
    for _, h in ipairs(ns.db.history) do
        local name = (h.link and h.link:match("%[(.-)%]")) or ""
        local zone = (h.zone or ""):gsub('"', '""')
        table.insert(lines, string.format('%s,%d,"%s",%s,%s,%s,%s,%s,"%s"',
            date("%Y-%m-%d %H:%M", h.time), h.itemId or 0, (name:gsub('"', '""')), h.winner or "",
            h.label or "", h.roll or "", h.sr and "ja" or "nein", h.trade and "ja" or "nein", zone))
    end
    self:TextDialog("Loot als CSV", "Mit Strg+C kopieren (der Text ist bereits markiert).", table.concat(lines, "\n"))
end

-- Bestätigungsdialoge --------------------------------------------------------
StaticPopupDialogs["ELTERNABEND_AWARD"] = {
    text = "%s an %s vergeben?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) ns.Loot:Award(data.name, data.item) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["ELTERNABEND_DELETE_NOTE"] = {
    text = "Notiz „%s“ wirklich löschen?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, id) ns.Notes:Delete(id) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["ELTERNABEND_CLEAR_SR"] = {
    text = "Soft-Reserve-Liste wirklich leeren?",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ns.SR:Clear() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["ELTERNABEND_CLEAR_HISTORY"] = {
    text = "Beute-Verlauf wirklich leeren?",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        wipe(ns.db.history)
        ns:Fire("HISTORY_UPDATE")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Minimap-Button -----------------------------------------------------------
function UI:UpdateMinimapButton()
    local b = self.minimapButton
    if not b then return end
    local s = ns.db.settings
    b:SetShown(not s.minimapHidden)
    local angle = math.rad(s.minimapAngle or 220)
    local radius = (Minimap:GetWidth() / 2) + 10
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function UI:CreateMinimapButton()
    local b = CreateFrame("Button", "ElternabendMinimapButton", Minimap)
    b:SetSize(32, 32)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(ns.LOGO)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.2)
    T.Round(hl, b)

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then UI:Show("mitglieder") else UI:Toggle() end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ns.db.settings.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
            UI:UpdateMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Elternabend", 0.95, 0.86, 0.6)
        GameTooltip:AddLine("Linksklick: Fenster öffnen", 1, 1, 1)
        GameTooltip:AddLine("Rechtsklick: Gilde", 1, 1, 1)
        GameTooltip:AddLine("Ziehen: verschieben", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    self.minimapButton = b
    self:UpdateMinimapButton()
end

ns:Listen("INIT", function() UI:CreateMinimapButton() end)
