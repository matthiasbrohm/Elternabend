-- Gildenmarkt (Idee von Philipp Wobakoff): Schaufenster und Einzelangebote, Kaufwunsch, Nachnahme, Abgleich

local POTION = "|cffffffff|Hitem:13446::::::::60:::::|h[Großer Heiltrank]|h|r"
local SWORD = "|cff0070dd|Hitem:12345::::::1027:::60:::::|h[Klinge des Bären]|h|r"

local function Welt(name, count)
    local first, last = (name or "Anna Sturmwind"):match("^(%S+) (%S+)$")
    local w = login({ guild = "Elternabend", name = first, surname = last, roster = {
        { name = "Anna Sturmwind", online = true }, { name = "Beta Lux", online = true },
        { name = "Greta Glutherz", online = true },
    } })
    w.env.C_Item.GetItemCount = function() return count or 20 end
    w:advance(40)
    return w
end

local function Send(from, to, id)
    to.ns.Market:Receive(from.ns.Market:Serialize(from.ns.db.market.offers[id]))
end

test("Markt: Geld und Gegenstandstext", function()
    local w = Welt()
    local M = w.ns.Market
    equal(M.Money(12345), "1g 23s 45k")
    equal(M.Money(50000), "5g")
    equal(M.Money(0), "0k")
    equal(M.ItemString(SWORD), "item:12345::::::1027:::60:::::")
    equal(M.ItemID(M.ItemString(SWORD)), 12345)
    noErrors(w)
end)

