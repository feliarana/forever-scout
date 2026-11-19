// Loads addon/TrailScout/TrailScout.lua in a Lua VM (fengari) against tests/wow_stub.lua
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

const ADDON = path.join(__dirname, "..", "addon", "TrailScout", "TrailScout.lua");
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
  exec(L, fs.readFileSync(ADDON, "utf8"), "TrailScout.lua");
  exec(L, body, "test");
}

// Shared Lua helpers: log in and let the first snapshot, welcome line and alert check run.
const LOGIN = `
  local function login()
    STUB.fire("PLAYER_LOGIN")
    STUB.advance(12)
  end
  local function slash(text) SlashCmdList.TRAILSCOUT(text) end
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
    local snap = TrailScoutDB
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
    assert(TrailScoutDB.level == 30)
    STUB.bags[0] = { size = 16 }
    STUB.player.level = 31
    STUB.fire("PLAYER_LOGOUT")
    assert(TrailScoutDB.level == 30, "torn-down logout data replaced the snapshot")
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
    for _, item in ipairs(TrailScoutDB.bags) do
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
    local deaths = TrailScoutHistory.deaths
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
    assert(TrailScoutDB.xp == 7000, "snapshot rebuilt during combat")
    STUB.inCombat = false
    STUB.advance(20)
    assert(TrailScoutDB.xp == 9999, "snapshot did not catch up after combat")
  `);
});

test("heavy sections are cached until their event or an explicit /scout", () => {
  withAddon(ONE_ITEM, LOGIN + `
    login()
    STUB.completedQuests = { 1, 2, 3, 4 }
    STUB.advance(20)
    assert(#TrailScoutDB.completedQuests == 3, "cache was rebuilt without an event")
    STUB.fire("QUEST_TURNED_IN")
    STUB.advance(20)
    assert(#TrailScoutDB.completedQuests == 4, "QUEST_TURNED_IN did not invalidate the cache")
    STUB.completedQuests = { 1, 2, 3, 4, 5 }
    slash("")
    assert(#TrailScoutDB.completedQuests == 5, "/scout must rebuild everything")
  `);
});

test("XP pace: the session survives a reload and reports a rate after five minutes", () => {
  withAddon(ONE_ITEM, LOGIN + `
    login()
    STUB.fire("PLAYER_XP_UPDATE")
    STUB.player.xp = 8000
    STUB.fire("PLAYER_XP_UPDATE")
    STUB.advance(20)
    assert(TrailScoutDB.pace.sessionXP == 1000)
    local started = TrailScoutHistory.pace.start
    STUB.fire("PLAYER_LOGIN")  -- a /reload
    STUB.advance(20)
    assert(TrailScoutHistory.pace.start == started, "reload reset the session")
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
    assert(STUB.said("/scout weights") and STUB.said("/whereis") and STUB.said("Privacy:"))
    assert(#STUB.chat == 12, "help should be twelve lines for a class with weights, got " .. #STUB.chat)
    assert(STUB.said("/scout config"))
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
    STUB.player.class = "MONK"  -- not a Forever class: stands for any class with no set
    ROBE = STUB.item({ id = 105, name = "Silk Robe", equipLoc = "INVTYPE_ROBE", classID = 4, subClassID = 1,
      stats = { ITEM_MOD_INTELLECT_SHORT = 9, ITEM_MOD_STAMINA_SHORT = 4 } })
  `, LOGIN + `
    slash(ROBE)
    assert(STUB.said("no stat weights for your class yet"), "missing-weights message not shown")
    assert(not STUB.said("NEED") and not STUB.said("GREED"))

    STUB.clearChat()
    slash("weights bogus=3")
    assert(STUB.said('unknown stat "bogus"'))
    assert(TrailScoutHistory.weights == nil, "an invalid line must not save anything")

    STUB.clearChat()
    slash("weights int=1 sta=0.5")
    assert(TrailScoutHistory.weights.int == 1 and TrailScoutHistory.weights.sta == 0.5)
    assert(STUB.said("int=1") and STUB.said("yours"))

    STUB.clearChat()
    slash(ROBE)
    assert(STUB.said("NEED"), "with intellect weighted, the robe is an upgrade")
    slash("weights reset")
    assert(TrailScoutHistory.weights == nil)
  `);
});

const ROBE = `
  ROBE = STUB.item({ id = 105, name = "Silk Robe", equipLoc = "INVTYPE_ROBE", classID = 4, subClassID = 1,
    stats = { ITEM_MOD_INTELLECT_SHORT = 9, ITEM_MOD_STAMINA_SHORT = 4 } })
  HEALROBE = STUB.item({ id = 106, name = "Robe of Mending", equipLoc = "INVTYPE_ROBE", classID = 4, subClassID = 1,
    stats = { ITEM_MOD_SPELL_HEALING_DONE_SHORT = 20, ITEM_MOD_CRIT_SPELL_RATING_SHORT = 1 } })
`;

test("every class has built-in weights: a mage gets loot advice with nothing to set up", () => {
  withAddon(GEAR + ROBE + `STUB.player.class = "MAGE"`, LOGIN + `
    slash(ROBE)
    assert(STUB.said("NEED"), "intellect and stamina are worth something to a mage out of the box")
    STUB.clearChat()
    slash(BETTER)
    assert(STUB.said("too heavy"), "a mage cannot wear leather")
    STUB.clearChat()
    slash("weights")
    assert(STUB.said("stat weights (class default: Spell damage): ") and STUB.said("sp=1") and STUB.said("spellcrit=9"))
    slash("")
    assert(TrailScoutDB.weights.role == "caster" and TrailScoutDB.weights.values.int == 1.1,
      "the snapshot must carry the weights in use for the offline tools")
  `);
  // The nine classes of the game, each with at least one role.
  const source = fs.readFileSync(ADDON, "utf8");
  const roles = source.slice(source.indexOf("local CLASS_ROLES = {"), source.indexOf("local ROLE_LABELS"));
  for (const cls of ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"]) {
    assert.match(roles, new RegExp("^  " + cls + " = \\{\\s*\\{ key = \"", "m"), cls + " has no weights");
  }
});

