-- Elternabend: Reiter „Berufe“ » „Gildenmarkt“
-- Links die Angebote (Suche, Filter), rechts das gewählte Angebot – oder das Formular „Angebot einstellen“.
local _, ns = ...
local T = ns.Theme
local UI = ns.UI

local DETAIL_W = 360

local function Coins(copper) return ns.Market.Money(copper) end

-- Preis aus drei Feldern (Gold, Silber, Kupfer) in Kupfer
local function ReadPrice(g, s, k)
    local function N(eb) return math.max(0, math.floor(tonumber(eb:GetText()) or 0)) end
    return N(g) * 10000 + math.min(99, N(s)) * 100 + math.min(99, N(k))
end

local function NumberBox(parent, width, placeholder)
    local eb = T.EditBox(parent, width, placeholder)
    if eb.SetNumeric then eb:SetNumeric(true) end
    eb:SetMaxLetters(6)
    return eb
end

function UI:CreateMarketPanel()
    local p = self:NewPanel()
    local M = ns.Market
    local listW = UI.CONTENT_W - DETAIL_W - 12
    p.filter = "alle"

    -- Kopfzeile: Suche, Filter, Einstellen -------------------------------------------------------
    local search = T.EditBox(p, 220, "Gegenstand oder Verkäufer …")
    T.AddClearButton(search)
    search:SetPoint("TOPLEFT", 0, 0)
    search:HookScript("OnTextChanged", function() p:Refresh() end)
    p.search = search

    local FILTERS = {
        { key = "alle", label = "Alle" },
        { key = "e", label = "Einzelangebote" },
        { key = "s", label = "Schaufenster" },
        { key = "meine", label = "Meine" },
    }
    p.filterButtons = {}
    local prev = search
    for _, f in ipairs(FILTERS) do
        local b = T.Button(p, f.label, f.key == "e" and 116 or f.key == "s" and 108 or 70)
        b:SetPoint("LEFT", prev, "RIGHT", 8, 0)
        b:SetScript("OnClick", function()
            p.filter = f.key
            p:Refresh()
        end)
        p.filterButtons[f.key] = b
        prev = b
    end

    p.newBtn = T.Button(p, "Angebot einstellen", DETAIL_W, "primary")
    p.newBtn:SetPoint("TOPRIGHT", 0, 0)
    p.newBtn:SetScript("OnClick", function()
        p.selected = nil
        p.form = true
        -- Filter „Schaufenster“ oder „Einzelangebote“ gewählt: gleich diese Art vorauswählen
        if p.filter == "s" or p.filter == "e" then p.formKind = p.filter end
        p:Refresh()
    end)

    -- Liste --------------------------------------------------------------------------------------------
    local columns = {
        { key = "icon", x = 2, icon = true },
        { key = "name", label = "Gegenstand", x = 26, w = 230 },
        { key = "qty", label = "Menge", x = 262, w = 64 },
        { key = "price", label = "Preis", x = 330, w = 110 },
        { key = "seller", label = "Verkäufer", x = 444, w = 130 },
        { key = "kind", label = "Art", x = 578 },
    }
    local list = UI.CreateList(p, columns)
    list.panel:SetPoint("TOPLEFT", 0, -34)
    list.panel:SetPoint("BOTTOMLEFT", 0, 0)
    list.panel:SetWidth(listW)
    list.onClick = function(_, o, button)
        if button == "LeftButton" and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
            ChatEdit_InsertLink(M:Link(o))
            return
        end
        p.selected = o.id
        p.form = false
        p:Refresh()
    end
    list.onEnter = function(row, o)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetHyperlink, GameTooltip, o.item) then GameTooltip:AddLine(o.name or "?") end
        GameTooltip:Show()
    end
    p.list = list
    p.empty = T.Text(list.panel, "muted", "CENTER")
    p.empty:SetPoint("CENTER", 0, -10)
    p.empty:SetWidth(listW - 60)

    -- Rechte Seite -------------------------------------------------------------------------------------
    local side = T.Panel(p)
    side:SetPoint("TOPRIGHT", 0, -34)
    side:SetPoint("BOTTOMRIGHT", 0, 0)
    side:SetWidth(DETAIL_W)
    p.side = side

    -- a) Gewähltes Angebot
    local det = CreateFrame("Frame", nil, side)
    det:SetAllPoints()
    p.det = det
    det.kicker = T.Text(det, "kicker")
    det.kicker:SetPoint("TOPLEFT", 14, -12)
    det.icon = det:CreateTexture(nil, "ARTWORK")
    det.icon:SetSize(36, 36)
    det.icon:SetPoint("TOPLEFT", 14, -30)
    det.iconBtn = CreateFrame("Button", nil, det)
    det.iconBtn:SetAllPoints(det.icon)
    det.iconBtn:SetScript("OnEnter", function(self)
        local o = p.current
        if not o then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if not pcall(GameTooltip.SetHyperlink, GameTooltip, o.item) then GameTooltip:AddLine(o.name or "?") end
        GameTooltip:Show()
    end)
    det.iconBtn:SetScript("OnLeave", GameTooltip_Hide)
    det.name = T.Text(det, "navActive")
    det.name:SetPoint("TOPLEFT", det.icon, "TOPRIGHT", 10, -2)
    det.name:SetPoint("RIGHT", -14, 0)
    det.name:SetWordWrap(true)
    det.info = T.Text(det, "body")
    det.info:SetPoint("TOPLEFT", det.icon, "BOTTOMLEFT", 0, -12)
    det.info:SetPoint("RIGHT", -14, 0)
    det.info:SetSpacing(3)

    det.qty = NumberBox(det, 60, "1")
    det.buy = T.Button(det, "Kaufen", 150, "primary")
    det.qtyLabel = T.Text(det, "muted")
    det.qtyLabel:SetText("Stück:")
    -- Summe zur eingegebenen Menge (mit Mengenrabatt)
    det.sum = T.Text(det, "muted")
    function det.UpdateSum()
        local o = p.current
        if not o then return end
        local qty = M:Partial(o) and math.max(1, tonumber(det.qty:GetText()) or 1) or o.count
        local unit = M:UnitPrice(o, qty)
        if M:IsGift(o) then
            det.sum:SetText(qty .. " Stück, " .. T.Hex("green", "geschenkt"))
            return
        end
        det.sum:SetText(qty .. " Stück = " .. T.Hex("goldBright", Coins(M:Total(o, qty)))
            .. (unit < o.price and T.Hex("green", "  (Mengenrabatt: " .. Coins(unit) .. " pro Stück)") or ""))
    end
    det.qty:HookScript("OnTextChanged", function() det.UpdateSum() end)
    det.status = T.Text(det, "body")
    det.status:SetPoint("LEFT", 14, 0)
    det.status:SetPoint("RIGHT", -14, 0)
    det.status:SetWordWrap(true)
    det.cancel = T.Button(det, "Kaufwunsch zurückziehen", 200)
    det.remove = T.Button(det, "Angebot herausnehmen", 200)
    det.reqHead = T.Text(det, "kicker")
    det.reqHead:SetText("KAUFWÜNSCHE")
    det.reqRows = {}
    for i = 1, 4 do
        local r = CreateFrame("Frame", nil, det)
        r:SetSize(DETAIL_W - 28, 46)
        r.text = T.Text(r, "small")
        r.text:SetPoint("TOPLEFT", 0, 0)
        r.text:SetPoint("RIGHT", 0, 0)
        r.text:SetWordWrap(false)
        r.mail = T.Button(r, "Brief vorbereiten", 130)
        r.mail:SetPoint("TOPLEFT", 0, -16)
        r.mail:SetHeight(24)
        r.done = T.Button(r, "Erledigt", 82)
        r.done:SetPoint("LEFT", r.mail, "RIGHT", 6, 0)
        r.done:SetHeight(24)
        r.no = T.Button(r, "Ablehnen", 82)
        r.no:SetPoint("LEFT", r.done, "RIGHT", 6, 0)
        r.no:SetHeight(24)
        det.reqRows[i] = r
    end
    det.msg = T.Text(det, "muted")
    det.msg:SetPoint("BOTTOMLEFT", 14, 12)
    det.msg:SetPoint("RIGHT", -14, 0)
    det.msg:SetWordWrap(true)

    local function Say(text) det.msg:SetText(text or "") end

    det.buy:SetScript("OnClick", function()
        local o = p.current
        if not o then return end
        local ok, err = M:Buy(o.id, tonumber(det.qty:GetText()) or 1)
        Say(ok and (M:IsGift(o) and ("Wunsch ist an " .. ns.ShortName(o.seller) .. " unterwegs. Das Geschenk kommt per Brief.")
            or ("Kaufwunsch ist an " .. ns.ShortName(o.seller) .. " unterwegs. Die Ware kommt per Brief mit Nachnahme – du zahlst beim Öffnen.")) or err)
        p:Refresh()
    end)
    det.cancel:SetScript("OnClick", function()
        if p.current then M:Cancel(p.current.id) end
        Say("Kaufwunsch zurückgezogen.")
        p:Refresh()
    end)
    det.remove:SetScript("OnClick", function()
        if p.current then M:Remove(p.current.id) end
        Say("Angebot herausgenommen.")
        p:Refresh()
    end)

    -- b) Formular „Angebot einstellen“
    local form = CreateFrame("Frame", nil, side)
    form:SetAllPoints()
    p.formFrame = form
    form.kicker = T.Text(form, "kicker")
    form.kicker:SetPoint("TOPLEFT", 14, -12)
    form.kicker:SetText("ANGEBOT EINSTELLEN")
    -- Feld für den Gegenstand: aus der Tasche hineinziehen oder anklicken, während man ihn hält
    local slot = CreateFrame("Button", nil, form, "BackdropTemplate")
    slot:SetSize(40, 40)
    slot:SetPoint("TOPLEFT", 14, -30)
    T.Backdrop(slot, nil, 0.6, 0.8)
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 2, -2)
    slot.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    local function TakeCursor()
        local kind, _, link = GetCursorInfo()
        if kind == "item" and link then
            p.formLink = link
            ClearCursor()
            local have = M.CountItem(M.ItemString(link))
            form.count:SetText(tostring(1))
            form.have = have
            p:Refresh()
        end
    end
    slot:SetScript("OnReceiveDrag", TakeCursor)
    slot:SetScript("OnClick", TakeCursor)
    slot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if p.formLink then
            pcall(GameTooltip.SetHyperlink, GameTooltip, M.ItemString(p.formLink))
        else
            GameTooltip:AddLine("Gegenstand aus der Tasche hierher ziehen")
        end
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", GameTooltip_Hide)
    form.slot = slot
    form.TakeCursor = TakeCursor
    form.itemText = T.Text(form, "body")
    form.itemText:SetPoint("LEFT", slot, "RIGHT", 10, 0)
    form.itemText:SetPoint("RIGHT", -14, 0)
    form.itemText:SetWordWrap(true)

    local y = -84
    local function Label(text)
        local l = T.Text(form, "muted")
        l:SetPoint("TOPLEFT", 14, y - 6)
        l:SetText(text)
        return l
    end
    Label("Art")
    form.kindButtons = {}
    local kx = 96
    for _, k in ipairs({ { key = "e", label = "Einzelangebot" }, { key = "s", label = "Schaufenster" } }) do
        local b = T.Button(form, k.label, 120)
        b:SetPoint("TOPLEFT", kx, y)
        b:SetScript("OnClick", function()
            p.formKind = k.key
            p:Refresh()
        end)
        form.kindButtons[k.key] = b
        kx = kx + 126
    end
    y = y - 34
    form.hoursLabel = Label("Laufzeit")
    form.hourButtons = {}
    kx = 96
    for _, h in ipairs(M.HOURS) do
        local b = T.Button(form, h .. " Std.", 60)
        b:SetPoint("TOPLEFT", kx, y)
        b:SetScript("OnClick", function()
            p.formHours = h
            p:Refresh()
        end)
        form.hourButtons[h] = b
        kx = kx + 63
    end
    y = y - 34
    form.countLabel = Label("Menge")
    form.count = NumberBox(form, 60, "1")
    form.count:SetPoint("TOPLEFT", 96, y)
    form.haveText = T.Text(form, "muted")
    form.haveText:SetPoint("LEFT", form.count, "RIGHT", 8, 0)
    form.count:HookScript("OnTextChanged", function(_, user) if user then p:Refresh() end end)
    y = y - 30
    -- Einzelangebot: verschenken (ohne Preis) und – bei mehreren Stück – nur komplett abgeben
    form.gift = T.Checkbox(form, "verschenken")
    form.gift:SetPoint("TOPLEFT", 92, y)
    form.gift.onChange = function() p:Refresh() end
    form.whole = T.Checkbox(form, "nur komplett")
    form.whole:SetPoint("TOPLEFT", 222, y)
    form.whole.onChange = function() p:Refresh() end
    y = y - 30
    form.priceLabel = Label("Preis")
    form.gold = NumberBox(form, 64, "Gold")
    form.gold:SetPoint("TOPLEFT", 96, y)
    form.silver = NumberBox(form, 52, "Silber")
    form.silver:SetPoint("LEFT", form.gold, "RIGHT", 6, 0)
    form.silver:SetMaxLetters(2)
    form.copper = NumberBox(form, 52, "Kupfer")
    form.copper:SetPoint("LEFT", form.silver, "RIGHT", 6, 0)
    form.copper:SetMaxLetters(2)
    form.perPiece = T.Text(form, "muted")
    form.perPiece:SetPoint("LEFT", form.copper, "RIGHT", 8, 0)
    y = y - 34
    -- Mengenrabatt: bis zu zwei Staffeln „ab … Stück: Preis pro Stück“
    form.tierLabel = Label("Rabatt")
    form.tiers = {}
    for i = 1, 2 do
        local t = {}
        t.ab = T.Text(form, "muted")
        t.ab:SetPoint("TOPLEFT", 96, y - 6)
        t.ab:SetText("ab")
        t.min = NumberBox(form, 40, "")
        t.min:SetPoint("TOPLEFT", 116, y)
        t.min:SetMaxLetters(4)
        t.st = T.Text(form, "muted")
        t.st:SetPoint("LEFT", t.min, "RIGHT", 4, 0)
        t.st:SetText("St.")
        t.gold = NumberBox(form, 52, "Gold")
        t.gold:SetPoint("LEFT", t.st, "RIGHT", 6, 0)
        t.silver = NumberBox(form, 44, "Silber")
        t.silver:SetPoint("LEFT", t.gold, "RIGHT", 4, 0)
        t.silver:SetMaxLetters(2)
        t.copper = NumberBox(form, 44, "Kupfer")
        t.copper:SetPoint("LEFT", t.silver, "RIGHT", 4, 0)
        t.copper:SetMaxLetters(2)
        form.tiers[i] = t
        y = y - 28
    end
    y = y - 4
    Label("Notiz")
    form.note = T.EditBox(form, DETAIL_W - 110, "optional, z. B. „auch Tausch“")
    form.note:SetPoint("TOPLEFT", 96, y)
    form.note:SetMaxLetters(80)
    y = y - 38
    form.post = T.Button(form, "Einstellen", 150, "primary")
    form.post:SetPoint("TOPLEFT", 14, y)
    form.abort = T.Button(form, "Abbrechen", 110)
    form.abort:SetPoint("LEFT", form.post, "RIGHT", 8, 0)
    form.abort:SetScript("OnClick", function()
        p.form = false
        p.formLink = nil
        p:Refresh()
    end)
    form.msg = T.Text(form, "muted")
    form.msg:SetPoint("TOPLEFT", 14, y - 36)
    form.msg:SetPoint("RIGHT", -14, 0)
    form.msg:SetWordWrap(true)
    form.post:SetScript("OnClick", function()
        local ok, res = M:Post({
            link = p.formLink, kind = p.formKind, hours = p.formHours,
            count = tonumber(form.count:GetText()) or 1,
            price = ReadPrice(form.gold, form.silver, form.copper), note = form.note:GetText(),
            gift = p.formKind == "e" and form.gift:GetChecked(),
            whole = form.whole:GetChecked(), tiers = (function()
                local list = {}
                for _, t in ipairs(form.tiers) do
                    local min = tonumber(t.min:GetText())
                    if min then table.insert(list, { min = min, price = ReadPrice(t.gold, t.silver, t.copper) }) end
                end
                return list
            end)(),
        })
        if not ok then
            form.msg:SetText(T.Hex("red", res))
            return
        end
        p.formLink = nil
        for _, eb in ipairs({ form.gold, form.silver, form.copper, form.note }) do eb:SetText("") end
        for _, t in ipairs(form.tiers) do
            for _, eb in ipairs({ t.min, t.gold, t.silver, t.copper }) do eb:SetText("") end
        end
        form.whole:SetChecked(false)
        form.gift:SetChecked(false)
        form.msg:SetText("")
        p.form = false
        p.selected = res.id
        Say("Dein Angebot steht im Gildenmarkt.")
        p:Refresh()
    end)
    p.formKind, p.formHours = "e", 24

    -- Neu zeichnen --------------------------------------------------------------------------------------
    local function KindText(o)
        if o.kind == "s" then return T.Hex("goldBright", "Schaufenster") end
        return "noch " .. M.Left(o.expires - M.Now())
    end

    local function QtyText(o)
        if o.kind == "s" then
            local a = M:Available(o)
            return a > 0 and (a .. " da") or T.Hex("muted", "ausverkauft")
        end
        if o.count > 1 and M:Partial(o) and o.state == "offen" then
            local a = M:Available(o)
            return a < o.count and (a .. " von " .. o.count) or (o.count .. "x")
        end
        return o.count > 1 and (o.count .. "x") or "1"
    end

    local function PerPiece(o) return o.kind == "s" or o.count > 1 end

    -- „50s pro Stück, ab 10 Stück 45s, ab 20 Stück 40s“
    local function TierLines(o)
        local lines = {}
        for _, t in ipairs(M.ParseTiers(o.tiers)) do
            table.insert(lines, "  ab " .. t.min .. " Stück: " .. T.Hex("green", Coins(t.price)) .. " pro Stück")
        end
        return lines
    end

    local function StateText(o)
        if o.state == "verkauft" then return T.Hex("green", "verkauft") end
        if o.state == "entfernt" then return T.Hex("muted", "herausgenommen") end
        if M:ReservedBy(o) then return T.Hex("orange", "reserviert") end
        return KindText(o)
    end

    local function RefreshForm()
        local link = p.formLink
        form.slot.icon:SetTexture(link and M:Icon({ item = M.ItemString(link) }) or nil)
        form.itemText:SetText(link or T.Hex("muted", "Gegenstand aus der Tasche in das Feld ziehen"))
        for key, b in pairs(form.kindButtons) do b:SetSelected(p.formKind == key) end
        local single = p.formKind == "e"
        for h, b in pairs(form.hourButtons) do
            b:SetSelected(p.formHours == h)
            b:SetShown(single)
        end
        form.hoursLabel:SetShown(single)
        form.countLabel:SetShown(single)
        form.count:SetShown(single)
        form.haveText:SetShown(single and link ~= nil)
        form.haveText:SetText(link and ("du hast " .. (form.have or 0)) or "")
        local count = tonumber(form.count:GetText()) or 1
        local many = not single or count > 1
        local gift = single and form.gift:GetChecked()
        form.gift:SetShown(single)
        form.whole:SetShown(single and count > 1)
        local tiers = many and not gift and not (single and form.whole:GetChecked())
        form.priceLabel:SetShown(not gift)
        for _, eb in ipairs({ form.gold, form.silver, form.copper, form.perPiece }) do eb:SetShown(not gift) end
        form.tierLabel:SetShown(tiers)
        for _, t in ipairs(form.tiers) do
            for _, wdg in ipairs({ t.ab, t.min, t.st, t.gold, t.silver, t.copper }) do wdg:SetShown(tiers) end
        end
        form.perPiece:SetText(many and "pro Stück" or "")
        form.post:SetEnabled(link ~= nil)
    end

    local function RefreshDetail(o)
        p.current = o
        local mine = M:CanManage(o)
        det.kicker:SetText(o.kind == "s" and "SCHAUFENSTER" or "EINZELANGEBOT")
        det.icon:SetTexture(M:Icon(o))
        det.name:SetText(M:Link(o))
        local lines = {
            "Verkäufer: " .. T.Hex("goldBright", ns.ShortName(o.seller)),
            M:IsGift(o) and ("Preis: " .. T.Hex("green", "geschenkt – kostet nichts"))
                or ("Preis: " .. T.Hex("goldBright", Coins(o.price)) .. (PerPiece(o) and " pro Stück" or "")),
        }
        for _, l in ipairs(TierLines(o)) do table.insert(lines, l) end
        if o.kind == "s" then
            table.insert(lines, "Vorrat: " .. QtyText(o))
        else
            if o.count > 1 then
                table.insert(lines, "Menge: " .. QtyText(o) .. (o.whole == "1" and T.Hex("muted", " (nur komplett)") or ""))
            end
            table.insert(lines, "Läuft noch " .. M.Left(o.expires - M.Now()))
        end
        if o.state ~= "offen" then table.insert(lines, StateText(o)) end
        if o.note ~= "" then table.insert(lines, T.Hex("muted", "„" .. o.note .. "“")) end
        det.info:SetText(table.concat(lines, "\n"))
        local anchorY = -(30 + 36 + 12 + det.info:GetStringHeight() + 14)

        local myReq = M:MyRequest(o)
        local canBuy = not mine and o.state == "offen" and not (myReq and myReq.st == "neu")
        local partial = M:Partial(o)
        det.qty:SetShown(canBuy and partial)
        det.qtyLabel:SetShown(canBuy and partial)
        det.buy:SetShown(canBuy)
        det.sum:SetShown(canBuy)
        if canBuy then
            local x = 14
            if partial then
                det.qtyLabel:ClearAllPoints()
                det.qtyLabel:SetPoint("TOPLEFT", 14, anchorY - 6)
                det.qty:ClearAllPoints()
                det.qty:SetPoint("TOPLEFT", 60, anchorY)
                x = 130
            end
            det.buy:ClearAllPoints()
            det.buy:SetPoint("TOPLEFT", x, anchorY)
            local available = M:Available(o)
            det.buy:SetEnabled(available > 0)
            det.buy:SetText(available > 0 and (M:IsGift(o) and "Haben wollen" or "Kaufen") or (o.kind == "e" and "Reserviert" or "Ausverkauft"))
            det.sum:ClearAllPoints()
            det.sum:SetPoint("TOPLEFT", 14, anchorY - 34)
            det.UpdateSum()
            anchorY = anchorY - 56
        end
        -- Eigener Kaufwunsch
        det.status:SetShown(myReq ~= nil)
        det.cancel:SetShown(myReq ~= nil and myReq.st == "neu")
        if myReq then
            local st = M.STATES[myReq.st]
            det.status:ClearAllPoints()
            det.status:SetPoint("TOPLEFT", 14, anchorY)
            det.status:SetPoint("RIGHT", -14, 0)
            det.status:SetText("Dein Kaufwunsch: " .. (myReq.qty > 1 and (myReq.qty .. " Stück – ") or "") .. T.Hex(st[2], st[1])
                .. (myReq.st == "versandt" and " – schau in deinen Briefkasten." or ""))
            anchorY = anchorY - 22
            if myReq.st == "neu" then
                det.cancel:ClearAllPoints()
                det.cancel:SetPoint("TOPLEFT", 14, anchorY)
                anchorY = anchorY - 34
            end
        end
        -- Eigenes Angebot: Kaufwünsche bearbeiten
        det.remove:SetShown(mine and o.state == "offen")
        local reqs = {}
        if mine then
            for _, r in ipairs(M:Requests(o)) do
                if r.st ~= "zurueck" then table.insert(reqs, r) end
            end
        end
        det.reqHead:SetShown(#reqs > 0)
        if #reqs > 0 then
            det.reqHead:ClearAllPoints()
            det.reqHead:SetPoint("TOPLEFT", 14, anchorY)
            anchorY = anchorY - 18
        end
        local here = ns.SameName(o.seller, ns.UnitFullName("player"))
        for i, row in ipairs(det.reqRows) do
            local r = reqs[i]
            row:SetShown(r ~= nil)
            if r then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 14, anchorY)
                local st = M.STATES[r.st]
                local total = M:Total(o, r.qty)
                row.text:SetText(T.Hex("goldBright", ns.ShortName(r.buyer)) .. "  " .. (PerPiece(o) and (r.qty .. " Stück, ") or "")
                    .. (M:IsGift(o) and T.Hex("green", "Geschenk") or Coins(total)) .. "  ·  " .. T.Hex(st[2], st[1]))
                local open = r.st == "neu"
                row.mail:SetShown(open)
                row.done:SetShown(open)
                row.no:SetShown(open)
                row.mail:SetEnabled(here and M.mailOpen == true)
                row.mail:SetScript("OnClick", function()
                    local ok, res = M:PrepareMail(o.id, r.key)
                    if not ok then Say(T.Hex("red", res)) return end
                    Say(res and "Brief ist fertig – nur noch abschicken. Danach steht der Kauf auf „verschickt“."
                        or ("Brief ist vorbereitet. Zieh noch " .. (r.qty > 1 and (r.qty .. "x ") or "") .. (o.name or "") .. " in den Brief und schick ihn ab."))
                end)
                row.mail:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                    GameTooltip:AddLine("Brief mit Nachnahme vorbereiten")
                    GameTooltip:AddLine(not here and ("Die Ware liegt bei " .. ns.ShortName(o.seller) .. " – bitte dorthin umloggen.")
                        or not M.mailOpen and "Erst einen Briefkasten öffnen."
                        or "Empfänger, Betreff und Nachnahme werden ausgefüllt, die Ware wird angelegt. Du musst nur noch abschicken.", 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                row.mail:SetScript("OnLeave", GameTooltip_Hide)
                row.done:SetScript("OnClick", function()
                    M:Answer(o.id, r.key, "versandt")
                    Say("Als erledigt markiert (z. B. per Handel übergeben).")
                end)
                row.no:SetScript("OnClick", function()
                    M:Answer(o.id, r.key, "abgelehnt")
                    Say("Kaufwunsch abgelehnt.")
                end)
                anchorY = anchorY - (open and 46 or 20)
            end
        end
        if det.remove:IsShown() then
            det.remove:ClearAllPoints()
            det.remove:SetPoint("TOPLEFT", 14, anchorY - 6)
        end
    end

    function p:Refresh()
        for key, b in pairs(self.filterButtons) do b:SetSelected(self.filter == key) end
        local f = { search = search:GetText() }
        if self.filter == "e" or self.filter == "s" then f.kind = self.filter end
        if self.filter == "meine" then f.mine = true end
        local data = M:List(f)
        list:SetData(data, function(row, o)
            row.cols.icon:SetTexture(M:Icon(o))
            row.cols.name:SetText(M:Link(o) .. (o.id == self.selected and T.Hex("goldBright", "  ◂") or ""))
            row.cols.qty:SetText(QtyText(o))
            row.cols.price:SetText(M:IsGift(o) and T.Hex("green", "Geschenk")
                or (Coins(o.price) .. (PerPiece(o) and T.Hex("muted", " /St.") or "") .. (o.tiers ~= "" and T.Hex("green", " %") or "")))
            row.cols.seller:SetText(ns.ShortName(o.seller))
            row.cols.kind:SetText(StateText(o))
        end)
        self.empty:SetShown(#data == 0)
        self.empty:SetText(self.filter == "meine" and "Du hast noch nichts eingestellt und nichts angefragt."
            or (search:GetText() ~= "" and "Nichts gefunden.")
            or "Noch keine Angebote. Stell als Erster etwas ein – oben rechts „Angebot einstellen“.")

        local o = self.selected and ns.db.market.offers[self.selected]
        if self.form then
            det:Hide()
            form:Show()
            RefreshForm()
        elseif o then
            form:Hide()
            det:Show()
            RefreshDetail(o)
        else
            form:Hide()
            det:Show()
            p.current = nil
            det.kicker:SetText("GILDENMARKT")
            det.icon:SetTexture(nil)
            det.name:SetText("Kaufen und verkaufen in der Gilde")
            det.info:SetText(T.Hex("muted", "Links ein Angebot anklicken. Kaufen schickt dem Verkäufer einen Kaufwunsch – "
                .. "auch wenn er gerade offline ist. Die Ware kommt per Brief mit Nachnahme, du zahlst beim Öffnen.\n\n"
                .. "Selbst verkaufen: „Angebot einstellen“. Schaufenster bleiben dauerhaft stehen (z. B. Tränke), "
                .. "Einzelangebote laufen nach 6 bis 48 Stunden ab (z. B. Ausrüstung)."))
            for _, w in ipairs({ det.qty, det.qtyLabel, det.buy, det.sum, det.status, det.cancel, det.remove, det.reqHead }) do w:Hide() end
            for _, r in ipairs(det.reqRows) do r:Hide() end
        end
    end

    return p
end