test("Markt: Einzelangebot einstellen, läuft nach der gewählten Zeit ab", function()
    local w = Welt()
    local M = w.ns.Market
    local ok, o = M:Post({ link = SWORD, kind = "e", count = 1, price = 250000, hours = 12, note = "kaum getragen" })
    check(ok, o)
    equal(o.kind, "e")
    equal(o.name, "Klinge des Bären")
    equal(o.quality, 3)
    equal(o.expires - o.created, 12 * 3600)
    w:advance(1)
    seen(w, "comm", "MKTN .*O%^" .. o.id)
    equal(#M:List(), 1)
    -- ohne Preis / ohne Gegenstand
    check(not M:Post({ link = SWORD, kind = "e", price = 0 }), "ohne Preis eingestellt")
    check(not M:Post({ kind = "e", price = 100 }), "ohne Gegenstand eingestellt")
    noErrors(w)
end)

test("Markt: Schaufenster zählt den Vorrat und bleibt bestehen", function()
    local w = Welt(nil, 20)
    local M = w.ns.Market
    local ok, o = M:Post({ link = POTION, kind = "s", price = 5000 })
    check(ok, o)
    equal(o.stock, 20)
    equal(o.expires - o.created, 30 * 86400)
    -- zweimal dasselbe im Schaufenster geht nicht
    check(not M:Post({ link = POTION, kind = "s", price = 4000 }), "doppelt im Schaufenster")
    -- Vorrat ändert sich
    w.env.C_Item.GetItemCount = function() return 7 end
    w:clear()
    M:CheckStock()
    equal(o.stock, 7)
    w:advance(1)
    seen(w, "comm", "MKTN .*O%^" .. o.id)
    noErrors(w)
end)

test("Markt: Kaufwunsch erreicht den Verkäufer, Einzelangebot ist dann reserviert", function()
    local seller = Welt("Anna Sturmwind")
    local buyer = Welt("Beta Lux")
    local third = Welt("Greta Glutherz")
    local ok, o = seller.ns.Market:Post({ link = SWORD, kind = "e", price = 250000, hours = 24 })
    check(ok, o)
    Send(seller, buyer, o.id)
    Send(seller, third, o.id)
    equal(#buyer.ns.Market:List(), 1)
    local bought, err = buyer.ns.Market:Buy(o.id)
    check(bought, err)
    -- Verkäufer bekommt den Kaufwunsch (auch über einen Dritten)
    Send(buyer, third, o.id)
    seller:clear()
    Send(third, seller, o.id)
    seen(seller, "print", "Beta Lux möchte .*Klinge des Bären.* für 25g kaufen")
    equal(seller.ns.Market:OpenRequestCount(), 1)
    -- für andere reserviert
    local got = third.ns.db.market.offers[o.id]
    equal(third.ns.Market:Available(got), 0)
    check(not third.ns.Market:Buy(o.id), "doppelt gekauft")
    noErrors(seller)
    noErrors(buyer)
end)

test("Markt: Verkäufer verschickt, Käufer erfährt es, Angebot ist verkauft", function()
    local seller = Welt("Anna Sturmwind")
    local buyer = Welt("Beta Lux")
    local _, o = seller.ns.Market:Post({ link = SWORD, kind = "e", price = 250000, hours = 6 })
    Send(seller, buyer, o.id)
    buyer.ns.Market:Buy(o.id)
    Send(buyer, seller, o.id)
    seller.ns.Market:Answer(o.id, seller.ns.NameKey("Beta Lux"), "versandt")
    equal(seller.ns.db.market.offers[o.id].state, "verkauft")
    buyer:clear()
    Send(seller, buyer, o.id)
    seen(buyer, "print", "Anna Sturmwind hat dir .*per Nachnahme geschickt")
    equal(#buyer.ns.Market:List(), 0)
    -- eine alte Fassung macht es nicht wieder „offen“
    local old = buyer.ns.Market:Parse(buyer.ns.Market:Serialize(buyer.ns.db.market.offers[o.id]))
    old.state, old.updated = "offen", old.updated + 50
    buyer.ns.Market:Merge(old, true)
    equal(buyer.ns.db.market.offers[o.id].state, "verkauft")
    noErrors(seller)
    noErrors(buyer)
end)

test("Markt: Schaufenster – Menge kaufen, nicht mehr als vorrätig, ablehnen", function()
    local seller = Welt("Anna Sturmwind", 10)
    local buyer = Welt("Beta Lux")
    local _, o = seller.ns.Market:Post({ link = POTION, kind = "s", price = 5000 })
    Send(seller, buyer, o.id)
    check(not buyer.ns.Market:Buy(o.id, 11), "mehr als vorrätig")
    check(buyer.ns.Market:Buy(o.id, 4), "Kauf ging nicht")
    equal(buyer.ns.Market:Available(buyer.ns.db.market.offers[o.id]), 6)
    Send(buyer, seller, o.id)
    seen(seller, "print", "4x .*für 2g kaufen")
    seller.ns.Market:Answer(o.id, seller.ns.NameKey("Beta Lux"), "abgelehnt")
    buyer:clear()
    Send(seller, buyer, o.id)
    seen(buyer, "print", "kann dir .*leider nicht verkaufen")
    equal(buyer.ns.Market:Available(buyer.ns.db.market.offers[o.id]), 10)
    noErrors(seller)
    noErrors(buyer)
end)

test("Markt: Kaufwunsch zurückziehen gibt das Einzelangebot frei", function()
    local seller = Welt("Anna Sturmwind")
    local buyer = Welt("Beta Lux")
    local _, o = seller.ns.Market:Post({ link = SWORD, kind = "e", price = 1000, hours = 6 })
    Send(seller, buyer, o.id)
    buyer.ns.Market:Buy(o.id)
    equal(buyer.ns.Market:Available(buyer.ns.db.market.offers[o.id]), 0)
    buyer.ns.Market:Cancel(o.id)
    equal(buyer.ns.Market:Available(buyer.ns.db.market.offers[o.id]), 1)
    noErrors(buyer)
end)

test("Markt: Abgleich beim Einloggen schickt fehlende Angebote", function()
    local seller = Welt("Anna Sturmwind")
    local _, o = seller.ns.Market:Post({ link = SWORD, kind = "e", price = 1000, hours = 48 })
    seller:clear()
    seller.ns.Market:AnswerRequest("Beta Lux", "abc#")
    seller:advance(10)
    seen(seller, "comm", "MKTA abc")
    seen(seller, "comm", "MKTN .*O%^" .. o.id)
    noErrors(seller)
end)

test("Markt: Zurückziehen und Ablauf", function()
    local w = Welt()
    local M = w.ns.Market
    local _, o = M:Post({ link = SWORD, kind = "e", price = 1000, hours = 6 })
    M:Remove(o.id)
    equal(#M:List(), 0)
    equal(o.state, "entfernt")
    local _, o2 = M:Post({ link = POTION, kind = "s", price = 1000 })
    w.env.GetServerTime = function() return o2.created + 31 * 86400 end
    w.env.time = w.env.GetServerTime
    M:Prune()
    check(w.ns.db.market.offers[o2.id] == nil, "Schaufenster nicht abgelaufen")
    noErrors(w)
end)

-- Reiter -----------------------------------------------------------------------------------------------

test("Reiter Gildenmarkt: Unterreiter von Berufe, Liste, Angebot einstellen per Ziehen", function()
    local w = Welt(nil, 5)
    local UI = w.ns.UI
    UI:Show("markt")
    check(UI.panels.markt:IsShown(), "Gildenmarkt nicht offen")
    check(UI.subTabs.berufe:IsShown() and UI.subTabs.markt:IsShown(), "Unterreiter fehlen")
    local p = UI.panels.markt
    check(p.empty:IsShown(), "Hinweis bei leerer Liste fehlt")
    -- Einstellen: Gegenstand aufs Feld ziehen
    w:call(p.newBtn:GetScript("OnClick"))
    check(p.formFrame:IsShown(), "Formular nicht offen")
    w.env.GetCursorInfo = function() return "item", 12345, SWORD end
    local cleared = false
    w.env.ClearCursor = function() cleared = true end
    w:call(p.formFrame.TakeCursor)
    check(cleared, "Cursor nicht geleert")
    equal(p.formLink, SWORD)
    w:call(p.formFrame.hourButtons[48]:GetScript("OnClick"))
    p.formFrame.gold:SetText("12")
    p.formFrame.silver:SetText("50")
    w:call(p.formFrame.post:GetScript("OnClick"))
    local o = w.ns.db.market.offers[p.selected]
    check(o, "nicht eingestellt: " .. tostring(p.formFrame.msg:GetText()))
    equal(o.price, 125000)
    equal(o.expires - o.created, 48 * 3600)
    check(p.det:IsShown(), "Angebot wird nicht gezeigt")
    check(p.det.remove:IsShown(), "eigenes Angebot ohne „herausnehmen“")
    check(not p.det.buy:IsShown(), "eigenes Angebot zum Kaufen")
    equal(#p.list.rows > 0 and p.list.rows[1]:IsShown(), true)
    noErrors(w)
end)

test("Reiter Gildenmarkt: Kaufen per Knopf, Verkäufer sieht Kaufwunsch mit Knöpfen", function()
    local seller = Welt("Anna Sturmwind", 10)
    local buyer = Welt("Beta Lux")
    local _, o = seller.ns.Market:Post({ link = POTION, kind = "s", price = 5000 })
    Send(seller, buyer, o.id)
    buyer.ns.UI:Show("markt")
    local p = buyer.ns.UI.panels.markt

    buyer:call(p.list.onClick, p.list.rows[1], buyer.ns.db.market.offers[o.id], "LeftButton")
    check(p.det.buy:IsShown() and p.det.qty:IsShown(), "Kaufen fehlt")
    p.det.qty:SetText("3")
    buyer:call(p.det.buy:GetScript("OnClick"))
    check(p.det.cancel:IsShown(), "Zurückziehen fehlt")
    Send(buyer, seller, o.id)
    seller.ns.UI:Show("markt")
    local sp = seller.ns.UI.panels.markt
    equal(seller.ns.UI.subTabs.markt.badge.count or seller.ns.Market:OpenRequestCount(), 1)
    sp.selected = o.id
    seller:call(sp.Refresh, sp)
    local row = sp.det.reqRows[1]
    check(row:IsShown() and row.mail:IsShown() and row.no:IsShown(), "Kaufwunsch-Knöpfe fehlen")
    check(row.text:GetText():find("Beta Lux", 1, true) and row.text:GetText():find("3 Stück", 1, true), row.text:GetText())
    -- ohne Briefkasten: Brief-Knopf aus
    check(not row.mail:IsEnabled(), "Brief ohne Briefkasten möglich")
    noErrors(seller)
    noErrors(buyer)
end)

test("Gildenmarkt: Brief mit Nachnahme vorbereiten, beim Abschicken „verschickt“", function()
    local seller = Welt("Anna Sturmwind", 10)
    local buyer = Welt("Beta Lux")
    local _, o = seller.ns.Market:Post({ link = POTION, kind = "s", price = 5000 })
    Send(seller, buyer, o.id)
    buyer.ns.Market:Buy(o.id, 2)
    Send(buyer, seller, o.id)
    local env = seller.env
    local filled = {}
    env.SendMailNameEditBox = { SetText = function(_, t) filled.name = t end }
    env.SendMailSubjectEditBox = { SetText = function(_, t) filled.subject = t end }
    env.SendMailMoney = {}
    env.MoneyInputFrame_SetCopper = function(_, c) filled.cod = c end
    env.SendMailRadioButton_OnClick = function(i) filled.radio = i end
    seller:fire("MAIL_SHOW")
    local key = seller.ns.NameKey("Beta Lux")
    local ok = seller.ns.Market:PrepareMail(o.id, key)
    check(ok, "Brief nicht vorbereitet")
    equal(filled.name, "Beta Lux")
    equal(filled.cod, 10000)
    equal(filled.radio, 2)
    check(filled.subject:find("2x Großer Heiltrank", 1, true), filled.subject)
    -- abschicken
    seller.ns.Market.sendingTo = "Beta Lux"
    seller:fire("MAIL_SEND_SUCCESS")
    equal(seller.ns.db.market.offers[o.id].reqs[key].st, "versandt")
    seen(seller, "print", "Brief an Beta Lux ist unterwegs")
    noErrors(seller)
end)
