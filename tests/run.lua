-- Tests ohne WoW: luajit tests/run.lua [Filter]
-- Lädt alle tests/*_test.lua, führt jeden Test in einer frischen Welt aus und meldet,
-- was schiefging. Exitcode 1 bei Fehlern (für GitHub Actions).
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local root = here .. "/.."
package.path = here .. "/?.lua;" .. package.path

local W = require("wow")
local filter = arg[1]

local tests = {}
local current
function test(name, fn) table.insert(tests, { file = current, name = name, fn = fn }) end

-- Hilfen für die Tests ------------------------------------------------------------------------------
function login(opts) return W.login(root, opts) end
function world(opts)
    local w = W.new(opts)
    W.load(w, root)
    return w
end
W.root = root

local function fail(msg, level) error(msg, (level or 1) + 2) end

function check(cond, msg) if not cond then fail(msg or "Bedingung nicht erfüllt", 1) end end
function equal(actual, expected, msg)
    if actual ~= expected then
        fail(string.format("%serwartet %s, bekommen %s", msg and (msg .. ": ") or "", tostring(expected), tostring(actual)), 1)
    end
end
-- Keine Lua-Fehler im Addon
function noErrors(w)
    if #w.errors > 0 then fail("Lua-Fehler im Addon:\n" .. table.concat(w.errors, "\n\n"), 1) end
end
-- Etwas wurde aufgezeichnet bzw. nicht aufgezeichnet (kind: print, sound, window, chat, comm, screen, popup)
function seen(w, kind, pattern)
    local hit = w:find(kind, pattern)
    if not hit then fail(string.format("kein %s mit „%s“ gefunden. Aufgezeichnet:\n%s", kind, pattern,
        table.concat(w:entries(), "\n")), 1) end
    return hit
end
function notSeen(w, kind, pattern)
    local hit = w:find(kind, pattern or "")
    if hit then fail(string.format("unerwartet %s: %s", kind, hit), 1) end
end

-- Laufen lassen -------------------------------------------------------------------------------------
local files = {}
local p = io.popen('ls "' .. here .. '"')
for f in p:lines() do if f:match("_test%.lua$") then table.insert(files, f) end end
p:close()
table.sort(files)

for _, f in ipairs(files) do
    current = f
    dofile(here .. "/" .. f)
end

local passed, failed = 0, 0
local start = os.clock()
for _, t in ipairs(tests) do
    if not filter or (t.file .. " " .. t.name):find(filter, 1, true) then
        local ok, err = xpcall(t.fn, debug.traceback)
        if ok then
            passed = passed + 1
        else
            failed = failed + 1
            print(string.format("FEHLER  %s › %s\n%s\n", t.file, t.name, err))
        end
    end
end
print(string.format("%d Tests, %d fehlgeschlagen (%.0f ms)", passed + failed, failed, (os.clock() - start) * 1000))
os.exit(failed == 0 and 0 or 1)
