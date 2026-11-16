// Loads addon/ForeverScout/ForeverScout.lua in a Lua VM (fengari) against tests/wow_stub.lua
// and checks its behaviour without the game. Run with: npm test
//
// Each test gets a fresh VM. `setup` is Lua run before the addon loads (to configure STUB),
// `body` is Lua run after it; a failed assert() fails the test.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const luaparse = require("luaparse");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const ADDON = path.join(__dirname, "..", "addon", "ForeverScout", "ForeverScout.lua");
const STUB = path.join(__dirname, "wow_stub.lua");

function exec(L, code, name) {
  const buffer = to_luastring(code);
  const status = lauxlib.luaL_loadbuffer(L, buffer, buffer.length, to_luastring("@" + name));
  if (status !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    const message = lua.lua_tojsstring(L, -1);
    lua.lua_pop(L, 1);
    throw new Error(message);
  }
}

function withAddon(setup, body) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  exec(L, fs.readFileSync(STUB, "utf8"), "wow_stub.lua");
  exec(L, setup || "", "setup");
  exec(L, fs.readFileSync(ADDON, "utf8"), "ForeverScout.lua");
  exec(L, body, "test");
}

// Shared Lua helpers: log in and let the first snapshot, welcome line and alert check run.
const LOGIN = `
  local function login()
    STUB.fire("PLAYER_LOGIN")
    STUB.advance(12)
  end
  local function slash(text) SlashCmdList.FOREVERSCOUT(text) end
`;

// A bag with one junk item so the snapshot counts as valid (it must see bag contents).
const ONE_ITEM = `
  local junk = STUB.item({ id = 1, name = "Linen Cloth", type = "Trade Goods" })
  STUB.bags[0] = { size = 16, [1] = { junk, 5 } }
`;

test("addon source is valid Lua 5.1", () => {
  assert.doesNotThrow(() => luaparse.parse(fs.readFileSync(ADDON, "utf8"), { luaVersion: "5.1" }));
});

test("login builds a complete snapshot with no section errors", () => {
  withAddon(ONE_ITEM + `
    STUB.quests = { { id = 549, title = "WANTED: Syndicate Personnel", level = 22 },
                    { id = 5881, title = "Calling in the Reserves", level = 28, complete = true } }
  `, LOGIN + `
    login()
    local snap = ForeverScoutDB
    assert(snap, "no snapshot saved")
    if snap.errors then
      for key, message in pairs(snap.errors) do error("section " .. key .. " failed: " .. message) end
    end
    assert(snap.level == 30 and snap.class == "HUNTER" and snap.race == "Troll")
    assert(#snap.quests == 2 and snap.quests[2].complete == 1)
    assert(snap.questLog.count == 2 and snap.questLog.max == 40)
    assert(#snap.completedQuests == 3)
    assert(snap.location.mapID == 1424 and snap.location.x == 61)
    assert(snap.upkeep.freeSlots == 15 and snap.upkeep.totalSlots == 16)
    assert(snap.pace and snap.pace.sessionXP == 0)
    assert(snap.talents.trees[1].nodes[1].name == "Endurance Training")
  `);
});

test("a snapshot with empty bags never overwrites a good one", () => {
  withAddon(ONE_ITEM, LOGIN + `
    login()
    assert(ForeverScoutDB.level == 30)
    STUB.bags[0] = { size = 16 }
    STUB.player.level = 31
    STUB.fire("PLAYER_LOGOUT")
    assert(ForeverScoutDB.level == 30, "torn-down logout data replaced the snapshot")
  `);
});