test("a class with several roles picks one, and its own numbers still win", () => {
  withAddon(GEAR + ROBE + `STUB.player.class = "PRIEST"`, LOGIN + `
    -- Leveling priests default to damage: a healing robe is worth little.
    slash(HEALROBE)
    local asDamage = STUB.chat[#STUB.chat]
    slash("weights healer")
    assert(TrailScoutHistory.weightRole == "healer")
    assert(STUB.said("stat weights (class default: Healer): ") and STUB.said("heal=1"))
    STUB.clearChat()
    slash(HEALROBE)
    assert(STUB.said("NEED") and STUB.chat[#STUB.chat] ~= asDamage, "healing must count for a healer")
    -- 20 healing and 1% spell crit at 6 make 26 points, against 2.4 for the vest she wears.
    assert(STUB.said("+23.6"), STUB.chat[#STUB.chat])

    STUB.clearChat()
    slash("weights tank")
    assert(STUB.said("your class has no weights for that role.") and TrailScoutHistory.weightRole == "healer")

    -- Tuning one stat keeps the rest of the role's set; picking a role again drops the tuning.
    slash("weights heal=2")
    assert(TrailScoutHistory.weights.heal == 2 and TrailScoutHistory.weights.int == 1.2)
    slash("weights caster")
    assert(TrailScoutHistory.weights == nil and TrailScoutHistory.weightRole == "caster")
  `);
  withAddon(GEAR + `STUB.player.class = "DRUID"; STUB.locale = "esMX"`, LOGIN + `
    login()
    slash("weights sanador")
    assert(TrailScoutHistory.weightRole == "healer" and STUB.said("por defecto de la clase: Sanador"))
    slash("config")
    local frame = TrailScoutOptionsFrame
    assert(#frame.roles == 3 and frame.roles[1].text == "Daño cuerpo a cuerpo" and frame.roles[3].text == "Sanador")
    STUB.click(frame.roles[2])
    assert(TrailScoutHistory.weightRole == "caster" and frame.weights.text:find("sp=1", 1, true))
    assert(frame.weightsSource.text:find("Daño con hechizos", 1, true), frame.weightsSource.text)
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
    local text = TrailScoutCopyFrame.box.text
    assert(text:find("FX1", 1, true) and text:find("level 30", 1, true), "summary header missing")
    assert(text:find("QUESTION: where do I go next?", 1, true))
    assert(TrailScoutDB.question == "where do I go next?")
    -- The box says what the text is, in the client language, with its length.
    assert(TrailScoutCopyFrame.info.text:find("Resumen de tu personaje (" .. #text .. " caracteres)", 1, true))
    assert(TrailScoutCopyFrame.box.cursor == 0, "the box must show the start of the summary")
  `);
});

test("the summary names the class and the talents, with options when a point is free or asked about", () => {
  withAddon(ONE_ITEM, LOGIN + `
    slash("where do I go next?")
    local text = TrailScoutCopyFrame.box.text
    assert(text:find("HUNTER", 1, true), "the class is missing from the summary")
    assert(text:find("talents (0 unspent): Endurance Training 3/5", 1, true), "taken talents missing")
    assert(not text:find("that can take a point", 1, true), "options belong to the talent question")

    -- The talent question lists where a point could go, with the game's description.
    slash("Where should I put my next talent points for my class and the way I am playing?")
    text = TrailScoutCopyFrame.box.text
    assert(text:find("talents that can take a point: Endurance Training 3/5: Increases the Health of your pet by 15%.", 1, true),
      "talent options missing from the talent question")
  `);
  withAddon(ONE_ITEM, LOGIN + `
    slash("que talentos me conviene poner?")
    assert(TrailScoutCopyFrame.box.text:find("talents that can take a point", 1, true),
      "a typed question about talents must bring the options too")
  `);
  withAddon(ONE_ITEM + `STUB.talentPoints = 1 STUB.legacy = { points = 1, placeholders = true }`, LOGIN + `
    slash("where do I go next?")
    local text = TrailScoutCopyFrame.box.text
    assert(text:find("talents (1 unspent)", 1, true) and text:find("talents that can take a point", 1, true),
      "a free point must bring the options along")
    assert(text:find("Legacy (1 unspent): Skilled Skinner 2/3", 1, true), "perk trees missing")
    assert(text:find("Legacy that can take a point: Well Rested 0/5", 1, true), "perk options missing")
    local _, placeholders = text:gsub("Unknown 0/1", "")
    assert(placeholders == 1, "perks not released yet must be listed once, got " .. placeholders)
  `);
});

// A three-stop route as tools/map_route.py --addon writes it into Route.lua: a waypoint,
// a quest objective and a turn-in, all on the map the stub player stands on (1424).
const ROUTE = `
  TrailScoutRoute = { title = "Route: Hillsbrad", createdAt = "2026-11-16 09:00:00", loop = false, points = {
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
    assert(TrailScoutHistory.routeState == nil)
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

// Quest data for route imports: quest 514 wants ten Mudsnout Blossoms (item 3502, picked
// from object 1728) and Hillsbrad Farmers killed; it is turned in to Apothecary Lydon.
const ROUTE_QUESTS = `
  STUB.questie.npcs[2300] = { name = "Hillsbrad Farmer", zone = 267, x = 33.4, y = 38.9, dist = 300 }
  STUB.questie.items[3502] = { name = "Mudsnout Blossom", objectDrops = { 1728 } }
  STUB.questie.quests[514] = { name = "Elixir of Agony",
    objectives = { { { 2300, "Farmers slain" } }, nil, { { 3502 } } },
    finishedBy = { { 2216 }, nil } }
