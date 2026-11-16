-- Der Regler am rechten Rand der Listen: Mausrad, Ziehen mit der Maus, Klick in die Leiste.

-- Eine Liste mit 200 Pixeln Höhe und 600 Pixeln, die darunter noch kommen.
-- Der Regler ist dann 50 Pixel hoch und hat 150 Pixel Weg; die Leiste beginnt oben bei y = 500.
local function Liste(range)
    local w = login({ guild = "Elternabend" })
    local sf
    w:call(function() sf = w.ns.Theme.Scroll(w:NewFrame("Frame")) end)
    local scroll = 0
    rawset(sf, "GetHeight", function() return 200 end)
    rawset(sf, "GetVerticalScrollRange", function() return range or 600 end)
    rawset(sf, "GetVerticalScroll", function() return scroll end)
    rawset(sf, "SetVerticalScroll", function(_, v) scroll = v end)
    local maus = { y = 500, unten = false }
    w.env.GetCursorPosition = function() return 0, maus.y end
    w.env.IsMouseButtonDown = function() return maus.unten end
    w:call(sf.UpdateThumb)
    local function druecken(y)
        maus.y, maus.unten = y, true
        w:call(sf.bar:GetScript("OnMouseDown"), sf.bar, "LeftButton")
    end
    local function ziehen(y)
        maus.y = y
        w:advance(1)
    end
    local function loslassen()
        maus.unten = false
        w:call(sf.bar:GetScript("OnMouseUp"), sf.bar, "LeftButton")
    end
    return w, sf, function() return scroll end, druecken, ziehen, loslassen
end

test("Regler: Klick in die Leiste springt an die Stelle", function()
    local w, sf, stand, druecken, _, loslassen = Liste()
    check(sf.bar:IsShown(), "Leiste fehlt, obwohl es etwas zu scrollen gibt")
    druecken(375) -- 125 Pixel unter der Oberkante, Regler mittig darunter
    equal(stand(), 400)
    loslassen()
    noErrors(w)
end)

test("Regler: mit gedrückter Maus ziehen, bis ans Ende und nicht weiter", function()
    local w, _, stand, druecken, ziehen, loslassen = Liste()
    druecken(490) -- auf den Regler selbst: nichts springt
    equal(stand(), 0)
    ziehen(460)
    equal(stand(), 120)
    ziehen(100) -- weit unter der Liste
    equal(stand(), 600)
    ziehen(900) -- weit darüber
    equal(stand(), 0)
    loslassen()
    noErrors(w)
end)

test("Regler: nach dem Loslassen folgt er der Maus nicht mehr", function()
    local w, sf, stand, druecken, ziehen, loslassen = Liste()
    druecken(490)
    ziehen(460)
    loslassen()
    ziehen(300)
    equal(stand(), 120)
    check(sf.bar:GetScript("OnUpdate") == nil, "OnUpdate läuft nach dem Loslassen weiter")
    noErrors(w)
end)

test("Regler: Maustaste außerhalb losgelassen – das Ziehen endet trotzdem", function()
    local w, sf, stand, druecken, ziehen = Liste()
    druecken(490)
    ziehen(460)
    w.env.IsMouseButtonDown = function() return false end
    ziehen(300)
    equal(stand(), 120)
    check(sf.bar:GetScript("OnUpdate") == nil, "OnUpdate läuft weiter")
    noErrors(w)
end)

test("Regler: rechte Maustaste tut nichts", function()
    local w, sf, stand = Liste()
    w.env.GetCursorPosition = function() return 0, 375 end
    w:call(sf.bar:GetScript("OnMouseDown"), sf.bar, "RightButton")
    equal(stand(), 0)
    noErrors(w)
end)

test("Regler: das Mausrad geht weiterhin", function()
    local w, sf, stand = Liste()
    w:call(sf:GetScript("OnMouseWheel"), sf, -1)
    equal(stand(), 44)
    w:call(sf:GetScript("OnMouseWheel"), sf, 1)
    w:call(sf:GetScript("OnMouseWheel"), sf, 1)
    equal(stand(), 0)
    noErrors(w)
end)

test("Regler: kurze Liste – keine Leiste, Klick ohne Wirkung", function()
    local w, sf, stand = Liste(0)
    check(not sf.bar:IsShown(), "Leiste sichtbar, obwohl alles hineinpasst")
    w.env.GetCursorPosition = function() return 0, 375 end
    w:call(sf.bar:GetScript("OnMouseDown"), sf.bar, "LeftButton")
    equal(stand(), 0)
    noErrors(w)
end)