test("bag stacks are keyed by item string, so random suffixes stay separate", () => {
  withAddon(`
    local monkey = STUB.item({ id = 9000, suffix = 588, name = "Bandit Boots of the Monkey",
      equipLoc = "INVTYPE_FEET", classID = 4, subClassID = 2, stats = { ITEM_MOD_AGILITY_SHORT = 5 } })
    local bear = STUB.item({ id = 9000, suffix = 1200, name = "Bandit Boots of the Bear",
      equipLoc = "INVTYPE_FEET", classID = 4, subClassID = 2, stats = { ITEM_MOD_STRENGTH_SHORT = 5 } })
    local arrows = STUB.item({ id = 3030, name = "Razor Arrow", classID = 6 })
    STUB.bags[0] = { size = 16, [1] = { monkey, 1 }, [2] = { bear, 1 }, [3] = { arrows, 200 }, [4] = { arrows, 150 } }
  `, LOGIN + `
    login()
    local boots, arrows = 0, nil
    for _, item in ipairs(ForeverScoutDB.bags) do
      if item.id == 9000 then boots = boots + 1 end
      if item.id == 3030 then arrows = item end
    end
    assert(boots == 2, "expected two boot entries, got " .. boots)
    assert(arrows and arrows.count == 350, "identical stacks must still merge")
  `);
});

test("a death is logged once, with an unknown killer unless a hostile target is up", () => {
  withAddon(ONE_ITEM, LOGIN + `
    login()
    STUB.fire("PLAYER_DEAD")
    STUB.fire("PLAYER_DEAD")  -- the client fires it twice
    local deaths = ForeverScoutHistory.deaths
    assert(#deaths == 1, "duplicate death logged")
    assert(deaths[1].killer == nil and deaths[1].killerIsPlayer == nil, "unknown killer must stay empty")

    STUB.advance(60)
    STUB.target = { name = "Gankerino", hostile = true, player = true }
    STUB.fire("PLAYER_DEAD")
    assert(#deaths == 2 and deaths[2].killer == "Gankerino" and deaths[2].killerIsPlayer == true)
  `);
});

test("the periodic snapshot is skipped in combat and catches up after", () => {
  withAddon(ONE_ITEM, LOGIN + `
    login()
    STUB.inCombat = true
    STUB.player.xp = 9999
    STUB.advance(60)
    assert(ForeverScoutDB.xp == 7000, "snapshot rebuilt during combat")
    STUB.inCombat = false
    STUB.advance(20)
    assert(ForeverScoutDB.xp == 9999, "snapshot did not catch up after combat")
  `);
});

test("heavy sections are cached until their event or an explicit /scout", () => {
  withAddon(ONE_ITEM, LOGIN + `
    login()
    STUB.completedQuests = { 1, 2, 3, 4 }
    STUB.advance(20)
    assert(#ForeverScoutDB.completedQuests == 3, "cache was rebuilt without an event")
    STUB.fire("QUEST_TURNED_IN")
    STUB.advance(20)
    assert(#ForeverScoutDB.completedQuests == 4, "QUEST_TURNED_IN did not invalidate the cache")
    STUB.completedQuests = { 1, 2, 3, 4, 5 }
    slash("")
    assert(#ForeverScoutDB.completedQuests == 5, "/scout must rebuild everything")
  `);
});

test("XP pace: the session survives a reload and reports a rate after five minutes", () => {
  withAddon(ONE_ITEM, LOGIN + `
    login()
    STUB.fire("PLAYER_XP_UPDATE")
    STUB.player.xp = 8000
    STUB.fire("PLAYER_XP_UPDATE")
    STUB.advance(20)
    assert(ForeverScoutDB.pace.sessionXP == 1000)
    local started = ForeverScoutHistory.pace.start
    STUB.fire("PLAYER_LOGIN")  -- a /reload
    STUB.advance(20)
    assert(ForeverScoutHistory.pace.start == started, "reload reset the session")
  `);
});

test("first login prints the welcome line once", () => {
  withAddon(ONE_ITEM, LOGIN + `
    login()
    assert(STUB.said("Type /scout help"), "no welcome line")
    STUB.clearChat()
    login()
    assert(not STUB.said("Type /scout help"), "welcome line repeated")
  `);
});