`;

test("route import: a line from an AI chat becomes a route placed from Questie's data", () => {
  withAddon(ONE_ITEM + QUESTIE + ROUTE_QUESTS + `
    STUB.installTomTom()
    STUB.x, STUB.y = 0.30, 0.30
  `, LOGIN + `
    -- Code fence, line break and a final period, as chats tend to answer.
    slash("import \`\`\`TSR1; Hillsbrad run; q514; find mudsnout;\\nat 1424 61 20 Tarren Mill; t514.\`\`\`")
    assert(STUB.said("route imported: Hillsbrad run (4 stops)."), "import not confirmed")
    local route = TrailScoutHistory.importedRoute
    assert(route and #route.points == 4, "route not saved")
    -- The quest sends the player to two places, so it gets two stops: the farmers and the
    -- blossoms (named after the item to collect). "find mudsnout" is that same spot.
    local quest, find, at, turnin = route.points[1], route.points[2], route.points[3], route.points[4]
    assert(quest.label == "1. Elixir of Agony: Hillsbrad Farmer" and quest.kind == "quest" and quest.m == 1267 and quest.x == 33.4)
    assert(find.label == "2. Elixir of Agony: Mudsnout Blossom (+1)" and find.kind == "quest" and find.y == 61.3, find.label)
    assert(at.label == "3. Tarren Mill" and at.m == 1424 and at.x == 61 and at.y == 20 and at.kind == "poi")
    assert(turnin.label == "4. Turn in Elixir of Agony: Apothecary Lydon" and turnin.kind == "turnin" and turnin.x == 61.4)
    -- It starts right away, and plain /scout route finds it again.
    assert(STUB.arrow == "1. Elixir of Agony: Hillsbrad Farmer" and STUB.waypointCount() == 4)
    slash("route clear")
    slash("route")
    assert(STUB.arrow == "1. Elixir of Agony: Hillsbrad Farmer", "the imported route must stay loaded")
  `);
});

test("route import: finished objectives are skipped and unknown stops are reported", () => {
  withAddon(ONE_ITEM + QUESTIE + ROUTE_QUESTS + `
    STUB.installTomTom()
    STUB.quests = { { id = 514, title = "Elixir de agonía", level = 24,
      objectives = { { text = "Hillsbrad Farmer slain: 6/6", finished = true },
                     { text = "Mudsnout Blossom: 2/10", finished = false } } } }
  `, LOGIN + `
    login()
    slash("TSR1; q514; q999; find nobody here; dance a little; t999")
    local route = TrailScoutHistory.importedRoute
    -- The farmers are done, so the stop is at the blossoms; the title is the log's own.
    assert(#route.points == 1 and route.points[1].label == "1. Elixir de agonía: Mudsnout Blossom", route.points[1].label)
    assert(route.title == "Route from the AI")
    assert(STUB.said("4 stops left out"), "problems not reported")
    assert(STUB.said("q999 (no place known for this quest)") and STUB.said("find nobody here (name not found)"))
    assert(STUB.said("dance a little (not understood)"))
  `);
});

test("route import: works without Questie for plain places, falls back to where a quest was accepted", () => {
  withAddon(ONE_ITEM + `STUB.installTomTom()`, LOGIN + `
    slash("import nothing useful")
    assert(STUB.said("that is not a route line"), "a line without the tag must be refused")
    slash("import TSR1; q514")
    assert(STUB.said("no stop of that route could be placed") and STUB.said("q514 (Questie is needed)"))
    assert(not (TrailScoutHistory and TrailScoutHistory.importedRoute), "nothing is saved when no stop could be placed")
    slash("import TSR1; at 1424 50.5, 40 ")
    assert(TrailScoutHistory.importedRoute.points[1].label == "1. 50.5, 40.0")
  `);
  withAddon(ONE_ITEM + QUESTIE + `STUB.installTomTom()`, LOGIN + `
    TrailScoutHistory = { questGivers = { [777] = { name = "Krusk", mapID = 1424, x = 63.2, y = 20.7 } } }
    slash("import TSR1; t777")
    local point = TrailScoutHistory.importedRoute.points[1]
    assert(point.m == 1424 and point.x == 63.2 and point.label:find("where you accepted it", 1, true), point.label)

    -- A "go to this place" quest has only a spot in the database.
    STUB.questie.quests[888] = { name = "Scout the tower", triggerEnd = { "Tower scouted", { [267] = { { 52.3, 47.8 } } } } }
    slash("import TSR1; q888")
    point = TrailScoutHistory.importedRoute.points[1]
    assert(point.m == 1267 and point.x == 52.3 and point.label == "1. Scout the tower: Tower scouted", point.label)
  `);
});

test("route import: a quest gets a stop per place, counting vendors, and nearby objectives share one", () => {
  withAddon(ONE_ITEM + QUESTIE + `
    STUB.installTomTom()
    STUB.questie.npcs[10] = { name = "Snapjaw", zone = 267, x = 63.8, y = 35.6, dist = 500 }
    STUB.questie.npcs[11] = { name = "Derak Nightfall", zone = 267, x = 62.6, y = 19.0, dist = 5 }
    STUB.questie.npcs[12] = { name = "Farmer Ray", zone = 267, x = 33.2, y = 34.8, dist = 900 }
    STUB.questie.npcs[13] = { name = "Farmer Getz", zone = 267, x = 35.2, y = 38.0, dist = 950 }
    STUB.questie.items[1] = { name = "Turtle Meat", npcDrops = { 10 } }
    STUB.questie.items[2] = { name = "Soothing Spices", vendors = { 11 } }
    STUB.questie.quests[7321] = { name = "Soothing Turtle Bisque", objectives = { nil, nil, { { 1 }, { 2 } } } }
    STUB.questie.npcs[14] = { name = "Hillsbrad Farmhand", zone = 267, x = 34.0, y = 37.0, dist = 920 }
    STUB.questie.quests[527] = { name = "Battle of Hillsbrad", objectives = { { { 12 }, { 13 }, { 14 } } } }
  `, LOGIN + `
    slash("import TSR1; q7321; q527")
    local points = TrailScoutHistory.importedRoute.points
    assert(#points == 3, "expected 3 stops, got " .. #points)
    -- The vendor next door must not hide the turtles: each item is its own stop.
    assert(points[1].label == "1. Soothing Turtle Bisque: Turtle Meat" and points[1].x == 63.8, points[1].label)
    assert(points[2].label == "2. Soothing Turtle Bisque: Soothing Spices" and points[2].x == 62.6, points[2].label)
    -- Farmers in the same fields are one stop that names the first two and counts the rest.
    assert(points[3].label == "3. Battle of Hillsbrad: Farmer Ray + Farmer Getz (+1)", points[3].label)
  `);
});

test("route import: stops in a row at the same place are one stop", () => {
  withAddon(ONE_ITEM + QUESTIE + ROUTE_QUESTS + `STUB.installTomTom()`, LOGIN + `
    -- Lydon stands at 61.4, 19.1: the turn-in and the two places next to him share a stop.
    slash("import TSR1; at 1267 61 20 Tarren Mill; t514; at 1267 62 19.5 Inn; at 1267 30 40 Fields; at 1267 61 20 Tarren Mill")
    local points = TrailScoutHistory.importedRoute.points
    assert(#points == 3, "expected 3 stops, got " .. #points)
    assert(points[1].label == "1. Tarren Mill (+2)" and points[1].kind == "turnin", points[1].label .. " " .. points[1].kind)
    assert(points[2].label == "2. Fields" and points[3].label == "3. Tarren Mill")
    assert(STUB.said("(3 stops)"))
  `);
});

test("route import: the newer of the tool's route and the imported one is used", () => {
  withAddon(ONE_ITEM + ROUTE + `STUB.installTomTom()`, LOGIN + `
    slash("import TSR1; Mine; at 1424 10 10 First")
    slash("route")
    assert(STUB.arrow == "1. First", "an import made now is newer than the 2026-11-16 route file")
    TrailScoutHistory.importedRoute.createdAt = "2020-01-01 00:00:00"
    slash("route")
    assert(STUB.arrow == "1. Tarren Mill", "a newer route file must win over an old import")
  `);
});

test("Start page: the route question asks for a TSR1 line and the box loads it", () => {
  withAddon(ONE_ITEM + `STUB.installTomTom()`, LOGIN + `
    login()
    local frame = TrailScoutOptionsFrame
    assert(frame.questions[6].text == "Plan a route for me")
    STUB.click(frame.questions[6])
    local text = TrailScoutCopyFrame.box.text
    assert(text:find("TSR1; route name; q123; t123", 1, true), "the question must carry the line format")
    assert(text:find(" map 1424", 1, true), "the summary must carry the map number for 'at' stops")

    slash("config")
    STUB.click(frame.tabs.start)
    frame.routeBox.text = "not a route"
    STUB.click(frame.routeStart)
    assert(frame.shown and frame.routeBox.text == "not a route", "a bad line stays in the box to be fixed")
    frame.routeBox.text = "TSR1; at 1424 61 20 Tarren Mill"
    STUB.click(frame.routeStart)
    assert(not frame.shown and frame.routeBox.text == "", "a loaded route closes the window")
    assert(STUB.arrow == "1. Tarren Mill")
    -- The button beside it takes the route's waypoints off the map again.
    STUB.click(frame.routeClear)
    assert(STUB.waypointCount() == 0 and STUB.said("route cleared."))
  `);
  withAddon(ONE_ITEM + `STUB.locale = "esMX"`, LOGIN + `
    login()
    local frame = TrailScoutOptionsFrame
    assert(frame.questions[6].text == "Ármame una ruta" and frame.routeStart.text == "Empezar esta ruta")
    slash("import nada")
    assert(STUB.said("eso no es una línea de ruta"))
  `);
});

// Lua allows 200 local variables per function, and the file's top level is one function.
// Going over is a load error in game, so leave room and fail here first.
test("the addon stays under Lua's limit of 200 top-level locals", () => {
  const ast = luaparse.parse(fs.readFileSync(ADDON, "utf8"), { luaVersion: "5.1" });
  let locals = 0;
  for (const node of ast.body) {
    if (node.type === "LocalStatement") locals += node.variables.length;
    if (node.type === "FunctionDeclaration" && node.isLocal) locals += 1;
  }
  assert.ok(locals <= 198, "top-level locals: " + locals + " (limit 200): move one into a function or a table");
});

test("the placeholder Route.lua and the TOC load order are in place", () => {
  const dir = path.join(__dirname, "..", "addon", "TrailScout");
  const toc = fs.readFileSync(path.join(dir, "TrailScout.toc"), "utf8").split(/\r?\n/);
  assert.ok(toc.indexOf("Route.lua") >= 0 && toc.indexOf("Route.lua") < toc.indexOf("TrailScout.lua"),
    "Route.lua must be listed before TrailScout.lua");
  assert.doesNotThrow(() => luaparse.parse(fs.readFileSync(path.join(dir, "Route.lua"), "utf8"), { luaVersion: "5.1" }));
});

test("talents carry their description and whether a point can go there", () => {
  withAddon(ONE_ITEM + `STUB.talentPoints = 1`, LOGIN + `
    login()
    local node = TrailScoutDB.talents.trees[1].nodes[1]
    assert(node.name == "Endurance Training" and node.rank == 3 and node.max == 5)
    assert(node.desc == "Increases the Health of your pet by 15%.", "talent description missing")
    assert(node.canBuy == true and node.open == true)
    assert(TrailScoutDB.traitApi and TrailScoutDB.traitApi.C_Traits, "API names must be saved while no other system is found")
  `);
});

test("other trait systems (legacy perks) are saved with their own points", () => {
  withAddon(ONE_ITEM + `
    STUB.legacy = { points = 3 }
    STUB.spellText[901] = "Rested experience lasts 10% longer."
    STUB.spellText[902] = "Skinning yields extra leather."
  `, LOGIN + `
    login()
    local systems = TrailScoutDB.traitSystems
    assert(#systems == 1, "expected one extra trait system, got " .. #systems)
    assert(systems[1].name == "Legacy" and systems[1].systemID == 7)
    local tree = systems[1].trees[1]
    assert(tree.currencies[1].available == 3 and tree.currencies[1].spent == 2)
    assert(#tree.nodes == 2 and tree.nodes[1].name == "Well Rested" and tree.nodes[1].canBuy == true)
    assert(tree.nodes[2].desc == "Skinning yields extra leather.")
    assert(TrailScoutDB.traitApi == nil, "API names are only needed while nothing is found")
  `);
});

test("talent text that loads late is picked up by a later snapshot", () => {
  withAddon(ONE_ITEM + `STUB.spellText[900] = nil`, LOGIN + `
    login()
    assert(TrailScoutDB.talents.trees[1].nodes[1].desc == nil)
    STUB.spellText[900] = "Increases the Health of your pet by 15%."
    STUB.advance(20)
    assert(TrailScoutDB.talents.trees[1].nodes[1].desc ~= nil, "description was never retried")
  `);
});

test("spending a talent point refreshes the cached talents", () => {
  withAddon(ONE_ITEM + `STUB.talentPoints = 1`, LOGIN + `
    login()
    assert(TrailScoutDB.talents.trees[1].currencies[1].available == 1)
    STUB.talentPoints = 0
    STUB.advance(20)
    assert(TrailScoutDB.talents.trees[1].currencies[1].available == 1, "talents are cached between events")
    STUB.fire("TRAIT_CONFIG_UPDATED")
    STUB.advance(20)
    assert(TrailScoutDB.talents.trees[1].currencies[1].available == 0, "TRAIT_CONFIG_UPDATED did not refresh talents")
  `);
});

test("perk trees that load after login are picked up without an event", () => {
  withAddon(ONE_ITEM, LOGIN + `
    login()
    assert(#TrailScoutDB.traitSystems == 0)
    STUB.legacy = { points = 1 }
    STUB.spellText[901], STUB.spellText[902] = "a", "b"
    STUB.advance(40)
    assert(#TrailScoutDB.traitSystems == 1, "late perk trees were cached as empty")
  `);
});

const QUESTIE = `
  STUB.installQuestie()
  STUB.questie.npcs[2216] = { name = "Apothecary Lydon", zone = 267, x = 61.4, y = 19.1, dist = 40 }
  STUB.questie.npcs[2500] = { name = "Lydia the Far", zone = 45, x = 10, y = 10, dist = 900000 }
  STUB.questie.objects[1728] = { name = "Mudsnout Blossom", zone = 267, x = 64.4, y = 61.3, dist = 800 }
`;

test("/whereis: finds an NPC, sets the arrow and offers the map", () => {
  withAddon(ONE_ITEM + QUESTIE + `STUB.installTomTom()`, `
    SlashCmdList.TRAILSCOUTWHERE("lydon")
    assert(STUB.said("Apothecary Lydon (2216)") and STUB.said("61.4, 19.1") and STUB.said("40 yd"))
    assert(STUB.arrow == "Apothecary Lydon", "arrow not set")
    assert(STUB.said("|Haddon:TrailScout:map|h[Show on map]|h"), "map link missing from the chat line")

    -- Clicking the link, or typing /whereis map, opens the world map on the spawn's zone.
    STUB.clickLink("addon:TrailScout:map")
    assert(STUB.mapOpened == 1267, "the link did not open the map")
    STUB.mapOpened = nil
    SlashCmdList.TRAILSCOUTWHERE("map")
    assert(STUB.mapOpened == 1267, "/whereis map did not open the map")
  `);
});

test("/whereis: with no argument reads the NPC id from an obfuscated target GUID", () => {
  withAddon(ONE_ITEM + QUESTIE + `STUB.installTomTom()`, `
    STUB.target = { name = "Apothecary Lydon", id = 2216 }
    SlashCmdList.TRAILSCOUTWHERE("")
    assert(STUB.said("Apothecary Lydon (2216)"), "the target's NPC id was not read")
  `);
});

test("/whereis: also finds world objects by name", () => {
  withAddon(ONE_ITEM + QUESTIE + `STUB.installTomTom()`, `
    SlashCmdList.TRAILSCOUTWHERE("mudsnout")
    assert(STUB.said("Mudsnout Blossom (1728)") and STUB.said("64.4, 61.3"), "object not found")
    assert(STUB.arrow == "Mudsnout Blossom")
    -- A number is an NPC id: object 1728 must not be picked by "/whereis 1728".
    STUB.clearChat()
    SlashCmdList.TRAILSCOUTWHERE("1728")
    assert(STUB.said("nothing matches"), "an object was matched by NPC id")
  `);
});

test("/whereis: works without TomTom (no arrow), and explains an empty map request", () => {
  withAddon(ONE_ITEM + QUESTIE, `
    SlashCmdList.TRAILSCOUTWHERE("map")
    assert(STUB.said("nothing to show yet"))
    SlashCmdList.TRAILSCOUTWHERE("lydon")
    assert(STUB.said("Apothecary Lydon (2216)") and STUB.said("TomTom is not enabled"))
    SlashCmdList.TRAILSCOUTWHERE("map")
    assert(STUB.mapOpened == 1267)
  `);
});

test("/whereis: old aliases still work and the link is translated on esMX", () => {
  withAddon(ONE_ITEM + QUESTIE + `STUB.installTomTom() STUB.locale = "esMX"`, `
    assert(SLASH_TRAILSCOUTWHERE1 == "/whereis" and SLASH_TRAILSCOUTWHERE2 == "/where" and SLASH_TRAILSCOUTWHERE3 == "/donde")
    SlashCmdList.TRAILSCOUTWHERE("lydia")
    assert(STUB.said("otro continente") and STUB.said("[Ver en mapa]"))
  `);
});

test("pet happiness is read from C_PetInfo on Forever, with the pet's diet", () => {
  withAddon(ONE_ITEM + `
    STUB.installPetInfo()
    STUB.pet = { name = "Boar", level = 29, happiness = 1, foods = { "Meat", "Fish" } }
  `, LOGIN + `
    login()
    assert(STUB.said("Pet is unhappy"), "the unhappy alert must fire from C_PetInfo data")
    local pet = TrailScoutDB.pet
    assert(pet.happiness == 1 and pet.damagePercent == 75, "happiness missing from the snapshot")
    assert(pet.foodTypes[1] == "Meat" and pet.foodTypes[2] == "Fish", "diet missing from the snapshot")
    STUB.clearChat()
    STUB.pet.happiness = 3
    STUB.advance(400)
    assert(not STUB.said("Pet is unhappy") and not STUB.said("only content"), "a happy pet must be quiet")
  `);
});

test("recipes are filed under their own profession, not the window that was opened", () => {
  withAddon(ONE_ITEM + `STUB.installTradeSkills()`, LOGIN + `
    STUB.recipeIDs[1] = { name = "Linen Bandage", profession = "First Aid", difficulty = 3 }
    STUB.recipeIDs[2] = { name = "Wool Bandage", profession = "First Aid", difficulty = 1 }
    STUB.openProfession = "First Aid"
    STUB.fire("TRADE_SKILL_SHOW")
    local recipes = TrailScoutHistory.recipes
    assert(#recipes["First Aid"].list == 2)

    -- Fishing has no recipes: the client keeps answering with the First Aid list.
    STUB.openProfession = "Fishing"
    STUB.fire("TRADE_SKILL_SHOW")
    assert(recipes["Fishing"] == nil, "First Aid recipes were saved under Fishing")
    assert(#recipes["First Aid"].list == 2)
  `);
});

test("recipe lists copied to the wrong profession by older versions are cleaned at login", () => {
  withAddon(ONE_ITEM + `
    local bandages = { { name = "Linen Bandage", color = 3 }, { name = "Wool Bandage", color = 1 } }
    TrailScoutHistory = { recipes = {
      ["First Aid"] = { at = "2026-11-15 20:17", list = bandages },
      ["Fishing"] = { at = "2026-11-15 20:18", list = { { name = "Linen Bandage", color = 3 }, { name = "Wool Bandage", color = 1 } } },
      ["Cooking"] = { at = "2026-11-15 20:18", list = { { name = "Charred Wolf Meat", color = 0 } } },
    } }
  `, LOGIN + `
    login()
    local recipes = TrailScoutHistory.recipes
    assert(recipes["Fishing"] == nil, "the copied list was kept")
    assert(recipes["First Aid"] and recipes["Cooking"], "a real list was dropped")
  `);
});

test("logged quests carry the client's own XP, next waypoint and quest giver", () => {
  withAddon(ONE_ITEM + `
    STUB.quests = { { id = 92421, title = "Light's Justice", level = 22, xp = 1850, waypoint = { 1420, 0.652, 0.602 } },
                    { id = 549, title = "WANTED: Syndicate Personnel", level = 22 } }
  `, LOGIN + `
    -- Accepting a quest records who gave it and where the player stood.
    STUB.npc = { name = "Morbin Lightbane", id = 4488 }
    STUB.fire("QUEST_ACCEPTED", 92421)
    STUB.npc = nil
    STUB.fire("QUEST_ACCEPTED", 3, 549)  -- Classic-era argument order, started without an NPC
    login()
    local first, second = TrailScoutDB.quests[1], TrailScoutDB.quests[2]
    assert(first.xp == 1850, "quest XP from the client is missing")
    assert(first.waypoint.mapID == 1420 and first.waypoint.x == 65.2 and first.waypoint.y == 60.2)
    assert(first.giver.name == "Morbin Lightbane" and first.giver.id == 4488 and first.giver.kind == "Creature")
    assert(first.giver.mapID == 1424 and first.giver.x == 61)
    assert(second.xp == nil and second.waypoint == nil, "no data must stay empty, not zero")
    assert(second.giver and second.giver.name == nil and second.giver.x == 61, "an NPC-less accept still records the place")
  `);
});

test("zone sizes in yards are saved for every zone the client knows", () => {
  withAddon(ONE_ITEM, LOGIN + `
    login()
    local sizes = TrailScoutDB.mapSizes
    assert(sizes[1424].w == 3200 and sizes[1424].h == 2133, "Hillsbrad size wrong or missing")
    assert(sizes[1413].w == 10133, "a zone the player is not in must be measured too")
    local count = 0
    for _ in pairs(sizes) do count = count + 1 end
    assert(count == 2, "only zone maps belong in the table, got " .. count)
  `);
});

test("class supplies: warned once when low and once when out, only for what the character carried", () => {
  withAddon(`
    STUB.player.class = "SHAMAN"
    ankh = STUB.item({ id = 17030, name = "Ankh", type = "Reagent" })
    STUB.bags[0] = { size = 16 }
  `, LOGIN + `
    login()
    STUB.advance(5)
    assert(not STUB.said("Ankh"), "a reagent never carried must not warn")

    STUB.bags[0][1] = { ankh, 3 }
    STUB.fire("BAG_UPDATE_DELAYED") STUB.advance(5)
    assert(not STUB.said("Ankh"), "three ankhs is enough")
    assert(TrailScoutHistory.supplies[17030].name == "Ankh")

    STUB.bags[0][1] = { ankh, 1 }
    STUB.fire("BAG_UPDATE_DELAYED") STUB.advance(5)
    assert(STUB.said("Low on Ankh: 1 left."), "low supply alert missing")
    STUB.clearChat()
    STUB.fire("BAG_UPDATE_DELAYED") STUB.advance(400)
    assert(not STUB.said("Low on Ankh"), "the supply alert must not repeat")

    STUB.bags[0][1] = nil
    STUB.fire("BAG_UPDATE_DELAYED") STUB.advance(5)
    assert(STUB.said("No Ankh left."), "out of supply alert missing")

    -- Dying with the last one (Reincarnation) warns again once alive; the shared switch mutes it.
    STUB.clearChat()
    slash("alerts on") STUB.advance(5)
    assert(STUB.said("No Ankh left."), "the alert must come back after the alerts are reset")
    STUB.clearChat()
    TrailScoutHistory.settings = { alert_ammo = false }
    slash("alerts on") STUB.advance(5)
    assert(not STUB.said("Ankh"), "the ammo and supplies switch must mute it")
    TrailScoutHistory.settings = nil

    -- Not carried for more than a week (a perk made it unnecessary): stop watching.
    STUB.clearChat()
    TrailScoutHistory.supplies[17030].at = time() - 8 * 86400
    slash("alerts on") STUB.advance(5)
    assert(not STUB.said("Ankh"), "a supply not carried for a week must be forgotten")
  `);
  // A failure while counting supplies leaves the other reminders working.
  withAddon(`
    STUB.player.class = "SHAMAN"
    local junk = STUB.item({ id = 1, name = "Linen Cloth", type = "Trade Goods" })
    STUB.bags[0] = { size = 1, [1] = { junk, 5 } }
  `, LOGIN + `
    login()
    -- A stack count that cannot be added up, like a value the client keeps to itself.
    local real = C_Container.GetContainerItemInfo
    C_Container.GetContainerItemInfo = function(bag, slot)
      local info = real(bag, slot)
      if info then info.stackCount = {} end
      return info
    end
    STUB.clearChat()
    slash("alerts on") STUB.advance(5)
    assert(STUB.said("Bags almost full"), "a supplies failure must not silence the other alerts")
  `);
  // Soul shards are counted across every bag; a hunter carrying a reagent is not warned.
  withAddon(`
    STUB.player.class = "WARLOCK"
    shard = STUB.item({ id = 6265, name = "Soul Shard", type = "Reagent" })
    STUB.bags[0] = { size = 16, [1] = { shard, 1 } }
    STUB.bags[4] = { size = 8, [3] = { shard, 1 } }
  `, LOGIN + `
    login()
    STUB.advance(5)
    assert(not STUB.said("Soul Shard"), "two shards in different bags are enough")
    STUB.bags[4][3] = nil
    STUB.fire("BAG_UPDATE_DELAYED") STUB.advance(5)
    assert(STUB.said("Low on Soul Shard: 1 left."), "shards must be counted across bags")
  `);
  withAddon(`
    ankh = STUB.item({ id = 17030, name = "Ankh", type = "Reagent" })
    STUB.bags[0] = { size = 16, [1] = { ankh, 1 } }
  `, LOGIN + `
    login()
    STUB.advance(5)
    assert(not STUB.said("Ankh"), "another class's reagent is not this class's supply")
  `);
  withAddon(`
    STUB.player.class = "SHAMAN"
    STUB.locale = "esMX"
    ankh = STUB.item({ id = 17030, name = "Ankh", type = "Reagent" })
    STUB.bags[0] = { size = 16, [1] = { ankh, 1 } }
  `, LOGIN + `
    login()
    STUB.advance(5)
    assert(STUB.said("Queda poco de Ankh: 1."), "supply alert missing or untranslated")
  `);
});

test("/scout config opens a window with a switch per feature and the help", () => {
  withAddon(ONE_ITEM, LOGIN + `
    login()
    slash("config")
    local frame = TrailScoutOptionsFrame
    assert(frame and frame.shown, "the window did not open")
    assert(frame.pages.settings.shown and not frame.pages.help.shown, "it must open on the settings page")
    for _, key in ipairs({ "alerts", "alert_bags", "alert_durability", "alert_talents", "alert_ammo", "alert_pet",
                           "lootAdvice", "tooltip", "minimap", "floating" }) do
      assert(frame.checks[key], "no switch for " .. key)
      assert(frame.checks[key].checked == true, key .. " must start switched on")
    end
    assert(frame.checks.alert_bags.label.text == "Bags almost full")
    assert(frame.weights.text:find("agi=2.33", 1, true), "the hunter's stat weights must be shown for editing")
    assert(frame.weights.cursor == 0, "the weights line must show its start")

    -- The Help tab explains every feature.
    STUB.click(frame.tabs.help)
    assert(frame.pages.help.shown and not frame.pages.settings.shown)
    for _, word in ipairs({ "/scout", "/whereis", "/scout route", "NEED or GREED", "Questie", "cannot use the internet" }) do
      assert(frame.helpText.text:find(word, 1, true), "the help does not mention " .. word)
    end

    slash("config")   -- on another page: switches to settings instead of closing
    assert(frame.shown and frame.pages.settings.shown)
    slash("config")   -- same page again: closes
    assert(not frame.shown)
    slash("guide")
    assert(frame.shown and frame.pages.help.shown, "/scout guide opens the help page")
  `);
});

test("switching a reminder off in the window silences just that one", () => {
  withAddon(`
    local junk = STUB.item({ id = 1, name = "Linen Cloth", type = "Trade Goods" })
    STUB.bags[0] = { size = 2, [1] = { junk, 5 } }
    STUB.durability[5] = { 10, 100 }
  `, LOGIN + `
    login()
    assert(STUB.said("Bags almost full") and STUB.said("Gear at 10% durability"))
    slash("config")
    STUB.click(TrailScoutOptionsFrame.checks.alert_bags)
    assert(TrailScoutHistory.settings.alert_bags == false, "the choice must be saved per character")
    STUB.clearChat()
    STUB.advance(400)
    assert(not STUB.said("Bags almost full"), "the bags reminder kept firing")
    assert(STUB.said("Gear at 10% durability"), "other reminders must keep working")

    -- Switching it back on makes it fire again right away.
    STUB.clearChat()
    STUB.click(TrailScoutOptionsFrame.checks.alert_bags)
    STUB.advance(2)
    assert(STUB.said("Bags almost full"))

    -- The master switch is the same one "/scout alerts" uses.
    STUB.click(TrailScoutOptionsFrame.checks.alerts)
    assert(TrailScoutHistory.alerts.enabled == false)
    STUB.clearChat()
    STUB.advance(400)
    assert(not STUB.said("Bags almost full") and not STUB.said("durability"))
  `);
});

test("loot advice on rolls can be switched off; asking about an item still works", () => {
  withAddon(GEAR + `function GetLootRollItemLink() return BETTER end`, LOGIN + `
    login()
    STUB.clearChat()
    STUB.fire("START_LOOT_ROLL", 1)
    assert(STUB.said("NEED"), "roll advice is on by default")
    slash("config")
    STUB.click(TrailScoutOptionsFrame.checks.lootAdvice)
    STUB.clearChat()
    STUB.fire("START_LOOT_ROLL", 2)
    assert(not STUB.said("NEED") and not STUB.said("GREED"), "roll advice was switched off")
    slash(BETTER)
    assert(STUB.said("NEED"), "an explicit /scout <item> must still answer")
  `);
});

test("stat weights can be edited and reset from the window", () => {
  withAddon(GEAR + `STUB.player.class = "MONK"`, LOGIN + `
    login()
    slash("config")
    local frame = TrailScoutOptionsFrame
    assert(frame.weights.text == "" and #frame.roles == 0, "a class without weights starts with an empty line")
    frame.weights.text = "int=1 sta=0.5"
    STUB.click(frame.applyWeights)
    assert(TrailScoutHistory.weights.int == 1 and TrailScoutHistory.weights.sta == 0.5)
    assert(frame.weights.text == "sta=0.5 int=1", "the line is rewritten in the canonical order, got " .. frame.weights.text)
    STUB.click(frame.resetWeights)
    assert(TrailScoutHistory.weights == nil and frame.weights.text == "")
  `);
});

test("minimap button: created at login, opens the window, right-click copies, can be hidden", () => {
  withAddon(ONE_ITEM, LOGIN + `
    login()
    local button = TrailScoutMinimapButton
    assert(button and button.shown, "no minimap button after login")
    -- The window opened by itself on this first login; a left-click toggles it.
    assert(TrailScoutOptionsFrame.shown and TrailScoutOptionsFrame.page == "start")
    STUB.click(button, "LeftButton")
    assert(not TrailScoutOptionsFrame.shown, "left-click on the open Start page must close it")
    STUB.click(button, "LeftButton")
    assert(TrailScoutOptionsFrame.shown, "left-click must open the window")
    STUB.click(button, "RightButton")
    assert(TrailScoutCopyFrame and TrailScoutCopyFrame.shown, "right-click must open the copy box")
    STUB.click(TrailScoutOptionsFrame.checks.minimap)
    assert(not button.shown, "the button must hide when its switch is off")
    assert(TrailScoutHistory.settings.minimap == false)
  `);
});

test("the settings window is in Spanish on an esMX client", () => {
  withAddon(ONE_ITEM + `STUB.locale = "esMX"`, LOGIN + `
    slash("opciones")
    local frame = TrailScoutOptionsFrame
    assert(frame.checks.alert_bags.label.text == "Bolsas casi llenas")
    assert(frame.tabs.help.text == "Ayuda" and frame.actions[1].text == "Copiar resumen")
    assert(frame.helpText.text:find("Para qué sirve TrailScout", 1, true))
    assert(not frame.helpText.text:find("What TrailScout is for", 1, true), "help topics must be translated")
  `);
});

test("if the window cannot be built, /scout config falls back to the help in chat", () => {
  withAddon(ONE_ITEM, LOGIN + `
    local realCreateFrame = CreateFrame
    CreateFrame = function(frameType, name, ...)
      if name == "TrailScoutOptionsFrame" then error("no such template") end
      return realCreateFrame(frameType, name, ...)
    end
    slash("config")
    assert(STUB.said("could not be built"), "the failure must be reported, not raised")
    assert(STUB.said("/scout weights"), "the chat help must follow")
  `);
});

test("every string the addon shows has a Spanish translation, in neutral Latin American Spanish", () => {
  const source = fs.readFileSync(ADDON, "utf8");
  const literal = '"((?:[^"\\\\]|\\\\.)*)"';
  const keys = new Set([...source.matchAll(new RegExp("^\\s*L\\[" + literal + "\\]\\s*=", "gm"))].map((m) => m[1]));
  const shown = new Set([...source.matchAll(new RegExp("\\bT\\(" + literal + "\\)", "g"))].map((m) => m[1]));
  // Strings kept in tables and passed to T() later: window switches, help topics, help lines,
  // window buttons and the addon overlap categories.
  const tables = source.slice(source.indexOf("local OPTION_CHECKS"), source.indexOf("-- Create a frame from a template"));
  for (const m of tables.matchAll(new RegExp("label = " + literal, "g"))) shown.add(m[1]);
  for (const m of tables.matchAll(new RegExp("^\\s*\\{ " + literal + ",\\s*$", "gm"))) shown.add(m[1]);
  for (const m of tables.matchAll(new RegExp("^\\s+" + literal + " \\},\\s*$", "gm"))) shown.add(m[1]);
  const helpLines = source.slice(source.indexOf("local HELP_LINES = {"), source.indexOf("local function helpCommand"));
  for (const m of helpLines.matchAll(new RegExp("^\\s*" + literal + ",\\s*$", "gm"))) shown.add(m[1]);
  const actions = source.slice(source.indexOf("local actions = {"), source.indexOf("frame.actions = {}"));
  for (const m of actions.matchAll(new RegExp("\\{ " + literal + ", function", "g"))) shown.add(m[1]);
  for (const m of source.matchAll(new RegExp("\\{ label = " + literal + ", names = ", "g"))) shown.add(m[1]);
  const questions = source.slice(source.indexOf("local AI_QUESTIONS = {"), source.indexOf("local function refreshOptions"));
  for (const m of questions.matchAll(new RegExp("(?:label|question) = " + literal, "g"))) shown.add(m[1]);
  for (const m of questions.matchAll(new RegExp("local AI_STEPS = " + literal, "g"))) shown.add(m[1]);
  assert.ok(shown.size > 100, "expected to find the addon's strings, found " + shown.size);
  // Words that read the same in both languages need no entry.
  const same = new Set(["Chat", "Tooltips"]);
  const missing = [...shown].filter((text) => !keys.has(text) && !same.has(text));
  assert.deepStrictEqual(missing, [], "strings without a Spanish translation");

  // Regional verb forms (voseo) must not come back: the Spanish is for all of Latin America.
  const spanish = source.slice(source.indexOf('if clientLocale == "esMX"'), source.indexOf("local function itemIdFromLink"));
  const values = [...spanish.matchAll(new RegExp("=\\s*\\n?\\s*" + literal + "\\s*$", "gm"))].map((m) => m[1]).join("\n");
  const regional = values.match(/(?<![A-Za-zÁÉÍÓÚáéíóúñü])(vos|tenés|podés|querés|apretá|escribí|pegalo|usá|poné|mirá|probá|abrí|comprá|acá)(?![A-Za-zÁÉÍÓÚáéíóúñü])/gi);
  assert.strictEqual(regional, null, "regional forms found: " + regional);
});

test("first login opens the window on its Start page, once per character", () => {
  withAddon(ONE_ITEM, LOGIN + `
    login()
    assert(TrailScoutOptionsFrame and TrailScoutOptionsFrame.shown, "a new player must see the window without typing anything")
    assert(TrailScoutOptionsFrame.page == "start")
    TrailScoutOptionsFrame:Hide()
    login()   -- a /reload
    assert(not TrailScoutOptionsFrame.shown, "the window must not come back on every login")
  `);
});

test("Start page: a question button copies the summary with that question, in the player's language", () => {
  withAddon(ONE_ITEM, LOGIN + `
    login()
    local frame = TrailScoutOptionsFrame
    assert(#frame.questions == 7 and frame.questions[1].text == "What should I do next?")
    assert(frame.steps.text:find("press Ctrl+C", 1, true), "the steps must be on the page")
    STUB.click(frame.questions[1])
    assert(not frame.shown, "the window steps aside for the copy box")
    assert(TrailScoutCopyFrame.shown)
    assert(TrailScoutCopyFrame.box.text:find("QUESTION: What should I do next? Give me the next steps in order.", 1, true))
    assert(TrailScoutDB.question:find("What should I do next?", 1, true))

    -- Her own question, typed in the box.
    slash("config")
    STUB.click(frame.tabs.start)
    frame.ownQuestion.text = "is this dungeon worth it?"
    STUB.click(frame.askOwn)
    assert(TrailScoutCopyFrame.box.text:find("QUESTION: is this dungeon worth it?", 1, true))
  `);
  withAddon(ONE_ITEM + `STUB.locale = "esMX"`, LOGIN + `
    login()
    local frame = TrailScoutOptionsFrame
    assert(frame.tabs.start.text == "Inicio" and frame.questions[1].text == "¿Qué hago ahora?")
    STUB.click(frame.questions[3])
    local text = TrailScoutCopyFrame.box.text
    assert(text:find("puntos de talento", 1, true), "the question must be asked in Spanish")
    assert(text:find("Respóndeme en español", 1, true), "and ask for the answer in Spanish")
  `);
});

test("Start page: the search box finds things without typing a command", () => {
  withAddon(ONE_ITEM + QUESTIE + `STUB.installTomTom()`, LOGIN + `
    login()
    local frame = TrailScoutOptionsFrame
    assert(frame.findHelp.text:find("Questie (loaded)", 1, true) and frame.findHelp.text:find("TomTom (loaded)", 1, true))
    frame.findBox.text = "  lydon "
    STUB.click(frame.find)
    assert(STUB.said("Apothecary Lydon (2216)"), "the search did not run")
    assert(STUB.arrow == "Apothecary Lydon")
    STUB.click(frame.findMap)
    assert(STUB.mapOpened == 1267, "Show on map must open the map on the result")
    STUB.click(frame.findClear)
    assert(STUB.arrow == nil and STUB.said("arrow cleared."))
    STUB.clearChat()
    frame.findBox.text = "   "
    STUB.click(frame.find)
    assert(#STUB.chat == 0, "an empty search does nothing")
  `);
  withAddon(ONE_ITEM, LOGIN + `
    login()
    assert(TrailScoutOptionsFrame.findHelp.text:find("Questie (not installed or disabled)", 1, true),
      "the page must say when Questie is missing")
  `);
});

test("floating button: shown at login, opens the window, remembers where it was dragged, can be hidden", () => {
  withAddon(ONE_ITEM, LOGIN + `
    login()
    local button = TrailScoutFloatButton
    assert(button and button.shown, "no floating button after login")
    assert(button.point[1] == "LEFT" and button.point[4] == 24, "default place is the left edge of the screen")
    TrailScoutOptionsFrame:Hide()
    STUB.click(button, "LeftButton")
    assert(TrailScoutOptionsFrame.shown and TrailScoutOptionsFrame.page == "start")
    STUB.click(button, "RightButton")
    assert(TrailScoutCopyFrame.shown, "right-click must open the copy box")

    -- Dragging: the game moves the frame; on release the addon saves the new anchor.
    button.scripts.OnDragStart(button)
    button.point = { "TOPLEFT", UIParent, "TOPLEFT", 315.4, -8.6 }
    button.scripts.OnDragStop(button)
    local saved = TrailScoutHistory.floatPos
    assert(saved[1] == "TOPLEFT" and saved[3] == 315 and saved[4] == -9, "the dragged place was not saved")

    login()   -- a /reload puts it back where it was left
    assert(button.point[1] == "TOPLEFT" and button.point[4] == 315)

    STUB.click(TrailScoutOptionsFrame.checks.floating)
    assert(not button.shown and TrailScoutHistory.settings.floating == false)
    assert(TrailScoutMinimapButton.shown, "hiding one launcher must not hide the other")
  `);
});
