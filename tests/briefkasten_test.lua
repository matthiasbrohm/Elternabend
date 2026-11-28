-- Fenster am Briefkasten: Gildenmarkt-Verkäufe und Gildenbank-Freigaben Brief für Brief

local POTION = "|cffffffff|Hitem:13446::::::::60:::::|h[Großer Heiltrank]|h|r"
local RANKS = { "Gildenleitung", "Offizier", "Raidleitung", "Mitglied", "Neuling" }

local function Welt(name, count)
    local first, last = name:match("^(%S+) (%S+)$")
    local w = login({ guild = "Elternabend", name = first, surname = last, roster = {
        { name = "Anna Sturmwind", online = true, rank = "Offizier", rankIndex = 1 },
        { name = "Beta Lux", online = true, rank = "Mitglied", rankIndex = 3 },
        { name = "Greta Glutherz", online = true, rank = "Mitglied", rankIndex = 3 },
    } })
    w.env.GuildControlGetNumRanks = function() return #RANKS end
    w.env.GuildControlGetRankName = function(i) return RANKS[i] end
    w.env.C_Item.GetItemCount = function() return count or 20 end
    w:advance(40)
    return w
end

local function Mailbox(w, filled)
    w.env.SendMailNameEditBox = { SetText = function(_, t) filled.name = t end }
    w.env.SendMailSubjectEditBox = { SetText = function(_, t) filled.subject = t end }
    w.env.SendMailMoney = {}
    w.env.MoneyInputFrame_SetCopper = function(_, c) filled.cod = c end
    w.env.SendMailRadioButton_OnClick = function(i) filled.radio = i end
end

test("Briefkasten: Fenster listet Verkäufe, „Brief vorbereiten“, nach dem Abschicken gleich der nächste", function()
    local seller = Welt("Anna Sturmwind", 20)
    local b1 = Welt("Beta Lux")
    local b2 = Welt("Greta Glutherz")
    local _, o = seller.ns.Market:Post({ link = POTION, kind = "s", price = 1000 })
    for _, b in ipairs({ b1, b2 }) do
        b.ns.Market:Receive(seller.ns.Market:Serialize(seller.ns.db.market.offers[o.id]))
        b.ns.Market:Buy(o.id, 3)
        seller.ns.Market:Receive(b.ns.Market:Serialize(b.ns.db.market.offers[o.id]))
        seller:advance(1)
    end
    local filled = {}
    Mailbox(seller, filled)
    seller:fire("MAIL_SHOW")
    seller:advance(1)
    local f = seller.ns.UI.mailHelper
    check(f and f:IsShown(), "Fenster fehlt")
    equal(f.title:GetText(), "2 Briefe zu verschicken")
    seller:call(f.go:GetScript("OnClick"))
    local first = filled.name
    check(first == "Beta Lux" or first == "Greta Glutherz", tostring(first))
    equal(filled.cod, 3000)
    -- abschicken
    seller.ns.Market.sendingTo = first
    seller:fire("MAIL_SEND_SUCCESS")
    seller:advance(2)
    equal(f.title:GetText(), "1 Brief zu verschicken")
    check(filled.name ~= first, "nächster Brief nicht vorbereitet")
    seller.ns.Market.sendingTo = filled.name
    seller:fire("MAIL_SEND_SUCCESS")
    seller:advance(2)
    check(not f:IsShown(), "Fenster bleibt trotz nichts zu tun")
    noErrors(seller)
end)

test("Briefkasten: kein Fenster, wenn nichts zu verschicken ist", function()
    local w = Welt("Beta Lux")
    w:fire("MAIL_SHOW")
    w:advance(1)
    check(not (w.ns.UI.mailHelper and w.ns.UI.mailHelper:IsShown()), "Fenster ohne Briefe")
    noErrors(w)
end)

test("Briefkasten: Fenster bekommt eine Position (neue Frames sind im Spiel sofort sichtbar)", function()
    local w = Welt("Anna Sturmwind", 20)
    local create = w.env.CreateFrame
    w.env.CreateFrame = function(kind, name, ...)
        local f = create(kind, name, ...)
        if name == "ElternabendBriefkasten" then
            f:Show() -- wie im Spiel
            local set = f.SetPoint
            f.SetPoint = function(self, ...) self.placed = true return set(self, ...) end
        end
        return f
    end
    w.ns.Post.List = function() return { { kind = "bank", id = "x", who = "Beta Lux", t = 1, text = "1x Leder" } } end
    w.ns.Market.mailOpen = true
    w:call(w.ns.UI.ShowMailHelper, w.ns.UI)
    local f = w.ns.UI.mailHelper
    check(f:IsShown() and f.placed, "Fenster ohne Position")
    noErrors(w)
end)
