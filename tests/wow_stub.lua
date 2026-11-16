-- Minimal stand-in for the WoW Forever client, enough to load ForeverScout.lua in a plain
-- Lua VM and drive it from tests/addon_test.js. Only what the addon touches is modelled.
-- Tests change the STUB table (class, level, bags, target...) and read back what the addon
-- did (chat lines, saved variables).
--
-- The VM is Lua 5.3 (fengari) while the game runs Lua 5.1, so the 5.1 globals the addon
-- relies on are restored here.

unpack = unpack or table.unpack
date, time = os.date, os.time

STUB = {
  locale = "enUS",
  now = 1000,                 -- GetTime()
  chat = {},                  -- every line the addon printed
  frames = {}, timers = {}, tickers = {},
  inCombat = false, inGroup = false, dead = false,
  talentPoints = 0,
  player = { name = "Tester", class = "HUNTER", race = "Troll", faction = "Horde",
             level = 30, xp = 7000, xpMax = 47400, rested = 4000, money = 123456 },
  zone = "Hillsbrad Foothills", subZone = "Tarren Mill", mapID = 1424, x = 0.61, y = 0.20,
  target = nil,               -- { name, hostile, player }
  pet = nil,                  -- { name, level, happiness, dead }
  equipped = {},              -- [slot] = item link
  durability = {},            -- [slot] = { current, max }
  bags = { [0] = {} },        -- [bag] = { size = n, [slot] = { link, count } }
  items = {},                 -- [link] = item definition (see STUB.item)
  quests = {},                -- { id, title, level, complete, objectives }
  questCap = 40,
  completedQuests = { 1, 2, 3 },
}

-- Build an item link and register its data. `suffix` is the random-suffix ID in the link.
function STUB.item(def)
  local link = string.format("|cff1eff00|Hitem:%d:0:0:0:0:0:%d:0|h[%s]|h|r", def.id, def.suffix or 0, def.name)
  def.link = link
  STUB.items[link] = def
  return link
end

function STUB.said(text)
  for _, line in ipairs(STUB.chat) do
    if line:find(text, 1, true) then return true end
  end
  return false
end

function STUB.clearChat()
  STUB.chat = {}
end

----------------------------------------------------------------------------------------
-- Frames: any capitalized method that is not defined below is accepted and does nothing.
----------------------------------------------------------------------------------------

local function noop() end
local Methods = {}
local FrameMT = { __index = function(_, key)
  if type(key) == "string" and key:match("^%u") then return Methods[key] or noop end
end }

local function newObject(name)
  local o = setmetatable({ scripts = {}, events = {}, shown = true }, FrameMT)
  if name then _G[name] = o end
  return o
end

