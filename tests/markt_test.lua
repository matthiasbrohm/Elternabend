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

test("Markt: Mengenrabatt – Stückpreis nach Staffel, Nachnahme mit Rabatt", function()
    local seller = Welt("Anna Sturmwind", 50)
    local buyer = Welt("Beta Lux")
    local M = seller.ns.Market
    check(not M:Post({ link = POTION, kind = "s", price = 5000, tiers = { { min = 10, price = 6000 } } }), "teurerer Rabatt erlaubt")
    local ok, o = M:Post({ link = POTION, kind = "s", price = 5000,
        tiers = { { min = 20, price = 4000 }, { min = 10, price = 4500 } } })
    check(ok, o)
    equal(o.tiers, "10:4500,20:4000")
    equal(M:UnitPrice(o, 9), 5000)
    equal(M:UnitPrice(o, 10), 4500)
    equal(M:Total(o, 25), 100000)
    Send(seller, buyer, o.id)
    equal(buyer.ns.db.market.offers[o.id].tiers, "10:4500,20:4000")
    buyer.ns.Market:Buy(o.id, 10)
    Send(buyer, seller, o.id)
    seen(seller, "print", "10x .*für 4g 50s kaufen")
    noErrors(seller)
end)

test("Markt: Einzelangebot mit 20 Stück – auch 10 kaufen, Rest bleibt im Angebot", function()
    local seller = Welt("Anna Sturmwind", 20)
    local b1 = Welt("Beta Lux")
    local b2 = Welt("Greta Glutherz")
    local _, o = seller.ns.Market:Post({ link = POTION, kind = "e", count = 20, price = 1000, hours = 24 })
    equal(o.whole, "")
    Send(seller, b1, o.id)
    check(b1.ns.Market:Buy(o.id, 10), "Teilkauf geht nicht")
    Send(b1, b2, o.id)
    local seen2 = b2.ns.db.market.offers[o.id]
    equal(b2.ns.Market:Available(seen2), 10)
    check(not b2.ns.Market:Buy(o.id, 11), "mehr als übrig gekauft")
    check(b2.ns.Market:Buy(o.id, 10), "Rest nicht kaufbar")
    equal(b2.ns.Market:Available(b2.ns.db.market.offers[o.id]), 0)
    -- Verkäufer verschickt an beide: dann verkauft
    Send(b1, seller, o.id)
    Send(b2, seller, o.id)
    seller.ns.Market:Answer(o.id, seller.ns.NameKey("Beta Lux"), "versandt")
    local so = seller.ns.db.market.offers[o.id]
    equal(so.state, "offen")
    equal(so.count, 10)
    seller.ns.Market:Answer(o.id, seller.ns.NameKey("Greta Glutherz"), "versandt")
    equal(so.state, "verkauft")
    noErrors(seller)
end)

test("Markt: Einzelangebot „nur komplett“", function()
    local seller = Welt("Anna Sturmwind", 20)
    local buyer = Welt("Beta Lux")
    local _, o = seller.ns.Market:Post({ link = POTION, kind = "e", count = 20, price = 1000, hours = 24, whole = true,
        tiers = { { min = 10, price = 900 } } })
    equal(o.whole, "1")
    equal(o.tiers, "") -- Rabatt ergibt bei „nur komplett“ keinen Sinn
    Send(seller, buyer, o.id)
    buyer.ns.Market:Buy(o.id, 5)
    local bo = buyer.ns.db.market.offers[o.id]
    equal(bo.reqs[buyer.ns.NameKey("Beta Lux")].qty, 20)
    check(buyer.ns.Market:ReservedBy(bo), "nicht reserviert")
    noErrors(buyer)
end)

test("Reiter Gildenmarkt: Rabattfelder im Formular, Summe mit Rabatt beim Kaufen", function()
    local seller = Welt("Anna Sturmwind", 50)
    local buyer = Welt("Beta Lux")
    seller.ns.UI:Show("markt")
    local p = seller.ns.UI.panels.markt
    seller:call(p.newBtn:GetScript("OnClick"))
    seller.env.GetCursorInfo = function() return "item", 13446, POTION end
    seller:call(p.formFrame.TakeCursor)
    seller:call(p.formFrame.kindButtons.s:GetScript("OnClick"))
    check(p.formFrame.tiers[1].min:IsShown(), "Rabattfelder fehlen")
    p.formFrame.silver:SetText("50")
    p.formFrame.tiers[1].min:SetText("10")
    p.formFrame.tiers[1].silver:SetText("45")
    seller:call(p.formFrame.post:GetScript("OnClick"))
    local o = seller.ns.db.market.offers[p.selected]
    check(o, tostring(p.formFrame.msg:GetText()))
    equal(o.tiers, "10:4500")
    Send(seller, buyer, o.id)
    buyer.ns.UI:Show("markt")
    local bp = buyer.ns.UI.panels.markt
    buyer:call(bp.list.onClick, bp.list.rows[1], buyer.ns.db.market.offers[o.id], "LeftButton")
    bp.det.qty:SetText("12")
    buyer:call(bp.det.UpdateSum)
    local sum = bp.det.sum:GetText()
    check(sum:find("12 Stück", 1, true) and sum:find("5g 40s", 1, true) and sum:find("Mengenrabatt", 1, true), sum)
    noErrors(seller)
    noErrors(buyer)
end)