test("/scout help lists the commands, in the client language", () => {
  withAddon(ONE_ITEM, LOGIN + `
    slash("help")
    assert(STUB.said("/scout weights") and STUB.said("/donde") and STUB.said("Privacy:"))
    assert(#STUB.chat == 11, "help should be eleven lines for a class with weights, got " .. #STUB.chat)
    assert(STUB.said("/scout route"))
    assert(STUB.said("Questie not installed or disabled, TomTom not installed or disabled"))
    TomTom = {}
    STUB.clearChat()
    slash("help")
    assert(STUB.said("TomTom loaded"), "help must report an optional addon that is present")
  `);
  withAddon(ONE_ITEM + `STUB.locale = "esMX"`, LOGIN + `
    slash("ayuda")
    assert(STUB.said("Privacidad:") and STUB.said("guarda una foto"), "help is not in Spanish")
    assert(not STUB.said("Privacy:"))
  `);
});

test("every English string passed through the help has a Spanish translation", () => {
  withAddon(ONE_ITEM + `STUB.locale = "esMX" STUB.player.class = "MAGE"`, LOGIN + `
    slash("help")
    for _, line in ipairs(STUB.chat) do
      assert(not line:find("snapshot", 1, true) and not line:find("stat weights", 1, true),
        "untranslated help line: " .. line)
    end
  `);
});

const GEAR = `
  local worn = STUB.item({ id = 100, name = "Old Vest", equipLoc = "INVTYPE_CHEST", classID = 4, subClassID = 2,
    stats = { ITEM_MOD_AGILITY_SHORT = 2, ITEM_MOD_INTELLECT_SHORT = 2 } })
  STUB.equipped[5] = worn
  BETTER = STUB.item({ id = 101, name = "Fine Vest", equipLoc = "INVTYPE_CHEST", classID = 4, subClassID = 2,
    stats = { ITEM_MOD_AGILITY_SHORT = 9, ITEM_MOD_INTELLECT_SHORT = 9 } })
  MAIL = STUB.item({ id = 102, name = "Chain Vest", equipLoc = "INVTYPE_CHEST", classID = 4, subClassID = 3,
    stats = { ITEM_MOD_AGILITY_SHORT = 20 } })
  PLATE = STUB.item({ id = 103, name = "Plate Vest", equipLoc = "INVTYPE_CHEST", classID = 4, subClassID = 4,
    stats = { ITEM_MOD_AGILITY_SHORT = 20 } })
  SHIELD = STUB.item({ id = 104, name = "Buckler", equipLoc = "INVTYPE_WEAPONOFFHAND", classID = 4, subClassID = 6,
    stats = { ITEM_MOD_STAMINA_SHORT = 20 } })
  STUB.bags[0] = { size = 16, [1] = { BETTER, 1 } }
`;

test("hunter loot advice: upgrade, and armor rules by class and level", () => {
  withAddon(GEAR, LOGIN + `
    slash(BETTER)
    assert(STUB.said("NEED") and STUB.said("upgrade"), "an agility upgrade must be NEED")
    STUB.clearChat()
    slash(MAIL)
    assert(STUB.said("GREED") and STUB.said("from level 40"), "mail before 40 is not wearable")
    STUB.clearChat()
    STUB.player.level = 40
    slash(MAIL)
    assert(STUB.said("NEED"), "mail at 40 is an upgrade for a hunter")
    STUB.clearChat()
    slash(PLATE)
    assert(STUB.said("too heavy"))
    STUB.clearChat()
    slash(SHIELD)
    assert(STUB.said("cannot use shields"))
  `);
});

test("a class without built-in weights gets a clear message, then its own weights work", () => {
  withAddon(GEAR + `
    STUB.player.class = "MAGE"
    -- A mage wears cloth: the leather vests above are too heavy for this class.
    ROBE = STUB.item({ id = 105, name = "Silk Robe", equipLoc = "INVTYPE_ROBE", classID = 4, subClassID = 1,
      stats = { ITEM_MOD_INTELLECT_SHORT = 9, ITEM_MOD_STAMINA_SHORT = 4 } })
  `, LOGIN + `
    slash(ROBE)
    assert(STUB.said("no stat weights for your class yet"), "missing-weights message not shown")
    assert(not STUB.said("NEED") and not STUB.said("GREED"))

    STUB.clearChat()
    slash("weights bogus=3")
    assert(STUB.said('unknown stat "bogus"'))
    assert(ForeverScoutHistory.weights == nil, "an invalid line must not save anything")

    STUB.clearChat()
    slash("weights int=1 sta=0.5")
    assert(ForeverScoutHistory.weights.int == 1 and ForeverScoutHistory.weights.sta == 0.5)
    assert(STUB.said("int=1") and STUB.said("yours"))

    STUB.clearChat()
    slash(ROBE)
    assert(STUB.said("NEED"), "with intellect weighted, the robe is an upgrade")
    STUB.clearChat()
    slash(BETTER)
    assert(STUB.said("too heavy"), "a mage cannot wear leather")

    slash("weights reset")
    assert(ForeverScoutHistory.weights == nil)
  `);
});

