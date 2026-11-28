-- Elternabend: Reiter „Gilde“ » „Gildenbank“
-- Links Bestand oder Anfragen (umschaltbar), rechts das Anfrageformular bzw. die gewählte Anfrage mit den
-- Knöpfen für Offiziere (Freigeben, Ablehnen, Aus der Bank holen, Brief vorbereiten, Erledigt).
local _, ns = ...
local T = ns.Theme
local UI = ns.UI

local DETAIL_W = 360

local function Fmt(t) return t and date("%d.%m. %H:%M", t) or "?" end

function UI:CreateGuildBankPanel()
    local p = self:NewPanel()
    local B = ns.GuildBank
    local M = ns.Market
    local listW = UI.CONTENT_W - DETAIL_W - 12
    p.view = "bestand"

    -- Kopfzeile ------------------------------------------------------------------------------------
    local search = T.EditBox(p, 220, "Gegenstand suchen …")
    T.AddClearButton(search)
    search:SetPoint("TOPLEFT", 0, 0)
    search:HookScript("OnTextChanged", function() p:Refresh() end)
    p.search = search
    p.viewButtons = {}
    local prev = search
    for _, v in ipairs({ { key = "bestand", label = "Bestand", w = 96 }, { key = "anfragen", label = "Anfragen", w = 110 } }) do
        local b = T.Button(p, v.label, v.w)
        b:SetPoint("LEFT", prev, "RIGHT", 8, 0)
        b:SetScript("OnClick", function()
            p.view = v.key
            p.selected = nil
            p:Refresh()
        end)
        p.viewButtons[v.key] = b
        prev = b
    end
    p.stand = T.Text(p, "muted")
    p.stand:SetPoint("LEFT", prev, "RIGHT", 12, 0)
    p.stand:SetPoint("RIGHT", p, "RIGHT", -(DETAIL_W + 12), 0)
    p.stand:SetWordWrap(false)

    -- Liste ------------------------------------------------------------------------------------------
    local stockCols = {
        { key = "icon", x = 2, icon = true },
        { key = "name", label = "Gegenstand", x = 26, w = 300 },
        { key = "count", label = "Menge", x = 330, w = 80 },
        { key = "tabs", label = "Fach", x = 414 },
    }
    local reqCols = {
        { key = "icon", x = 2, icon = true },
        { key = "name", label = "Gegenstand", x = 26, w = 230 },
        { key = "who", label = "Wer", x = 260, w = 130 },
        { key = "when", label = "Wann", x = 394, w = 90 },
        { key = "st", label = "Stand", x = 488 },
    }
    local function MakeList(cols)
        local l = UI.CreateList(p, cols)
        l.panel:SetPoint("TOPLEFT", 0, -34)
        l.panel:SetPoint("BOTTOMLEFT", 0, 0)
        l.panel:SetWidth(listW)
        l.onEnter = function(row, e)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetHyperlink, GameTooltip, e.item) then GameTooltip:AddLine(e.name or "?") end
            GameTooltip:Show()
        end
        return l
    end
    p.stockList = MakeList(stockCols)
    p.reqList = MakeList(reqCols)
    p.stockList.onClick = function(_, e)
        p.selected = e.item
        p:Refresh()
    end
    p.reqList.onClick = function(_, r)
        p.selected = r.id
        p:Refresh()
    end
    p.empty = T.Text(p, "muted", "CENTER")
    p.empty:SetPoint("CENTER", p.stockList.panel, "CENTER", 0, -10)
    p.empty:SetWidth(listW - 60)

    -- Rechte Seite -----------------------------------------------------------------------------------
    local side = T.Panel(p)
    side:SetPoint("TOPRIGHT", 0, -34)
    side:SetPoint("BOTTOMRIGHT", 0, 0)
    side:SetWidth(DETAIL_W)
    local d = CreateFrame("Frame", nil, side)
    d:SetAllPoints()
    p.det = d
    d.kicker = T.Text(d, "kicker")
    d.kicker:SetPoint("TOPLEFT", 14, -12)
    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(36, 36)
    d.icon:SetPoint("TOPLEFT", 14, -30)
    d.name = T.Text(d, "navActive")
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 10, -2)
    d.name:SetPoint("RIGHT", -14, 0)
    d.name:SetWordWrap(true)
    d.info = T.Text(d, "body")
    d.info:SetPoint("TOPLEFT", d.icon, "BOTTOMLEFT", 0, -12)
    d.info:SetPoint("RIGHT", -14, 0)
    d.info:SetSpacing(3)

    -- Formular „Anfragen“
    d.qtyLabel = T.Text(d, "muted")
    d.qtyLabel:SetText("Menge")
    d.qty = T.EditBox(d, 60, "1")
    if d.qty.SetNumeric then d.qty:SetNumeric(true) end
    d.qty:SetMaxLetters(5)
    d.noteLabel = T.Text(d, "muted")
    d.noteLabel:SetText("Wofür")
    d.note = T.EditBox(d, DETAIL_W - 96, "optional, z. B. „für den Raid Mittwoch“")
    d.note:SetMaxLetters(80)
    d.ask = T.Button(d, "Bei der Leitung anfragen", 220, "primary")

    -- Knöpfe für Offiziere bzw. den Anfragenden
    d.free = T.Button(d, "Freigeben", 110, "primary")
    d.no = T.Button(d, "Ablehnen", 100)
    d.take = T.Button(d, "Aus der Bank holen", 160)
    d.mail = T.Button(d, "Brief vorbereiten", 150, "primary")
    d.done = T.Button(d, "Erledigt", 90)
    d.cancel = T.Button(d, "Anfrage zurückziehen", 190)

    d.msg = T.Text(d, "muted")
    d.msg:SetPoint("BOTTOMLEFT", 14, 12)
    d.msg:SetPoint("RIGHT", -14, 0)
    d.msg:SetWordWrap(true)
    local function Say(text) d.msg:SetText(text or "") end
    p.Say = Say

    d.ask:SetScript("OnClick", function()
        if not p.current then return end
        local ok, res = B:Ask(p.current.item, tonumber(d.qty:GetText()) or 1, d.note:GetText())
        if not ok then Say(T.Hex("red", res)) return end
        d.note:SetText("")
        d.qty:SetText("")
        Say("Anfrage ist an die Gildenleitung unterwegs – auch wenn gerade niemand online ist. Du bekommst Bescheid.")
        p.view, p.selected = "anfragen", res.id
        p:Refresh()
    end)
    d.free:SetScript("OnClick", function()
        if p.current and B:Decide(p.current.id, "frei") then Say("Freigegeben. Jetzt an der Gildenbank „Aus der Bank holen“, dann am Briefkasten „Brief vorbereiten“.") end
        p:Refresh()
    end)
    d.no:SetScript("OnClick", function()
        if p.current and B:Decide(p.current.id, "abgelehnt") then Say("Abgelehnt.") end
        p:Refresh()
    end)
    d.done:SetScript("OnClick", function()
        if p.current and B:Decide(p.current.id, "versandt") then Say("Als erledigt markiert (z. B. per Handel übergeben).") end
        p:Refresh()
    end)
    d.cancel:SetScript("OnClick", function()
        if p.current then B:Withdraw(p.current.id) end
        Say("Anfrage zurückgezogen.")
        p:Refresh()
    end)
    d.take:SetScript("OnClick", function()
        if not p.current then return end
        local name = p.current.name
        local ok, err = B:Take(p.current.id, function(success)
            Say(success and (name .. " liegt jetzt in deinen Taschen. Weiter am Briefkasten mit „Brief vorbereiten“.")
                or T.Hex("red", "Das Herausholen hat nicht geklappt – bitte selbst aus der Gildenbank nehmen."))
        end)
        if not ok then Say(T.Hex("red", err)) end
    end)
    d.mail:SetScript("OnClick", function()
        if not p.current then return end
        local r = p.current
        local ok, res, why = B:PrepareMail(r.id)
        if not ok then Say(T.Hex("red", res)) return end
        local what = (r.qty > 1 and (r.qty .. "x ") or "") .. (r.name or "")
        Say(res and "Brief ist fertig – nur noch abschicken. Danach steht die Anfrage auf „verschickt“."
            or why == "bank" and (what .. " ist noch nicht in deinen Taschen – erst an der Gildenbank „Aus der Bank holen“ oder selbst herausnehmen.")
            or ("Brief ist vorbereitet. Zieh noch " .. what .. " in den Brief und schick ihn ab."))
    end)
    for _, b in ipairs({ d.take, d.mail }) do
        b:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(self == d.take and "Erst die Gildenbank öffnen" or "Erst einen Briefkasten öffnen")
            GameTooltip:AddLine(self == d.take and "Holt die freigegebene Menge in deine Taschen (falls das Spiel es zulässt)."
                or "Füllt Empfänger und Betreff aus und legt die Ware ein – ohne Nachnahme.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", GameTooltip_Hide)
    end

    local ALL = { d.qtyLabel, d.qty, d.noteLabel, d.note, d.ask, d.free, d.no, d.take, d.mail, d.done, d.cancel }
    local function Place(widget, x, y)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", x, y)
        widget:Show()
    end

    local function ShowStockItem(e)
        p.current = e
        d.kicker:SetText("AUS DER GILDENBANK ANFRAGEN")
        d.icon:SetTexture(M:Icon(e))
        d.name:SetText(M:Link(e))
        d.info:SetText("In der Bank: " .. T.Hex("goldBright", e.count) .. "\n" .. T.Hex("muted", "Fach: " .. table.concat((function()
            local t = {}
            for name in pairs(e.tabs or {}) do table.insert(t, name) end
            table.sort(t)
            return t
        end)(), ", ")))
        local y = -(30 + 36 + 12 + d.info:GetStringHeight() + 16)
        local may = B:MayRequest(ns.UnitFullName("player"))
        if may then
            Place(d.qtyLabel, 14, y - 6)
            Place(d.qty, 80, y)
            y = y - 34
            Place(d.noteLabel, 14, y - 6)
            Place(d.note, 80, y)
            y = y - 40
            Place(d.ask, 14, y)
        else
            Say(T.Hex("muted", "Anfragen dürfen Mitglieder ab dem Rang „Mitglied“."))
        end
    end

    local function ShowRequest(r)
        p.current = r
        local st = B.STATES[r.st]
        d.kicker:SetText("ANFRAGE")
        d.icon:SetTexture(M:Icon(r))
        d.name:SetText((r.qty > 1 and (r.qty .. "x ") or "") .. M:Link(r))
        local lines = {
            "Von: " .. T.Hex("goldBright", ns.ShortName(r.who)) .. T.Hex("muted", "  ·  " .. Fmt(r.created)),
            "Stand: " .. T.Hex(st[2], st[1]) .. ((r.by ~= "" and r.st ~= "neu" and r.st ~= "zurueck") and T.Hex("muted", " von " .. ns.ShortName(r.by)) or ""),
            "In der Bank: " .. B:StockOf(r.item),
        }
        if r.note ~= "" then table.insert(lines, T.Hex("muted", "„" .. r.note .. "“")) end
        d.info:SetText(table.concat(lines, "\n"))
        local y = -(30 + 36 + 12 + d.info:GetStringHeight() + 16)
        local officer = B:AmOfficer()
        if officer and r.st == "neu" then
            Place(d.free, 14, y)
            Place(d.no, 132, y)
        elseif officer and r.st == "frei" then
            Place(d.take, 14, y)
            d.take:SetEnabled(B.bankOpen == true)
            y = y - 34
            Place(d.mail, 14, y)
            d.mail:SetEnabled(M.mailOpen == true)
            Place(d.done, 172, y)
        elseif r.st == "neu" and ns.Board:IsMePerson(r.who) then
            Place(d.cancel, 14, y)
        end
    end

    function p:Refresh()
        for key, b in pairs(self.viewButtons) do b:SetSelected(self.view == key) end
        local count = B:OpenCount()
        self.viewButtons.anfragen:SetText(count > 0 and ("Anfragen " .. T.Hex("green", "(" .. count .. ")")) or "Anfragen")
        local scan = B:LastScan()
        self.stand:SetText(scan and ("Stand " .. Fmt(scan.time) .. " von " .. ns.ShortName(scan.by or "?")) or "")
        local text = search:GetText() or ""
        local stockView = self.view == "bestand"
        self.stockList.panel:SetShown(stockView)
        self.reqList.panel:SetShown(not stockView)
        local data
        if stockView then
            data = B:Stock(text)
            self.stockList:SetData(data, function(row, e)
                row.cols.icon:SetTexture(M:Icon(e))
                row.cols.name:SetText(M:Link(e) .. (e.item == self.selected and T.Hex("goldBright", "  «") or ""))
                row.cols.count:SetText(tostring(e.count))
                local tabs = {}
                for name in pairs(e.tabs) do table.insert(tabs, name) end
                table.sort(tabs)
                row.cols.tabs:SetText(T.Hex("muted", table.concat(tabs, ", ")))
            end)
            self.empty:SetText(scan and (text ~= "" and "Nichts gefunden." or "Die Gildenbank ist leer.")
                or "Noch kein Bestand bekannt. Sobald jemand mit Addon die Gildenbank öffnet, steht hier, was drin ist.")
        else
            local lower = ns.Lower(strtrim(text))
            data = B:Requests(function(r)
                return lower == "" or ns.Lower(r.name or ""):find(lower, 1, true) or ns.Lower(ns.ShortName(r.who)):find(lower, 1, true)
            end)
            self.reqList:SetData(data, function(row, r)
                local st = B.STATES[r.st]
                row.cols.icon:SetTexture(M:Icon(r))
                row.cols.name:SetText((r.qty > 1 and (r.qty .. "x ") or "") .. M:Link(r) .. (r.id == self.selected and T.Hex("goldBright", "  «") or ""))
                row.cols.who:SetText(ns.ShortName(r.who))
                row.cols.when:SetText(T.Hex("muted", Fmt(r.created)))
                row.cols.st:SetText(T.Hex(st[2], st[1]))
            end)
            self.empty:SetText(text ~= "" and "Nichts gefunden." or "Noch keine Anfragen.")
        end
        self.empty:SetShown(#data == 0)

        for _, w in ipairs(ALL) do w:Hide() end
        local cur
        if self.selected then
            if stockView then
                for _, e in ipairs(B:Stock()) do if e.item == self.selected then cur = e end end
            else
                cur = ns.db.guildbank.records[self.selected]
            end
        end
        if cur and stockView then
            ShowStockItem(cur)
        elseif cur then
            ShowRequest(cur)
        else
            self.current = nil
            d.kicker:SetText("GILDENBANK")
            d.icon:SetTexture(nil)
            d.name:SetText("Etwas aus der Gildenbank haben?")
            d.info:SetText(T.Hex("muted", "Links einen Gegenstand anklicken, Menge eintragen und bei der Leitung anfragen – "
                .. "auch wenn gerade niemand online ist. Wird es freigegeben, kommt es per Brief.\n\n"
                .. "Den Bestand liest das Addon, wenn jemand mit Addon die Gildenbank öffnet."
                .. (B:AmOfficer() and "\n\nAls Offizier siehst du unter „Anfragen“ die Knöpfe zum Freigeben und Verschicken." or "")))
        end
    end

    return p
end