test("Reiter Gildenmarkt: Filter „Schaufenster“ wählt beim Einstellen gleich Schaufenster", function()
    local w = Welt()
    w.ns.UI:Show("markt")
    local p = w.ns.UI.panels.markt
    w:call(p.filterButtons.s:GetScript("OnClick"))
    w:call(p.newBtn:GetScript("OnClick"))
    equal(p.formKind, "s")
    check(not p.formFrame.hourButtons[24]:IsShown(), "Laufzeit beim Schaufenster sichtbar")
    w:call(p.filterButtons.e:GetScript("OnClick"))
    w:call(p.newBtn:GetScript("OnClick"))
    equal(p.formKind, "e")
    noErrors(w)
end)

test("Markt: Einzelangebot verschenken – ohne Preis, Brief ohne Nachnahme", function()
    local seller = Welt("Anna Sturmwind", 5)
    local buyer = Welt("Beta Lux")
    check(not seller.ns.Market:Post({ link = POTION, kind = "s", gift = true }), "Schaufenster verschenken erlaubt")
    local ok, o = seller.ns.Market:Post({ link = SWORD, kind = "e", hours = 24, gift = true })
    check(ok, o)
    equal(o.price, 0)
    Send(seller, buyer, o.id)
    check(buyer.ns.Market:Buy(o.id), "Geschenk nicht wählbar")
    Send(buyer, seller, o.id)
    seen(seller, "print", "Beta Lux hätte gern .*Klinge des Bären.*, das du verschenkst")
    local filled = {}
    seller.env.SendMailNameEditBox = { SetText = function(_, t) filled.name = t end }
    seller.env.SendMailSubjectEditBox = { SetText = function(_, t) filled.subject = t end }
    seller.env.SendMailMoney = {}
    seller.env.MoneyInputFrame_SetCopper = function(_, c) filled.cod = c end
    seller.env.SendMailRadioButton_OnClick = function(i) filled.radio = i end
    seller:fire("MAIL_SHOW")
    check(seller.ns.Market:PrepareMail(o.id, seller.ns.NameKey("Beta Lux")), "Brief nicht vorbereitet")
    equal(filled.radio, 1)
    equal(filled.cod, 0)
    check(filled.subject:find("Geschenk", 1, true), filled.subject)
    noErrors(seller)
end)

test("Reiter Gildenmarkt: Haken „verschenken“ blendet den Preis aus", function()
    local w = Welt(nil, 5)
    w.ns.UI:Show("markt")
    local p = w.ns.UI.panels.markt
    w:call(p.newBtn:GetScript("OnClick"))
    w.env.GetCursorInfo = function() return "item", 12345, SWORD end
    w:call(p.formFrame.TakeCursor)
    check(p.formFrame.gift:IsShown(), "Haken fehlt")
    p.formFrame.gift:SetChecked(true)
    w:call(p.formFrame.gift.onChange, true)
    check(not p.formFrame.gold:IsShown(), "Preis trotz Geschenk sichtbar")
    w:call(p.formFrame.post:GetScript("OnClick"))
    local o = w.ns.db.market.offers[p.selected]
    check(o and o.price == 0, "nicht als Geschenk eingestellt")
    check(p.list.rows[1].cols.price:GetText():find("Geschenk", 1, true), "Liste zeigt kein Geschenk")
    noErrors(w)
end)

test("Gildenmarkt: Ware über mehrere Stapel in den Brief legen", function()
    local seller = Welt("Anna Sturmwind", 33)
    local buyer = Welt("Beta Lux")
    local _, o = seller.ns.Market:Post({ link = POTION, kind = "s", price = 1800 })
    Send(seller, buyer, o.id)
    buyer.ns.Market:Buy(o.id, 25)
    Send(buyer, seller, o.id)
    local bags = { [0] = { [1] = 20, [2] = 13 } }
    local calls, attached = {}, {}
    seller.env.C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
        GetContainerItemInfo = function(bag, slot)
            local n = bags[bag] and bags[bag][slot]
            if n then return { itemID = 13446, stackCount = n, isLocked = false, hyperlink = POTION } end
        end,
        PickupContainerItem = function(bag, slot) table.insert(calls, "pick " .. slot) end,
        SplitContainerItem = function(bag, slot, n) table.insert(calls, "split " .. slot .. " " .. n) end,
    }
    seller.env.ClickSendMailItemButton = function(i) attached[i] = true end
    seller.env.GetSendMailItem = function(i) return attached[i] and "x" or nil end
    seller.env.CursorHasItem = function() return false end
    seller:fire("MAIL_SHOW")
    local ok, res = seller.ns.Market:PrepareMail(o.id, seller.ns.NameKey("Beta Lux"))
    check(ok and res, "nicht angelegt")
    equal(table.concat(calls, ","), "pick 1,split 2 5")
    check(attached[1] and attached[2], "Anhänge fehlen")
    -- zu wenig in den Taschen
    bags[0] = { [1] = 3 }
    attached = {}
    local _, res2, why = seller.ns.Market:PrepareMail(o.id, seller.ns.NameKey("Beta Lux"))
    check(not res2 and why == "bank", "Bank-Hinweis fehlt")
    noErrors(seller)
end)

test("Gildenmarkt: Kaufwunsch überholt wartende Abgleichspakete", function()
    local seller = Welt("Anna Sturmwind")
    local buyer = Welt("Beta Lux")
    local _, o = seller.ns.Market:Post({ link = SWORD, kind = "e", price = 1000, hours = 6 })
    Send(seller, buyer, o.id)
    -- viele große Pakete in der Warteschlange (z. B. Abgleich nach dem Einloggen)
    for i = 1, 30 do buyer.ns.Comm:SendLarge("PROF2", string.rep("x", 200) .. i, "GUILD") end
    buyer:clear()
    buyer.ns.Market:Buy(o.id)
    buyer:advance(2)
    seen(buyer, "comm", "MKTN .*K%^Beta Lux")
    noErrors(buyer)
end)