test("upkeep alerts: unspent talent point out of combat only, full bags, low durability", () => {
  withAddon(ONE_ITEM + `
    STUB.talentPoints = 1
    STUB.inCombat = true
  `, LOGIN + `
    login()
    assert(not STUB.said("unspent talent point"), "talent alert fired in combat")
    STUB.inCombat = false
    STUB.fire("PLAYER_REGEN_ENABLED")
    STUB.advance(2)
    assert(STUB.said("1 unspent talent point"), "talent alert missing out of combat")
  `);
  withAddon(`
    local junk = STUB.item({ id = 1, name = "Linen Cloth", type = "Trade Goods" })
    STUB.bags[0] = { size = 2, [1] = { junk, 5 } }
    STUB.durability[5] = { 10, 100 }
  `, LOGIN + `
    login()
    assert(STUB.said("Bags almost full: 1 free slot"))
    assert(STUB.said("Gear at 10% durability"))
    STUB.clearChat()
    slash("alerts off")
    STUB.advance(600)
    assert(not STUB.said("Bags almost full"), "alerts kept firing after /scout alerts off")
  `);
});

test("hunter alerts: low ammo and unhappy pet, in Spanish on an esMX client", () => {
  withAddon(`
    STUB.locale = "esMX"
    local arrows = STUB.item({ id = 3030, name = "Flecha navaja", classID = 6 })
    STUB.bags[0] = { size = 16, [1] = { arrows, 120 } }
    STUB.equipped[0] = arrows
    STUB.pet = { name = "Boar", level = 29, happiness = 1 }
  `, LOGIN + `
    login()
    assert(STUB.said("Poca munición: quedan 120 Flecha navaja"), "low ammo alert missing or untranslated")
    assert(STUB.said("La mascota está descontenta"), "unhappy pet alert missing or untranslated")
  `);
});

test("the copy box summary is English data whatever the client language", () => {
  withAddon(ONE_ITEM + `STUB.locale = "esMX"`, LOGIN + `
    slash("where do I go next?")
    local text = ForeverScoutCopyFrame.box.text
    assert(text:find("FX1", 1, true) and text:find("level 30", 1, true), "summary header missing")
    assert(text:find("QUESTION: where do I go next?", 1, true))
    assert(ForeverScoutDB.question == "where do I go next?")
    -- The box says what the text is, in the client language, with its length.
    assert(ForeverScoutCopyFrame.info.text:find("Resumen de tu personaje (" .. #text .. " caracteres)", 1, true))
    assert(ForeverScoutCopyFrame.box.cursor == 0, "the box must show the start of the summary")
  `);
});

// A three-stop route as tools/map_route.py --addon writes it into Route.lua: a waypoint,
// a quest objective and a turn-in, all on the map the stub player stands on (1424).
const ROUTE = `
  ForeverScoutRoute = { title = "Route: Hillsbrad", createdAt = "2026-11-16 09:00:00", loop = false, points = {
    { m = 1424, x = 61, y = 20, label = "1. Tarren Mill", kind = "poi" },
    { m = 1424, x = 64.4, y = 61.3, label = "2. Mudsnout Blossoms", kind = "loot" },
    { m = 1424, x = 61.4, y = 19.1, label = "3. Lydon: Elixir of Agony", kind = "turnin" },
  } }
`;

