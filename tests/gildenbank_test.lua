-- Gildenbank: Bestand je Fach, Anfragen ab Rang „Mitglied“, Freigabe durch Offiziere, Brief ohne Nachnahme

local LEATHER = "|cffffffff|Hitem:8170::::::::60:::::|h[Unverwüstliches Leder]|h|r"
local FLASK = "|cffffffff|Hitem:13510::::::::60:::::|h[Fläschchen der Titanen]|h|r"

local RANKS = { "Gildenleitung", "Offizier", "Raidleitung", "Mitglied", "Neuling" }

local function Welt(name)
    local first, last = (name or "Anna Sturmwind"):match("^(%S+) (%S+)$")
    local w = login({ guild = "Elternabend", name = first, surname = last, roster = {
        { name = "Anna Sturmwind", online = true, rank = "Offizier", rankIndex = 1 },
        { name = "Beta Lux", online = true, rank = "Mitglied", rankIndex = 3 },
        { name = "Greta Glutherz", online = true, rank = "Neuling", rankIndex = 4 },
    } })
    w.env.GuildControlGetNumRanks = function() return #RANKS end
    w.env.GuildControlGetRankName = function(i) return RANKS[i] end
    w:advance(40)
    return w
end

-- Gildenbank mit zwei Fächern in der Testwelt
local function Tresor(w, tabs)
    w.env.GetNumGuildBankTabs = function() return #tabs end
    w.env.GetGuildBankTabInfo = function(tab) return tabs[tab].name, 0, tabs[tab].viewable ~= false end
    w.env.QueryGuildBankTab = function() end
    w.env.GetGuildBankItemLink = function(tab, slot) local s = tabs[tab].slots[slot] return s and s[1] end
    w.env.GetGuildBankItemInfo = function(tab, slot) local s = tabs[tab].slots[slot] return 0, s and s[2] end
end

local function Send(from, to, id)
    to.ns.GuildBank:Receive(from.ns.GuildBank:Serialize(from.ns.db.guildbank.records[id]))
end

