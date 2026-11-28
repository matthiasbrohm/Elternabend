-- Elternabend: Fenster am Briefkasten – alles, was zu verschicken ist, Brief für Brief per Knopf
-- (Gildenmarkt: Kaufwünsche an eigene Angebote dieses Charakters; Gildenbank: freigegebene Anfragen, Offiziere).
-- „Brief vorbereiten“ füllt Empfänger, Betreff und ggf. Nachnahme aus und legt die Ware ein; abschicken muss man
-- selbst. Nach dem Abschicken bereitet das Fenster gleich den nächsten Brief vor.
local _, ns = ...
local T = ns.Theme
local UI = ns.UI

local Post = {}
ns.Post = Post

-- Was ist zu verschicken? { kind = "market"/"bank", id, key, who, text }
function Post:List()
    local list = {}
    local me = ns.UnitFullName("player")
    local M = ns.Market
    for _, o in pairs(ns.db.market.offers) do
        if o.state == "offen" and o.expires > M.Now() and ns.SameName(o.seller, me) then
            for _, r in ipairs(M:Requests(o)) do
                if r.st == "neu" and not M:IsMine(r.buyer) then
                    table.insert(list, { kind = "market", id = o.id, key = r.key, who = r.buyer, t = r.t,
                        text = r.qty .. "x " .. (o.name or "?") .. T.Hex("muted", " an " .. ns.ShortName(r.buyer)
                            .. (M:IsGift(o) and " (Geschenk)" or (" · Nachnahme " .. M.Money(M:Total(o, r.qty))))) })
                end
            end
        end
    end
    local B = ns.GuildBank
    if B:AmOfficer() then
        for _, r in ipairs(B:Requests(function(r) return r.st == "frei" end)) do
            table.insert(list, { kind = "bank", id = r.id, who = r.who, t = r.updated,
                text = r.qty .. "x " .. (r.name or "?") .. T.Hex("muted", " an " .. ns.ShortName(r.who) .. " (Gildenbank)") })
        end
    end
    table.sort(list, function(a, b) return a.t < b.t end)
    -- Übersprungene ans Ende
    if self.skipped then
        table.sort(list, function(a, b)
            local sa, sb = self.skipped[a.id .. (a.key or "")] or 0, self.skipped[b.id .. (b.key or "")] or 0
            if sa ~= sb then return sa < sb end
            return a.t < b.t
        end)
    end
    return list
end

function Post:Prepare(e)
    if e.kind == "market" then return ns.Market:PrepareMail(e.id, e.key) end
    return ns.GuildBank:PrepareMail(e.id)
end

function UI:ShowMailHelper()
    local list = Post:List()
    local f = self.mailHelper
    if #list == 0 then
        if f then f:Hide() end
        return
    end
    if not f then
        f = CreateFrame("Frame", "ElternabendBriefkasten", UIParent, "BackdropTemplate")
        f:SetSize(360, 200)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        T.Backdrop(f, T.colors.navy, 0.97, 0.8)
        f.kicker = T.Text(f, "kicker")
        f.kicker:SetPoint("TOPLEFT", 16, -14)
        f.kicker:SetText("ELTERNABEND · ZU VERSCHICKEN")
        f.title = T.Text(f, "navActive")
        f.title:SetPoint("TOPLEFT", f.kicker, "BOTTOMLEFT", 0, -6)
        f.title:SetPoint("RIGHT", -16, 0)
        f.title:SetWordWrap(true)
        f.lines = T.Text(f, "body")
        f.lines:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8)
        f.lines:SetPoint("RIGHT", -16, 0)
        f.lines:SetSpacing(2)
        f.status = T.Text(f, "muted")
        f.status:SetPoint("BOTTOMLEFT", 16, 46)
        f.status:SetPoint("RIGHT", -16, 0)
        f.status:SetWordWrap(true)
        f.go = T.Button(f, "Brief vorbereiten", 160, "primary")
        f.go:SetPoint("BOTTOMLEFT", 16, 14)
        f.skip = T.Button(f, "Überspringen", 110)
        f.skip:SetPoint("LEFT", f.go, "RIGHT", 8, 0)
        f.close = T.Button(f, "X", 26)
        f.close:SetHeight(22)
        f.close:SetPoint("TOPRIGHT", -8, -8)
        f.close:SetScript("OnClick", function()
            Post.auto = false
            f:Hide()
        end)
        f.go:SetScript("OnClick", function()
            local e = f.list and f.list[1]
            if not e then return end
            Post.auto = true -- nach dem Abschicken gleich den nächsten vorbereiten
            UI:PrepareNextMail()
        end)
        f.skip:SetScript("OnClick", function()
            local e = f.list and f.list[1]
            if not e then return end
            Post.skipped = Post.skipped or {}
            local k = e.id .. (e.key or "")
            Post.skipped[k] = (Post.skipped[k] or 0) + 1
            f.status:SetText("")
            UI:ShowMailHelper()
        end)
        self.mailHelper = f
    end
    f.list = list
    f.title:SetText(#list == 1 and "1 Brief zu verschicken" or (#list .. " Briefe zu verschicken"))
    local lines = {}
    for i, e in ipairs(list) do
        if i > 6 then
            table.insert(lines, T.Hex("muted", "… und " .. (#list - 6) .. " weitere"))
            break
        end
        table.insert(lines, (i == 1 and T.Hex("goldBright", "» ") or "   ") .. e.text)
    end
    f.lines:SetText(table.concat(lines, "\n"))
    f:SetHeight(140 + math.min(#list, 7) * 17)
    f.skip:SetShown(#list > 1)
    if not f:IsShown() then
        f:ClearAllPoints()
        if MailFrame and MailFrame:IsShown() then
            f:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 8, 0)
        else
            f:SetPoint("CENTER", 300, 100)
        end
    end
    f:Show()
end

function UI:PrepareNextMail()
    local f = self.mailHelper
    local e = f and f.list and f.list[1]
    if not e then return end
    local ok, res, why = Post:Prepare(e)
    if not ok then
        f.status:SetText(T.Hex("red", res))
        return
    end
    f.status:SetText(res and (T.Hex("green", "Brief ist fertig: ") .. e.text .. " – jetzt nur noch „Senden“.")
        or why == "bank" and T.Hex("red", "Die Ware liegt nicht (komplett) in deinen Taschen – erst holen oder „Überspringen“.")
        or "Brief ist vorbereitet – zieh noch die Ware hinein und schick ihn ab.")
end

local function Update()
    if ns.Market.mailOpen then UI:ShowMailHelper() end
end

pcall(ns.On, ns, "MAIL_SHOW", function()
    Post.auto, Post.skipped = false, nil
    C_Timer.After(0.6, Update)
end)
pcall(ns.On, ns, "MAIL_CLOSED", function()
    Post.auto = false
    if UI.mailHelper then UI.mailHelper:Hide() end
end)
-- Abgeschickt: Liste neu, und wenn gewünscht gleich den nächsten Brief vorbereiten
pcall(ns.On, ns, "MAIL_SEND_SUCCESS", function()
    C_Timer.After(1, function()
        if not ns.Market.mailOpen then return end
        UI:ShowMailHelper()
        local f = UI.mailHelper
        if Post.auto and f and f:IsShown() and f.list and f.list[1] then
            UI:PrepareNextMail()
        elseif f and f:IsShown() then
            f.status:SetText("")
        end
    end)
end)