function Methods.SetScript(self, name, fn) self.scripts[name] = fn end
function Methods.HookScript(self, name, fn) self.scripts[name] = fn end
function Methods.RegisterEvent(self, event) self.events[event] = true end
function Methods.Show(self) self.shown = true end
function Methods.Hide(self) self.shown = false end
function Methods.SetText(self, text) self.text = text; self.cursor = #tostring(text) end
function Methods.SetCursorPosition(self, position) self.cursor = position end
function Methods.CreateFontString() return newObject() end
function Methods.AddMessage(_, text) STUB.chat[#STUB.chat + 1] = text end

function CreateFrame(_, name)
  local frame = newObject(name)
  STUB.frames[#STUB.frames + 1] = frame
  return frame
end

UIParent = newObject("UIParent")
DEFAULT_CHAT_FRAME = newObject("DEFAULT_CHAT_FRAME")
SlashCmdList = {}

-- Deliver a game event to every frame that registered it.
function STUB.fire(event, ...)
  for _, frame in ipairs(STUB.frames) do
    if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
  end
end

----------------------------------------------------------------------------------------
-- Clock and timers
----------------------------------------------------------------------------------------

function GetTime() return STUB.now end

C_Timer = {}
function C_Timer.After(seconds, fn)
  STUB.timers[#STUB.timers + 1] = { at = STUB.now + seconds, fn = fn }
end
function C_Timer.NewTicker(seconds, fn)
  local ticker = { every = seconds, next = STUB.now + seconds, fn = fn }
  function ticker:Cancel() self.cancelled = true end
  STUB.tickers[#STUB.tickers + 1] = ticker
  return ticker
end

-- Move the clock forward one second at a time, running due timers and tickers.
function STUB.advance(seconds)
  for _ = 1, seconds do
    STUB.now = STUB.now + 1
    local due, rest = {}, {}
    for _, t in ipairs(STUB.timers) do
      if t.at <= STUB.now then due[#due + 1] = t else rest[#rest + 1] = t end
    end
    STUB.timers = rest
    for _, t in ipairs(due) do t.fn() end
    for _, ticker in ipairs(STUB.tickers) do
      if not ticker.cancelled and ticker.next <= STUB.now then
        ticker.next = ticker.next + ticker.every
        ticker.fn()
      end
    end
  end
end

----------------------------------------------------------------------------------------
-- Units
----------------------------------------------------------------------------------------

function GetLocale() return STUB.locale end
function GetRealmName() return "Test Realm" end

function UnitExists(unit)
  if unit == "player" then return true end
  if unit == "target" then return STUB.target ~= nil end
  if unit == "pet" then return STUB.pet ~= nil end
  return false
end
function UnitName(unit)
  if unit == "player" then return STUB.player.name end
  if unit == "target" then return STUB.target and STUB.target.name end
  if unit == "pet" then return STUB.pet and STUB.pet.name end
end
function UnitClass(unit) if unit == "player" then return STUB.player.class, STUB.player.class end end
function UnitRace() return STUB.player.race, STUB.player.race end
function UnitFactionGroup() return STUB.player.faction end
function UnitLevel(unit)
  if unit == "pet" then return STUB.pet and STUB.pet.level end
  return STUB.player.level
end
function UnitXP() return STUB.player.xp end
function UnitXPMax() return STUB.player.xpMax end
function GetXPExhaustion() return STUB.player.rested end
function GetMoney() return STUB.player.money end
function UnitHealthMax() return 2000 end
function UnitIsPVP() return true end
function UnitCanAttack(_, unit) return unit == "target" and STUB.target ~= nil and STUB.target.hostile or false end
function UnitIsPlayer(unit) return unit == "target" and STUB.target ~= nil and STUB.target.player or false end
function UnitIsDeadOrGhost() return STUB.dead end
function UnitIsDead(unit) return unit == "pet" and STUB.pet ~= nil and STUB.pet.dead or false end
function UnitClassification() return "normal" end
function UnitCharacterPoints() return 0 end
function InCombatLockdown() return STUB.inCombat end
function IsInGroup() return STUB.inGroup end
function IsInInstance() return false, "none" end
function IsInGuild() return false end
function IsResting() return false end
function IsMounted() return false end
function GetPetHappiness() return STUB.pet and STUB.pet.happiness end
function GetPetExperience() return 10, 100 end

----------------------------------------------------------------------------------------
-- Location
----------------------------------------------------------------------------------------

function GetZoneText() return STUB.zone end
function GetRealZoneText() return STUB.zone end
function GetSubZoneText() return STUB.subZone end
function GetBindLocation() return "Splintertree Post" end

C_Map = {}
function C_Map.GetBestMapForUnit() return STUB.mapID end
function C_Map.GetMapInfo() return { name = STUB.zone } end
function C_Map.GetPlayerMapPosition()
  return { GetXY = function() return STUB.x, STUB.y end }
end

----------------------------------------------------------------------------------------
-- Items, equipment and bags
----------------------------------------------------------------------------------------

function GetItemInfo(link)
  local def = STUB.items[link]
  if not def then return nil end
  return def.name, link, def.quality or 2, def.ilvl or 30, def.reqLevel or 1, def.type or "Armor",
    def.subType or "Leather", 1, def.equipLoc or "", nil, def.sell or 100, def.classID, def.subClassID
end
function GetItemStats(link)
  local def = STUB.items[link]
  return def and def.stats or nil
end
function GetItemInfoInstant(id)
  for _, def in pairs(STUB.items) do
    if def.id == id then return id, def.type, def.subType, def.equipLoc, nil, def.classID, def.subClassID end
  end
end
function GetInventoryItemLink(_, slot) return STUB.equipped[slot] end
function GetInventoryItemID(_, slot)
  local def = STUB.items[STUB.equipped[slot] or false]
  return def and def.id
end
function GetInventoryItemDurability(slot)
  local d = STUB.durability[slot]
  if d then return d[1], d[2] end
end
function GetItemCooldown() return 0, 0 end

C_Container = {}
function C_Container.GetContainerNumSlots(bag)
  return STUB.bags[bag] and STUB.bags[bag].size or 0
end
function C_Container.GetContainerNumFreeSlots(bag)
  local contents = STUB.bags[bag]
  if not contents then return 0 end
  local used = 0
  for slot = 1, contents.size or 0 do
    if contents[slot] then used = used + 1 end
  end
  return (contents.size or 0) - used
end
function C_Container.GetContainerItemInfo(bag, slot)
  local entry = STUB.bags[bag] and STUB.bags[bag][slot]
  if not entry then return nil end
  local def = STUB.items[entry[1]]
  return { hyperlink = entry[1], stackCount = entry[2] or 1, itemID = def and def.id }
end

----------------------------------------------------------------------------------------
-- Quests
----------------------------------------------------------------------------------------

C_QuestLog = {}
function C_QuestLog.GetNumQuestLogEntries() return #STUB.quests, #STUB.quests end
function C_QuestLog.GetInfo(index)
  local q = STUB.quests[index]
  return q and { questID = q.id, title = q.title, level = q.level, isHeader = false }
end
function C_QuestLog.GetQuestObjectives(id)
  for _, q in ipairs(STUB.quests) do
    if q.id == id then return q.objectives or {} end
  end
  return {}
end
function C_QuestLog.ReadyForTurnIn(id)
  for _, q in ipairs(STUB.quests) do
    if q.id == id then return q.complete or false end
  end
  return false
end
function C_QuestLog.IsFailed() return false end
function C_QuestLog.GetAllCompletedQuestIDs() return STUB.completedQuests end
function C_QuestLog.GetMaxNumQuestsCanAccept() return STUB.questCap end

----------------------------------------------------------------------------------------
-- Talents (trait system): one tree, one node, points held as the tree currency
----------------------------------------------------------------------------------------

C_ClassTalents = {}
function C_ClassTalents.GetActiveConfigID() return 1 end

-- Config 1 is the class tree (tree 10, one node). STUB.legacy adds a second trait system
-- (system 7, config 2, tree 20) with its own points, like the Legacy perk trees.
-- STUB.spellText[spellID] is the talent description; nil means "not loaded yet".
STUB.spellText = { [900] = "Increases the Health of your pet by 15%." }
STUB.legacy = nil  -- { points = n }

local NODES = {
  [100] = { tree = 10, name = "Endurance Training", spell = 900, rank = 3, max = 5 },
  [200] = { tree = 20, name = "Well Rested", spell = 901, rank = 0, max = 5 },
  [201] = { tree = 20, name = "Skilled Skinner", spell = 902, rank = 2, max = 3 },
}

C_Traits = {}
function C_Traits.GetConfigIDBySystemID(systemID)
  if systemID == 7 and STUB.legacy then return 2 end
end
function C_Traits.GetConfigInfo(configID)
  if configID == 1 then return { treeIDs = { 10 } } end
  if configID == 2 and STUB.legacy then return { name = "Legacy", treeIDs = { 20 } } end
end
function C_Traits.GetTreeCurrencyInfo(configID)
  if configID == 2 then
    return { { traitCurrencyID = 2, spent = 2, quantity = STUB.legacy.points, maxQuantity = 16 } }
  end
  return { { traitCurrencyID = 1, spent = 20, quantity = STUB.talentPoints, maxQuantity = 21 } }
end
function C_Traits.GetTreeNodes(treeID)
  local ids = {}
  for id, node in pairs(NODES) do
    if node.tree == treeID then ids[#ids + 1] = id end
  end
  table.sort(ids)
  return ids
end
function C_Traits.GetNodeInfo(configID, nodeID)
  local node = NODES[nodeID]
  local points = configID == 2 and STUB.legacy.points or STUB.talentPoints
  return { ID = nodeID, activeRank = node.rank, maxRanks = node.max, posX = 10, posY = nodeID, entryIDs = { nodeID },
           isAvailable = true, canPurchaseRank = points > 0 and node.rank < node.max }
end
function C_Traits.GetEntryInfo(_, entryID) return { definitionID = entryID } end
function C_Traits.GetDefinitionInfo(definitionID)
  local node = NODES[definitionID]
  return { overrideName = node.name, spellID = node.spell }
end
C_Spell = {}
function C_Spell.GetSpellDescription(spellID) return STUB.spellText[spellID] end
function GetNumUnspentTalents() return 0 end

----------------------------------------------------------------------------------------
-- TomTom: not loaded by default. STUB.installTomTom() adds a stand-in that records
-- waypoints in STUB.waypoints (uid -> { map, x, y, title, crazy }) and the arrow target.
----------------------------------------------------------------------------------------

function STUB.installTomTom()
  STUB.waypoints, STUB.arrow = {}, nil
  local nextUid = 0
  TomTom = {}
  function TomTom:AddWaypoint(map, x, y, options)
    nextUid = nextUid + 1
    local uid = { id = nextUid }
    STUB.waypoints[uid] = { map = map, x = x, y = y, title = options.title, crazy = options.crazy }
    if options.crazy then STUB.arrow = options.title end
    return uid
  end
  function TomTom:RemoveWaypoint(uid)
    if STUB.waypoints[uid] and STUB.arrow == STUB.waypoints[uid].title then STUB.arrow = nil end
    STUB.waypoints[uid] = nil
  end
end

function STUB.waypointCount()
  local count = 0
  for _ in pairs(STUB.waypoints or {}) do count = count + 1 end
  return count
end

----------------------------------------------------------------------------------------
-- Questie, world map and chat links: not loaded by default.
-- STUB.installQuestie() adds a tiny Questie database: STUB.questie.npcs / .objects are
-- { [id] = { name, zone, x, y, dist } } with one spawn each (dist in yards from the player).
-- STUB.clickLink(link) plays a click on an "addon:" chat hyperlink.
----------------------------------------------------------------------------------------

function STUB.installQuestie()
  STUB.questie = { npcs = {}, objects = {} }
  local function single(tableName)
    return function(id, field)
      local e = STUB.questie[tableName][id]
      if not e then return nil end
      if field == "name" then return e.name end
      if field == "spawns" then return { [e.zone] = { { e.x, e.y, dist = e.dist } } } end
    end
  end
  local db = { NPCPointers = STUB.questie.npcs, ObjectPointers = STUB.questie.objects,
               QueryNPCSingle = single("npcs"), QueryObjectSingle = single("objects") }
  local distance = {}
  function distance.GetNearestSpawn(spawns)
    for zone, list in pairs(spawns) do return list[1], zone, list[1].dist end
  end
  local zones = {}
  function zones:GetUiMapIdByAreaId(area) return area + 1000 end
  local modules = { QuestieDB = db, DistanceUtils = distance, ZoneDB = zones }
  QuestieLoader = {}
  function QuestieLoader:ImportModule(name) return modules[name] end
end

STUB.mapOpened = nil  -- uiMapID last passed to OpenWorldMap
function OpenWorldMap(mapID) STUB.mapOpened = mapID end

local itemRefCallbacks = {}
EventRegistry = {}
function EventRegistry:RegisterCallback(event, fn, owner)
  if event == "SetItemRef" then itemRefCallbacks[#itemRefCallbacks + 1] = { fn = fn, owner = owner } end
end
function STUB.clickLink(link)
  for _, callback in ipairs(itemRefCallbacks) do
    callback.fn(callback.owner, link, "[text]", "LeftButton", DEFAULT_CHAT_FRAME)
  end
end