test("Gildenbank: Bestand beim Öffnen auslesen und verteilen", function()
    local w = Welt()
    Tresor(w, {
        { name = "Mats", slots = { [1] = { LEATHER, 20 }, [5] = { LEATHER, 13 } } },
        { name = "Raid", slots = { [2] = { FLASK, 3 } } },
        { name = "Geheim", viewable = false, slots = { [1] = { FLASK, 99 } } },
    })
    w:clear()
    w:fire("GUILDBANKFRAME_OPENED")
    w:advance(5)
    local stock = w.ns.GuildBank:Stock()
    equal(#stock, 2)
    local leather
    for _, e in ipairs(stock) do if e.name == "Unverwüstliches Leder" then leather = e end end
    check(leather, "Leder fehlt")
    equal(leather.count, 33)
    equal(w.ns.GuildBank:StockOf(stock[1].item) > 0, true)
    seen(w, "comm", "BNKN .*T%^t1%^1%^Mats")
    notSeen(w, "comm", "T%^t3")
    -- an andere verteilt, neueres Fach gewinnt
    local other = Welt("Beta Lux")
    Send(w, other, "t1")
    equal(#other.ns.GuildBank:Stock(), 1)
    noErrors(w)
end)

test("Gildenbank: Anfrage ab Rang Mitglied, Offizier gibt frei, Anfragender erfährt es", function()
    local officer = Welt("Anna Sturmwind")
    Tresor(officer, { { name = "Mats", slots = { [1] = { LEATHER, 20 } } } })
    officer:fire("GUILDBANKFRAME_OPENED")
    officer:advance(5)
    local member = Welt("Beta Lux")
    local newbie = Welt("Greta Glutherz")
    Send(officer, member, "t1")
    Send(officer, newbie, "t1")
    local item = member.ns.GuildBank:Stock()[1].item
    -- Neuling darf nicht
    check(not newbie.ns.GuildBank:Ask(item, 5), "Neuling darf anfragen")
    -- mehr als da: nein
    check(not member.ns.GuildBank:Ask(item, 25), "mehr als vorhanden")
    local ok, r = member.ns.GuildBank:Ask(item, 10, "für Rüstung")
    check(ok, r)
    member:advance(2)
    seen(member, "comm", "BNKN .*R%^")
    officer:clear()
    Send(member, officer, r.id)
    seen(officer, "print", "Beta Lux möchte 10x Unverwüstliches Leder .*für Rüstung")
    equal(officer.ns.GuildBank:OpenCount(), 1)
    equal(member.ns.GuildBank:OpenCount(), 0) -- nur Offiziere sehen die Plakette
    check(officer.ns.GuildBank:Decide(r.id, "frei"), "Freigabe ging nicht")
    check(not member.ns.GuildBank:Decide(r.id, "abgelehnt"), "Mitglied darf entscheiden")
    member:clear()
    Send(officer, member, r.id)
    seen(member, "print", "Anna Sturmwind hat 10x Unverwüstliches Leder für dich freigegeben")
    noErrors(officer)
    noErrors(member)
end)

test("Gildenbank: Brief ohne Nachnahme, beim Abschicken „verschickt“", function()
    local officer = Welt("Anna Sturmwind")
    Tresor(officer, { { name = "Mats", slots = { [1] = { LEATHER, 20 } } } })
    officer:fire("GUILDBANKFRAME_OPENED")
    officer:advance(5)
    local member = Welt("Beta Lux")
    Send(officer, member, "t1")
    local _, r = member.ns.GuildBank:Ask(member.ns.GuildBank:Stock()[1].item, 5)
    Send(member, officer, r.id)
    officer.ns.GuildBank:Decide(r.id, "frei")
    local filled = {}
    officer.env.SendMailNameEditBox = { SetText = function(_, t) filled.name = t end }
    officer.env.SendMailSubjectEditBox = { SetText = function(_, t) filled.subject = t end }
    officer.env.SendMailMoney = {}
    officer.env.MoneyInputFrame_SetCopper = function(_, c) filled.cod = c end
    officer.env.SendMailRadioButton_OnClick = function(i) filled.radio = i end
    officer:fire("MAIL_SHOW")
    check(officer.ns.GuildBank:PrepareMail(r.id), "Brief nicht vorbereitet")
    equal(filled.name, "Beta Lux")
    equal(filled.radio, 1)
    equal(filled.cod, 0)
    check(filled.subject:find("Aus der Gildenbank: 5x Unverwüstliches Leder", 1, true), filled.subject)
    officer.ns.GuildBank.sendingTo = "Beta Lux"
    officer:fire("MAIL_SEND_SUCCESS")
    equal(officer.ns.db.guildbank.records[r.id].st, "versandt")
    equal(officer.ns.GuildBank:OpenCount(), 0)
    member:clear()
    Send(officer, member, r.id)
    seen(member, "print", "ist unterwegs zu dir")
    noErrors(officer)
end)

test("Gildenbank: Aus der Bank holen – ganzer Stapel und geteilter Rest", function()
    local officer = Welt("Anna Sturmwind")
    Tresor(officer, { { name = "Mats", slots = { [1] = { LEATHER, 20 }, [2] = { LEATHER, 13 } } } })
    officer:fire("GUILDBANKFRAME_OPENED")
    officer:advance(5)
    local member = Welt("Beta Lux")
    Send(officer, member, "t1")
    local _, r = member.ns.GuildBank:Ask(member.ns.GuildBank:Stock()[1].item, 25)
    Send(member, officer, r.id)
    officer.ns.GuildBank:Decide(r.id, "frei")
    local calls = {}
    officer.env.AutoStoreGuildBankItem = function(tab, slot) table.insert(calls, "auto " .. slot) end
    officer.env.SplitGuildBankItem = function(tab, slot, n) table.insert(calls, "split " .. slot .. " " .. n) end
    officer.env.C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and 4 or 0 end,
        GetContainerItemInfo = function(bag, slot) return nil end,
        PickupContainerItem = function(bag, slot) table.insert(calls, "ablegen " .. slot) end,
    }
    officer.env.CursorHasItem = function() return false end
    local result
    check(officer.ns.GuildBank:Take(r.id, function(ok) result = ok end), "Holen ging nicht los")
    officer:advance(3)
    equal(result, true)
    equal(table.concat(calls, ","), "auto 1,split 2 5,ablegen 1")
    noErrors(officer)
end)

test("Reiter Gildenbank: Unterreiter von Gilde, anfragen per Knopf, Offizier sieht Knöpfe", function()
    local officer = Welt("Anna Sturmwind")
    Tresor(officer, { { name = "Mats", slots = { [1] = { LEATHER, 20 } } } })
    officer:fire("GUILDBANKFRAME_OPENED")
    officer:advance(5)
    local member = Welt("Beta Lux")
    Send(officer, member, "t1")
    member.ns.UI:Show("gildenbank")
    local p = member.ns.UI.panels.gildenbank
    check(p:IsShown(), "Gildenbank nicht offen")
    check(p.stockList.rows[1]:IsShown(), "Bestand fehlt")
    member:call(p.stockList.onClick, p.stockList.rows[1], member.ns.GuildBank:Stock()[1])
    check(p.det.ask:IsShown(), "Anfragen fehlt")
    p.det.qty:SetText("4")
    member:call(p.det.ask:GetScript("OnClick"))
    equal(p.view, "anfragen")
    local id = p.selected
    check(member.ns.db.guildbank.records[id], "keine Anfrage")
    Send(member, officer, id)
    officer.ns.UI:Show("gildenbank")
    local op = officer.ns.UI.panels.gildenbank
    officer:call(op.viewButtons.anfragen:GetScript("OnClick"))
    officer:call(op.reqList.onClick, op.reqList.rows[1], officer.ns.db.guildbank.records[id])

    check(op.det.free:IsShown() and op.det.no:IsShown(), "Freigabe-Knöpfe fehlen")
    officer:call(op.det.free:GetScript("OnClick"))
    check(op.det.take:IsShown() and op.det.mail:IsShown() and op.det.done:IsShown(), "Versand-Knöpfe fehlen")
    noErrors(member)
    noErrors(officer)
end)

test("Plaketten: Anfragen an die Gildenbank nur an „Gildenbank“, nicht am Gildenmarkt oder an Berufe", function()
    local officer = Welt("Anna Sturmwind")
    Tresor(officer, { { name = "Mats", slots = { [1] = { LEATHER, 20 } } } })
    officer:fire("GUILDBANKFRAME_OPENED")
    officer:advance(5)
    local member = Welt("Beta Lux")
    Send(officer, member, "t1")
    local _, r = member.ns.GuildBank:Ask(member.ns.GuildBank:Stock()[1].item, 2)
    Send(member, officer, r.id)
    officer.ns.UI:Show("start")
    officer:call(officer.ns.UI.UpdateBadges, officer.ns.UI)
    local UI = officer.ns.UI
    check(UI.subTabs.gildenbank.badge:IsShown(), "Plakette an Gildenbank fehlt")
    equal(UI.subTabs.gildenbank.badge.text:GetText(), "1")
    check(not UI.subTabs.markt.badge:IsShown(), "Plakette am Gildenmarkt")
    check(not UI.tabs.berufe.badge:IsShown(), "Plakette an Berufe")
    noErrors(officer)
end)
