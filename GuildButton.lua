-- Elternabend: Knopf am Gildenfenster von Blizzard
-- Ein zusätzlicher Reiter mit dem Gildenwappen rechts am Fenster „Gilde & Communitys“
-- öffnet das Addon direkt im Reiter „Gilde“. Der Knopf hängt nur am Fenster und
-- verändert nichts an Blizzards eigenem Code (nur HookScript), damit nichts blockiert wird.
-- Sichtbar, solange das Gildenfenster offen ist.
local _, ns = ...
local T = ns.Theme
local c = T.colors

local GuildButton = {}
ns.GuildButton = GuildButton
local buttons = {}

-- Die Reiter rechts am Fenster (Chat, Mitglieder, Gildeninfo, …). WoW Forever hat dort
-- andere Reiter als Retail, deshalb suchen wir sie nach Lage statt nach Namen:
-- kleine, sichtbare Kinder des Fensters, die rechts außen hängen. Der unterste gewinnt.
local function LowestSideTab(host)
    local right = host:GetRight()
    if not right then return end
    local best, bestBottom
    for _, child in ipairs({ host:GetChildren() }) do
        if child:IsVisible() and child:GetWidth() < 80 and child:GetHeight() < 80 then
            local left, bottom = child:GetLeft(), child:GetBottom()
            if left and bottom and left >= right - 8 and (not bestBottom or bottom < bestBottom) then
                best, bestBottom = child, bottom
            end
        end
    end
    return best
end

local function Place(b, host)
    local tab = LowestSideTab(host)
    if tab == b.anchor and b:GetNumPoints() > 0 then return end
    b.anchor = tab
    b:ClearAllPoints()
    if tab then
        b:SetPoint("TOP", tab, "BOTTOM", 0, -12)
    else
        b:SetPoint("TOPLEFT", host, "TOPRIGHT", 2, -40) -- verkleinertes Fenster: keine Reiter
    end
end

local function Create(host)
    if not host or buttons[host] then return end
    -- Der Knopf hängt an UIParent und folgt dem Gildenfenster nur per Anker und Hooks.
    -- So kann Blizzards Fenstercode ihn weder ausblenden noch verdecken.
    local b = CreateFrame("Button", "ElternabendGildenKnopf" .. (host == CommunitiesFrame and "" or "2"), UIParent, "BackdropTemplate")
    buttons[host] = b
    b:Hide()
    b:SetSize(38, 38)
    b:SetFrameStrata("MEDIUM")
    T.Backdrop(b, c.ink, 0.92, 0.9)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    icon:SetTexture(ns.LOGO)
    T.Round(icon, b)

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(1, 1, 1, 0.15)

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, button)
        local UI = ns.UI
        local wanted = button == "RightButton" and "start" or "mitglieder"
        if UI.frame and UI.frame:IsShown() and UI.currentTab == wanted then
            UI.frame:Hide()
        else
            UI:Show(wanted)
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Elternabend", 0.95, 0.86, 0.6)
        GameTooltip:AddLine("Linksklick: Gilde mit Mains und Twinks", 1, 1, 1)
        GameTooltip:AddLine("Rechtsklick: Startseite des Addons", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)

    local function Update()
        local hidden = ns.db and ns.db.settings and ns.db.settings.guildButtonHidden
        if hidden or not host:IsVisible() then b:Hide() return end
        Place(b, host)
        b:SetFrameLevel(host:GetFrameLevel() + 50)
        b:SetScale(host:GetEffectiveScale() / UIParent:GetEffectiveScale())
        b:Show()
    end
    b.Update = Update
    host:HookScript("OnShow", Update)
    host:HookScript("OnHide", function() b:Hide() end)
    -- Die Reiter rechts wechseln (Community, verkleinern/vergrößern): kurz nachsehen, ob der Knopf mitrücken muss
    local wait = 0
    b:SetScript("OnUpdate", function(self, elapsed)
        wait = wait + elapsed
        if wait < 0.25 then return end
        wait = 0
        Place(self, host)
    end)
    Update()
end

local function TryCreate()
    if CommunitiesFrame then Create(CommunitiesFrame) end
    if GuildFrame then Create(GuildFrame) end -- älteres Gildenfenster
end

-- Wird das Gildenfenster geöffnet, prüfen wir noch einmal, welches Fenster es ist.
-- (Falls es neu aufgebaut wurde, bekommt auch das neue Fenster seinen Knopf.)
local function OnPanelShown(frame)
    if not frame then return end
    if frame == CommunitiesFrame or frame == GuildFrame or frame:GetName() == "CommunitiesFrame" then
        Create(frame)
        local b = buttons[frame]
        if b then b.Update() end
    end
end
hooksecurefunc("ShowUIPanel", OnPanelShown)
if ToggleGuildFrame then hooksecurefunc("ToggleGuildFrame", TryCreate) end
if ToggleCommunitiesFrame then hooksecurefunc("ToggleCommunitiesFrame", TryCreate) end

function GuildButton:Refresh()
    for _, b in pairs(buttons) do b.Update() end
end

ns:Listen("INIT", TryCreate)
ns:On("ADDON_LOADED", function(name)
    if name == "Blizzard_Communities" or name == "Blizzard_GuildUI" then TryCreate() end
end)