test("/scout route: needs a route file and TomTom, and says which one is missing", () => {
  withAddon(ONE_ITEM, LOGIN + `
    slash("route")
    assert(STUB.said("no route loaded"), "missing route not reported")
  `);
  withAddon(ONE_ITEM + ROUTE, LOGIN + `
    slash("route")
    assert(STUB.said("TomTom is not enabled"), "missing TomTom not reported")
  `);
});

test("/scout route: one waypoint per stop, arrow on the current one, advancing by kind", () => {
  withAddon(ONE_ITEM + ROUTE + `
    STUB.installTomTom()
    STUB.x, STUB.y = 0.30, 0.30  -- away from every stop
  `, LOGIN + `
    slash("route")
    assert(STUB.waypointCount() == 3, "expected three waypoints, got " .. STUB.waypointCount())
    assert(STUB.arrow == "1. Tarren Mill", "arrow must start on stop 1")
    assert(STUB.said('route "Route: Hillsbrad": 3 stops.'))

    -- A plain waypoint advances as soon as the player stands on it.
    STUB.x, STUB.y = 0.61, 0.20
    STUB.advance(2)
    assert(STUB.arrow == "2. Mudsnout Blossoms", "waypoint stop did not advance on arrival")
    assert(STUB.waypointCount() == 2, "the reached stop must be removed")

    -- A quest stop waits: farming takes time, so only "/scout route next" moves on.
    STUB.clearChat()
    STUB.x, STUB.y = 0.644, 0.613
    STUB.advance(5)
    assert(STUB.arrow == "2. Mudsnout Blossoms", "quest stop advanced by itself")
    assert(STUB.said("you reached 2. Mudsnout Blossoms"))
    assert(#STUB.chat == 1, "the arrival line must be said once, got " .. #STUB.chat)
    slash("route next")
    assert(STUB.arrow == "3. Lydon: Elixir of Agony")

    slash("route next")
    assert(STUB.said("route finished.") and STUB.waypointCount() == 0)
    assert(ForeverScoutHistory.routeState == nil)
  `);
});

test("/scout route: a reload resumes at the saved stop, a new route is announced once", () => {
  withAddon(ONE_ITEM + ROUTE + `
    STUB.installTomTom()
    STUB.x, STUB.y = 0.30, 0.30
  `, LOGIN + `
    login()
    assert(STUB.said("new route loaded: Route: Hillsbrad (3 stops)"), "new route not announced")
    slash("route 2")
    assert(STUB.arrow == "2. Mudsnout Blossoms" and STUB.waypointCount() == 2)

    -- /reload: TomTom forgets non-persistent waypoints, the addon puts them back.
    STUB.installTomTom()
    STUB.clearChat()
    login()
    assert(STUB.arrow == "2. Mudsnout Blossoms", "route not resumed after reload")
    assert(not STUB.said("new route loaded"), "a resumed route must not be announced again")

    slash("route clear")
    assert(STUB.waypointCount() == 0 and STUB.said("route cleared."))
  `);
});

test("/scout route: messages are in Spanish on an esMX client", () => {
  withAddon(ONE_ITEM + ROUTE + `
    STUB.locale = "esMX"
    STUB.installTomTom()
    STUB.x, STUB.y = 0.30, 0.30
  `, LOGIN + `
    slash("ruta")
    assert(STUB.said("próxima parada: 1. Tarren Mill (1 de 3)"), "route line missing or untranslated")
  `);
});

test("the placeholder Route.lua and the TOC load order are in place", () => {
  const dir = path.join(__dirname, "..", "addon", "ForeverScout");
  const toc = fs.readFileSync(path.join(dir, "ForeverScout.toc"), "utf8").split(/\r?\n/);
  assert.ok(toc.indexOf("Route.lua") >= 0 && toc.indexOf("Route.lua") < toc.indexOf("ForeverScout.lua"),
    "Route.lua must be listed before ForeverScout.lua");
  assert.doesNotThrow(() => luaparse.parse(fs.readFileSync(path.join(dir, "Route.lua"), "utf8"), { luaVersion: "5.1" }));
});
