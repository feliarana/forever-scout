-- ForeverScout: writes a per-character snapshot into SavedVariables.
-- WoW only flushes SavedVariables to disk on /reload, character switch or logout,
-- so /wow builds the snapshot and the following /reload writes it to disk.
--
-- Usage: /wow [optional question]  -> saves snapshot + question and shows a copy box;
-- type /reload to write the full snapshot to disk. See README.md for every feature.
-- It also remembers the last quest reward window, trainer and vendor you opened.
-- /donde <npc | party member> points a TomTom arrow at it (see where()).
-- Upkeep alerts warn about ammo, pet, bags and durability (see checkAlerts(), /wow alerts).
-- Gear tooltips get a weighted score line against what is equipped (see addTooltipScore()).

local frame = CreateFrame("Frame")

-- Data captured from windows during the session; kept until the next snapshot.
local session = {}

-- Upkeep alerts (ammo, pet, bags, durability); defined further down, used by the event handler.
local scheduleAlerts

-- Call a function safely; return nil instead of raising if the API is missing or errors.
local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  -- Lua 5.1 compatible: keep every return value (GetItemInfo returns more than ten).
  local function pack(...) return select("#", ...), { ... } end
  local n, r = pack(pcall(fn, ...))
  if r[1] then return unpack(r, 2, n) end
  return nil
end

local function itemIdFromLink(link)
  if not link then return nil end
  return tonumber(link:match("item:(%d+)"))
end

local function itemNameFromLink(link)
  if not link then return nil end
  return link:match("%[(.-)%]")
end

-- Short stat keys so the saved file stays readable.
local STAT_KEYS = {
  ITEM_MOD_AGILITY_SHORT = "agi",
  ITEM_MOD_STAMINA_SHORT = "sta",
  ITEM_MOD_STRENGTH_SHORT = "str",
  ITEM_MOD_INTELLECT_SHORT = "int",
  ITEM_MOD_SPIRIT_SHORT = "spi",
  RESISTANCE0_NAME = "armor",
  ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps",
  ITEM_MOD_ATTACK_POWER_SHORT = "ap",
  ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
  ITEM_MOD_CRIT_RATING_SHORT = "crit",
  ITEM_MOD_HIT_RATING_SHORT = "hit",
}

-- Full description of an item: quality, slot, level requirement, sell price and stats.
-- Forever exposes these under C_Item; the old globals are kept as fallbacks.
local function describeItem(link)
  if not link then return nil end
  local d = { id = itemIdFromLink(link), name = itemNameFromLink(link) }
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local _, _, quality, ilvl, reqLevel, itemType, subType, _, equipLoc, _, sellPrice = try(getInfo, link)
  d.quality, d.ilvl, d.reqLevel = quality, ilvl, reqLevel
  d.type, d.subType, d.slot, d.sell = itemType, subType, equipLoc, sellPrice
  local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
  local stats = try(getStats, link)
  if type(stats) == "table" then
    d.stats = {}
    for k, v in pairs(stats) do d.stats[STAT_KEYS[k] or k] = v end
  end
  return d
end

-- Loot advisor: scores an item with RestedXP hunter weights and compares it to what is equipped,
-- so a Need/Greed decision can be made in chat without a /reload.
local WEIGHTS = { agi = 2.33, spi = 1.12, sta = 0.75, int = 0.55, str = 0.20,
                  armor = 0.035, ap = 0.8, rap = 0.8, crit = 10, hit = 10 }
local RANGED_DPS_WEIGHT, MELEE_DPS_WEIGHT = 14, 3

-- Weapon subclasses a hunter can equip (axes, bows, guns, polearms, swords, staves, misc, fist, daggers, thrown, crossbows).
local HUNTER_WEAPONS = { [0] = true, [1] = true, [2] = true, [3] = true, [6] = true, [7] = true, [8] = true,
                         [10] = true, [13] = true, [14] = true, [15] = true, [16] = true, [18] = true }

local SLOTS_BY_EQUIPLOC = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
  INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
  INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
  INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 },
  INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}

local function scoreItem(link)
  if not link then return 0 end
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local equipLoc = select(9, try(getInfo, link))
  local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
  local stats = try(getStats, link) or {}
  local score = 0
  for key, value in pairs(stats) do
    local short = STAT_KEYS[key]
    if short == "dps" then
      local ranged = equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" or equipLoc == "INVTYPE_THROWN"
      score = score + value * (ranged and RANGED_DPS_WEIGHT or MELEE_DPS_WEIGHT)
    elseif short and WEIGHTS[short] then
      score = score + value * WEIGHTS[short]
    end
  end
  return score
end

-- Weighted score of an item against what is equipped in its slot.
-- Returns nil while the item is not cached yet. Otherwise a table with one of:
--   skip = reason        not gear the weights apply to (non-equippable, ammo, bags, shirts...)
--   unusable = reason    gear a hunter cannot wear or wield at this level
--   score, current, delta, reqLevel, equipped (true when this exact item is equipped)
local function evaluateItem(link)
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local name, _, _, _, reqLevel, _, _, _, equipLoc, _, _, classID, subClassID = try(getInfo, link)
  if not name then return nil end
  if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" then
    return { skip = "no es equipable" }
  end
  if classID == 2 and not HUNTER_WEAPONS[subClassID] then
    return { unusable = "arma que un cazador no puede usar" }
  end
  if classID == 4 then
    if subClassID == 4 or subClassID == 6 then return { unusable = "placas/escudo, no lo podés usar" } end
    if subClassID == 3 and UnitLevel("player") < 40 then return { unusable = "malla, recién al 40" } end
  end
  local slots = SLOTS_BY_EQUIPLOC[equipLoc]
  if not slots then return { skip = "ranura no reconocida (" .. tostring(equipLoc) .. ")" } end
  local result = { score = scoreItem(link), reqLevel = reqLevel }
  local id = itemIdFromLink(link)
  if equipLoc == "INVTYPE_2HWEAPON" then
    result.current = scoreItem(GetInventoryItemLink("player", 16)) + scoreItem(GetInventoryItemLink("player", 17))
    result.equipped = id ~= nil and id == itemIdFromLink(GetInventoryItemLink("player", 16))
  else
    for _, slot in ipairs(slots) do
      local equippedLink = GetInventoryItemLink("player", slot)
      local s = scoreItem(equippedLink)
      if not result.current or s < result.current then result.current = s end
      if id ~= nil and id == itemIdFromLink(equippedLink) then result.equipped = true end
    end
  end
  result.delta = result.score - (result.current or 0)
  return result
end

-- Returns verdict ("NEED", "GREED"), a short reason, and the score delta.
local function judgeItem(link)
  local e = evaluateItem(link)
  if not e then return nil end
  if e.skip or e.unusable then return "GREED", e.skip or e.unusable, 0 end
  local note = ""
  if e.reqLevel and e.reqLevel > UnitLevel("player") then note = " (requiere nivel " .. e.reqLevel .. ")" end
  if e.delta > 0.5 then
    return "NEED", string.format("mejora +%.1f puntos%s", e.delta, note), e.delta
  end
  return "GREED", string.format("no mejora lo tuyo (%.1f)%s", e.delta, note), e.delta
end

-- The weights, weapon list and armor rules above are for hunters; other classes would get
-- wrong NEED/GREED advice, so the advisor and the tooltip score only run for hunters.
local function isHunter()
  return select(2, UnitClass("player")) == "HUNTER"
end

local function adviseItem(link, attempt)
  local verdict, reason, delta = judgeItem(link)
  if not verdict then
    -- Item data may not be cached yet; retry a few times.
    if (attempt or 0) < 5 and C_Timer then C_Timer.After(0.4, function() adviseItem(link, (attempt or 0) + 1) end) end
    return
  end
  local color = verdict == "NEED" and "|cff00ff00NECESIDAD|r" or "|cffffd100CODICIA|r"
  print("|cff33ff99ForeverScout|r: " .. link .. " -> " .. color .. " (" .. reason .. ")")
  session.lastRolls = session.lastRolls or {}
  table.insert(session.lastRolls, 1, { item = describeItem(link), verdict = verdict, reason = reason,
                                       delta = math.floor((delta or 0) * 10) / 10, at = date("%H:%M:%S") })
  while #session.lastRolls > 10 do table.remove(session.lastRolls) end
end


-- Map ID, map name and x,y (percent) of a unit; nil fields when the client hides them.
local function unitMapPos(unit)
  local out = {}
  if not (C_Map and C_Map.GetBestMapForUnit) then return out end
  local mapID = try(C_Map.GetBestMapForUnit, unit)
  if not mapID then return out end
  out.mapID = mapID
  local info = try(C_Map.GetMapInfo, mapID)
  if info then out.mapName = info.name end
  local pos = try(C_Map.GetPlayerMapPosition, mapID, unit)
  if pos and pos.GetXY then
    local x, y = pos:GetXY()
    if x and y then
      out.x = math.floor(x * 10000 + 0.5) / 100
      out.y = math.floor(y * 10000 + 0.5) / 100
    end
  end
  return out
end

-- Tooltip score: one line on every gear tooltip (bags, quest rewards, vendors, links) with the
-- weighted score difference against what is equipped in that slot. Hunter weights only.
local function addTooltipScore(tooltip)
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end  -- skip comparison tooltips
  if not isHunter() then return end
  local _, link = tooltip:GetItem()
  if not link then return end
  local e = evaluateItem(link)
  if not e or e.skip then return end
  local text
  if e.unusable then
    text = "|cff808080ForeverScout: not for you (" .. e.unusable .. ")|r"
  elseif e.equipped then
    text = string.format("|cff808080ForeverScout: equipped, score %.1f|r", e.score)
  else
    local color = e.delta > 0.5 and "|cff00ff00" or (e.delta < -0.5 and "|cffff4040" or "|cffbbbbbb")
    text = string.format("%sForeverScout: %+.1f vs equipped|r |cff808080(score %.1f)|r", color, e.delta, e.score)
    if e.reqLevel and e.reqLevel > UnitLevel("player") then
      text = text .. " |cffff8000needs level " .. e.reqLevel .. "|r"
    end
  end
  tooltip:AddLine(text)
  tooltip:Show()  -- resize to fit the new line
end

-- Modern clients route every item tooltip through TooltipDataProcessor; older ones fire
-- OnTooltipSetItem. Only one of the two is hooked so the line is never added twice.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip) pcall(addTooltipScore, tooltip) end)
else
  for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tip and tip.HookScript then
      pcall(tip.HookScript, tip, "OnTooltipSetItem", function(self) pcall(addTooltipScore, self) end)
    end
  end
end

local function getLocation()
  local loc = { zone = GetZoneText(), subZone = GetSubZoneText(), realZone = GetRealZoneText() }
  for k, v in pairs(unitMapPos("player")) do loc[k] = v end
  return loc
end

-- Quest objectives through the modern C_QuestLog API.
local function questObjectives(questID)
  local list = {}
  local objectives = C_QuestLog and try(C_QuestLog.GetQuestObjectives, questID)
  if type(objectives) == "table" then
    for _, o in ipairs(objectives) do
      list[#list + 1] = { text = o.text, type = o.type, done = o.finished and true or false,
                          have = o.numFulfilled, need = o.numRequired }
    end
  end
  return list
end

local function getQuestLog()
  local quests = {}
  local header

  -- Modern API first (used by clients built on the current engine).
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    local num = try(C_QuestLog.GetNumQuestLogEntries) or 0
    for i = 1, num do
      local info = try(C_QuestLog.GetInfo, i)
      if info then
        if info.isHeader then
          header = info.title
        elseif info.questID then
          local id = info.questID
          local ready = try(C_QuestLog.ReadyForTurnIn, id) or try(C_QuestLog.IsComplete, id)
          quests[#quests + 1] = {
            id = id, title = info.title, level = info.level, group = info.suggestedGroup,
            zoneHeader = header, complete = ready and 1 or nil,
            failed = try(C_QuestLog.IsFailed, id) or nil,
            objectives = questObjectives(id),
          }
        end
      end
    end
    if #quests > 0 then return quests end
  end

  -- Classic-era fallback.
  local num = try(GetNumQuestLogEntries) or 0
  for i = 1, num do
    local title, level, suggestedGroup, isHeader, _, isComplete, _, questID = try(GetQuestLogTitle, i)
    if title then
      if isHeader then
        header = title
      else
        local q = { id = questID, title = title, level = level, group = suggestedGroup,
                    zoneHeader = header, complete = isComplete, objectives = {} }
        local nObj = try(GetNumQuestLeaderBoards, i) or 0
        for j = 1, nObj do
          local text, objType, finished = try(GetQuestLogLeaderBoard, j, i)
          q.objectives[#q.objectives + 1] = { text = text, type = objType, done = finished and true or false }
        end
        if #q.objectives == 0 and questID then q.objectives = questObjectives(questID) end
        quests[#quests + 1] = q
      end
    end
  end
  return quests
end

local function getCompletedQuests()
  local ids = {}
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    local list = try(C_QuestLog.GetAllCompletedQuestIDs)
    if list then
      for _, id in ipairs(list) do ids[#ids + 1] = id end
      return ids
    end
  end
  local map = try(GetQuestsCompleted)
  if type(map) == "table" then
    for id in pairs(map) do ids[#ids + 1] = id end
    table.sort(ids)
  end
  return ids
end

local function getEquipment()
  local gear = {}
  for slot = 0, 19 do
    local link = GetInventoryItemLink("player", slot)
    if link then gear[slot] = describeItem(link) end
  end
  return gear
end

local function getBags()
  local items = {}
  local container = C_Container
  for bag = 0, 4 do
    local slots = (container and try(container.GetContainerNumSlots, bag)) or try(GetContainerNumSlots, bag) or 0
    for slot = 1, slots do
      local link, count
      if container and container.GetContainerItemInfo then
        local info = try(container.GetContainerItemInfo, bag, slot)
        if info then link, count = info.hyperlink, info.stackCount end
      else
        local _, c, _, _, _, _, l = try(GetContainerItemInfo, bag, slot)
        link, count = l, c
      end
      if link then
        local id = itemIdFromLink(link)
        local entry = items[id]
        if entry then
          entry.count = entry.count + (count or 1)
        else
          entry = describeItem(link)
          entry.count = count or 1
          items[id] = entry
        end
      end
    end
  end
  local list = {}
  for _, v in pairs(items) do list[#list + 1] = v end
  return list
end

local function getSkills()
  local skills = {}

  -- Classic-era skill list.
  local num = try(GetNumSkillLines) or 0
  for i = 1, num do
    local name, isHeader, _, rank, _, _, maxRank = try(GetSkillLineInfo, i)
    if name and not isHeader then skills[#skills + 1] = { name = name, rank = rank, max = maxRank } end
  end
  if #skills > 0 then return skills end

  -- Modern profession API.
  local indices = { try(GetProfessions) }
  for _, index in pairs(indices) do
    if index then
      local name, _, rank, maxRank = try(GetProfessionInfo, index)
      if name then skills[#skills + 1] = { name = name, rank = rank, max = maxRank } end
    end
  end
  return skills
end

-- Full talent trees, including unspent talents, so a build can be planned from the file.
-- Forever uses the modern trait system (C_ClassTalents + C_Traits); the classic API is a fallback.
local function spellName(spellID)
  if not spellID then return nil end
  if C_Spell and C_Spell.GetSpellName then return try(C_Spell.GetSpellName, spellID) end
  return (try(GetSpellInfo, spellID))
end

local function getTraitTalents()
  if not (C_ClassTalents and C_Traits) then return nil end
  local configID = try(C_ClassTalents.GetActiveConfigID)
  if not configID then return nil end
  local config = try(C_Traits.GetConfigInfo, configID)
  if not config or not config.treeIDs then return nil end
  local result = { configID = configID, trees = {} }
  for _, treeID in ipairs(config.treeIDs) do
    local tree = { treeID = treeID, nodes = {} }
    local currencies = try(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
    if type(currencies) == "table" then
      tree.currencies = {}
      for _, c in ipairs(currencies) do
        tree.currencies[#tree.currencies + 1] = { id = c.traitCurrencyID, spent = c.spent, available = c.quantity, max = c.maxQuantity }
      end
    end
    local nodes = try(C_Traits.GetTreeNodes, treeID) or {}
    for _, nodeID in ipairs(nodes) do
      local node = try(C_Traits.GetNodeInfo, configID, nodeID)
      if node and node.ID and node.ID ~= 0 then
        local entryID = (node.activeEntry and node.activeEntry.entryID) or (node.entryIDs and node.entryIDs[1])
        local name
        if entryID then
          local entry = try(C_Traits.GetEntryInfo, configID, entryID)
          if entry and entry.definitionID then
            local def = try(C_Traits.GetDefinitionInfo, entry.definitionID)
            if def then name = def.overrideName or spellName(def.spellID) end
          end
        end
        tree.nodes[#tree.nodes + 1] = {
          name = name, rank = node.activeRank or node.currentRank, max = node.maxRanks,
          x = node.posX, y = node.posY,
        }
      end
    end
    result.trees[#result.trees + 1] = tree
  end
  return result
end

local function getTalents()
  local traits = getTraitTalents()
  if traits and #traits.trees > 0 then
    traits.unspent = try(GetNumUnspentTalents)
    return traits
  end
  local tabs = {}
  local numTabs = try(GetNumTalentTabs) or 0
  for t = 1, numTabs do
    local a, b, c, d = try(GetTalentTabInfo, t)
    local tab = { raw = { a, b, c, d }, talents = {} }
    local numTalents = try(GetNumTalents, t) or 0
    for i = 1, numTalents do
      local name, _, tier, column, rank, maxRank = try(GetTalentInfo, t, i)
      if name then
        tab.talents[#tab.talents + 1] = { name = name, tier = tier, column = column, rank = rank, max = maxRank }
      end
    end
    tabs[#tabs + 1] = tab
  end
  return { tabs = tabs, unspent = try(GetNumUnspentTalents) }
end

-- Spellbook: every known spell with its rank, grouped by spellbook tab.
local function getSpellbook()
  local tabs = {}
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    for i = 1, (try(C_SpellBook.GetNumSpellBookSkillLines) or 0) do
      local line = try(C_SpellBook.GetSpellBookSkillLineInfo, i)
      if line then
        local tab = { name = line.name, spells = {} }
        for j = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
          local item = try(C_SpellBook.GetSpellBookItemInfo, j, bank)
          if item and item.name then
            tab.spells[#tab.spells + 1] = { name = item.name, rank = item.subName, id = item.spellID,
                                            passive = item.isPassive or nil }
          end
        end
        tabs[#tabs + 1] = tab
      end
    end
    if #tabs > 0 then return tabs end
  end
  -- Classic-era fallback.
  for i = 1, (try(GetNumSpellTabs) or 0) do
    local name, _, offset, count = try(GetSpellTabInfo, i)
    if name then
      local tab = { name = name, spells = {} }
      for j = offset + 1, offset + count do
        local spellName, rank = try(GetSpellBookItemName, j, "spell")
        if spellName then tab.spells[#tab.spells + 1] = { name = spellName, rank = rank } end
      end
      tabs[#tabs + 1] = tab
    end
  end
  return tabs
end

-- Action bars: what sits in every action slot (spell, item or macro) plus key bindings
-- for the default main bar. Bartender4 uses the same action slots.
local function getActionBars()
  local slots = {}
  for slot = 1, 120 do
    local actionType, id, subType = try(GetActionInfo, slot)
    if actionType then
      local entry = { slot = slot, type = actionType }
      if actionType == "spell" then
        entry.name = (C_Spell and try(C_Spell.GetSpellName, id)) or try(GetSpellInfo, id)
      elseif actionType == "item" then
        entry.name = (C_Item and try(C_Item.GetItemNameByID, id)) or try(GetItemInfo, id)
      elseif actionType == "macro" then
        entry.name = try(GetMacroInfo, id) or try(GetActionText, slot)
      else
        entry.name = try(GetActionText, slot)
      end
      entry.subType = subType
      slots[#slots + 1] = entry
    end
  end
  local binds = {}
  for i = 1, 12 do
    local key = try(GetBindingKey, "ACTIONBUTTON" .. i)
    if key then binds[i] = key end
  end
  -- Bartender4 binds its buttons by name (button number = action slot); record all of them.
  for i = 1, 120 do
    local key = try(GetBindingKey, "CLICK BT4Button" .. i .. ":Keybind") or try(GetBindingKey, "CLICK BT4Button" .. i .. ":LeftButton")
    if key then binds["bt" .. i] = key end
  end
  return { slots = slots, binds = binds }
end

-- Active auras (buffs and debuffs) on a unit, with stacks and seconds left when readable.
local function getAuras(unit, filter)
  local list = {}
  for i = 1, 40 do
    local aura = C_UnitAuras and try(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
    if not aura then break end
    local entry = { name = aura.name, id = aura.spellId }
    -- Numeric fields may be restricted values; read them defensively.
    pcall(function()
      if aura.applications and aura.applications > 1 then entry.stacks = aura.applications end
      if aura.expirationTime and aura.expirationTime > 0 then
        entry.left = math.floor(aura.expirationTime - GetTime())
      end
    end)
    list[#list + 1] = entry
  end
  return list
end

-- Hearthstone: where it is bound and seconds left on its cooldown.
local function getHearth()
  local h = { bind = try(GetBindLocation) }
  local getCooldown = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
  local start, duration = try(getCooldown, 6948)
  pcall(function()
    if start and duration and start > 0 and duration > 0 then
      h.cooldownLeft = math.max(0, math.floor(start + duration - GetTime()))
    else
      h.cooldownLeft = 0
    end
  end)
  return h
end

-- Free bag slots and equipment durability (lowest percent and per slot below 100%).
local function getUpkeep()
  local u = { freeSlots = 0, totalSlots = 0, durability = {} }
  for bag = 0, 4 do
    local free = (C_Container and try(C_Container.GetContainerNumFreeSlots, bag)) or try(GetContainerNumFreeSlots, bag) or 0
    local total = (C_Container and try(C_Container.GetContainerNumSlots, bag)) or try(GetContainerNumSlots, bag) or 0
    u.freeSlots, u.totalSlots = u.freeSlots + free, u.totalSlots + total
  end
  local lowest = 100
  for slot = 1, 18 do
    local cur, max = try(GetInventoryItemDurability, slot)
    if cur and max and max > 0 then
      local pct = math.floor(cur / max * 100)
      if pct < 100 then u.durability[#u.durability + 1] = { slot = slot, pct = pct } end
      if pct < lowest then lowest = pct end
    end
  end
  u.lowestDurability = lowest
  return u
end

-- Flight masters: the client only lists known nodes while the flight map is open,
-- so they are stored in the per-character history and kept across sessions.
local function captureTaxi()
  local h = ForeverScoutHistory or {}
  ForeverScoutHistory = h
  h.flights = h.flights or {}
  for i = 1, (try(NumTaxiNodes) or 0) do
    local name = try(TaxiNodeName, i)
    local kind = try(TaxiNodeGetType, i)
    if name then h.flights[name] = kind end
  end
  if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and C_Map then
    local mapID = try(C_Map.GetBestMapForUnit, "player")
    local nodes = mapID and try(C_TaxiMap.GetAllTaxiNodes, mapID)
    if type(nodes) == "table" then
      for _, n in ipairs(nodes) do
        if n.name then h.flights[n.name] = n.state end
      end
    end
  end
end

-- Profession recipes: recorded whenever a profession window is opened, kept across sessions.
local function captureTradeSkill()
  local h = ForeverScoutHistory or {}
  ForeverScoutHistory = h
  h.recipes = h.recipes or {}
  local profession = try(GetTradeSkillLine)
  local list = {}
  for i = 1, (try(GetNumTradeSkills) or 0) do
    local name, kind = try(GetTradeSkillInfo, i)
    if name and kind ~= "header" then list[#list + 1] = { name = name, color = kind } end
  end
  if #list == 0 and C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
    profession = profession or (C_TradeSkillUI.GetBaseProfessionInfo and try(C_TradeSkillUI.GetBaseProfessionInfo) or {}).professionName
    for _, id in ipairs(try(C_TradeSkillUI.GetAllRecipeIDs) or {}) do
      local info = try(C_TradeSkillUI.GetRecipeInfo, id)
      if info and info.learned then list[#list + 1] = { name = info.name, color = info.relativeDifficulty } end
    end
  end
  if profession and #list > 0 then
    h.recipes[profession] = { at = date("%Y-%m-%d %H:%M"), list = list }
  end
end

local function getPet()
  if not UnitExists("pet") then return nil end
  local pet = { name = UnitName("pet"), level = UnitLevel("pet"), family = try(UnitCreatureFamily, "pet") }
  pet.happiness = try(GetPetHappiness)
  pcall(function()
    local xp, xpMax = GetPetExperience()
    pet.xp, pet.xpMax = xp, xpMax
  end)
  return pet
end

-- Lists which talent, quest, skill and item API functions exist on this client,
-- so missing data can be fixed in the next version of the addon.
local function getApiDiagnostics()
  local found = {}
  local patterns = { "Talent", "Quest", "Skill", "Profession", "Item" }
  for name, value in pairs(_G) do
    if type(name) == "string" then
      if name:match("^C_") and type(value) == "table" then
        for _, pattern in ipairs(patterns) do
          if name:find(pattern) then
            local fns = {}
            for fnName, fn in pairs(value) do
              if type(fn) == "function" then fns[#fns + 1] = fnName end
            end
            table.sort(fns)
            found[name] = fns
            break
          end
        end
      elseif type(value) == "function" and (name:find("Talent") or name:find("SkillLine") or name:find("Profession")) then
        found.globals = found.globals or {}
        found.globals[#found.globals + 1] = name
      end
    end
  end
  if found.globals then table.sort(found.globals) end
  return found
end

local function getTarget()
  if not UnitExists("target") then return nil end
  return {
    name = UnitName("target"),
    level = UnitLevel("target"),
    classification = UnitClassification("target"), -- normal, elite, rare, rareelite, worldboss
    creatureType = try(UnitCreatureType, "target"),
    family = try(UnitCreatureFamily, "target"),
    hostile = UnitCanAttack("player", "target") and true or false,
    player = UnitIsPlayer("target") and true or false,
  }
end

-- Quest window: offered or completed quest with its reward choices (with stats).
local function captureQuestWindow(kind)
  local q = { kind = kind, title = try(GetTitleText), id = try(GetQuestID), at = date("%H:%M:%S") }
  q.choices, q.rewards = {}, {}
  for i = 1, (try(GetNumQuestChoices) or 0) do
    local link = try(GetQuestItemLink, "choice", i)
    if link then q.choices[#q.choices + 1] = describeItem(link) end
  end
  for i = 1, (try(GetNumQuestRewards) or 0) do
    local link = try(GetQuestItemLink, "reward", i)
    if link then q.rewards[#q.rewards + 1] = describeItem(link) end
  end
  q.money = try(GetRewardMoney)
  q.xp = try(GetRewardXP)
  session.lastQuestWindow = q
end

-- Trainer window (class, pet or profession trainer): every service with cost and requirement.
local function captureTrainer()
  local t = { npc = UnitName("npc"), at = date("%H:%M:%S"), services = {} }
  for i = 1, (try(GetNumTrainerServices) or 0) do
    local name, subText, category = try(GetTrainerServiceInfo, i)
    if name then
      t.services[#t.services + 1] = {
        name = name, rank = subText, status = category, -- available, unavailable, used, header
        cost = try(GetTrainerServiceCost, i),
        levelReq = try(GetTrainerServiceLevelReq, i),
      }
    end
  end
  session.lastTrainer = t
end

-- Vendor window: items for sale with price and stats.
local function captureMerchant()
  local m = { npc = UnitName("npc"), at = date("%H:%M:%S"), items = {} }
  for i = 1, (try(GetMerchantNumItems) or 0) do
    local link = try(GetMerchantItemLink, i)
    local _, _, price, quantity = try(GetMerchantItemInfo, i)
    if link then
      local d = describeItem(link)
      d.price, d.quantity = price, quantity
      m.items[#m.items + 1] = d
    end
  end
  session.lastMerchant = m
end

--------------------------------------------------------------------------------------------
-- Persistent history (survives between snapshots): XP pacing, deaths, dungeon runs.
--------------------------------------------------------------------------------------------

local MAX_ENTRIES = 60
local tracker = { lastXP = nil, lastXPMax = nil, lastLevel = nil }

local function history()
  ForeverScoutHistory = ForeverScoutHistory or {}
  local h = ForeverScoutHistory
  h.levelUps = h.levelUps or {}
  h.deaths = h.deaths or {}
  h.runs = h.runs or {}
  h.xpTotal = h.xpTotal or 0
  return h
end

local function push(list, entry)
  list[#list + 1] = entry
  while #list > MAX_ENTRIES do table.remove(list, 1) end
end

-- Values from roster APIs can be restricted ("secret") on this client; storing one makes the
-- SavedVariables write trip the blocked-action dialog. Comparing a secret value raises an error,
-- so a value that survives a comparison inside pcall is a plain one and safe to keep.
local function plain(v)
  if v == nil then return nil end
  local ok = pcall(function() return v == v end)
  return ok and v or nil
end

local function isTrue(v)
  local ok, r = pcall(function() return v == true end)
  return ok and r or false
end

-- Strip the "-Realm" suffix the guild roster adds to names. Battle.net hides real names
-- behind protected "|K...|k" tokens that only the UI can render; those are dropped.
local function shortName(name)
  name = plain(name)
  if type(name) ~= "string" or name == "" or name:find("|K", 1, true) then return nil end
  return name:match("^([^-]+)") or name
end

local function partyMembers()
  local members = {}
  for i = 1, 4 do
    local unit = "party" .. i
    if UnitExists(unit) then
      local _, class = UnitClass(unit)
      -- Online flag and map position tell whether the member can actually help right now.
      local entry = { name = UnitName(unit), level = UnitLevel(unit), class = class }
      -- Connection state can come back as a restricted value; any test on it must stay inside pcall.
      pcall(function() entry.online = (UnitIsConnected(unit) == true) and "yes" or "no" end)
      pcall(function()
        for k, v in pairs(unitMapPos(unit)) do entry[k] = plain(v) end
      end)
      members[#members + 1] = entry
    end
  end
  return members
end

-- Ask the server for fresh friend and guild rosters; the data arrives a moment later
-- and is read by the next snapshot.
local function requestRosters()
  if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
  if IsInGuild and IsInGuild() then
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster)
    elseif GuildRoster then pcall(GuildRoster) end
  end
end

-- Communities (C_Club): every subscribed club except the guild, with its online members.
-- Club types: 0 Battle.net, 1 WoW character community, 2 guild, 3 other.
local CLUB_TYPES = { [0] = "bnet", [1] = "wow", [3] = "other" }
-- Enum.ClubMemberPresence: 1 online, 2 online on mobile, 3 offline, 4 away, 5 busy.
local CLUB_ONLINE = { [1] = true, [4] = true, [5] = true }

local function className(classID)
  local info = classID and C_CreatureInfo and try(C_CreatureInfo.GetClassInfo, classID)
  return info and info.className
end

local function getCommunities()
  if not (C_Club and C_Club.GetSubscribedClubs) then return nil end
  local out = {}
  for _, club in ipairs(try(C_Club.GetSubscribedClubs) or {}) do
    local clubType = plain(club.clubType)
    if clubType ~= 2 then
      local entry = { name = plain(club.name), type = CLUB_TYPES[clubType] or tostring(clubType),
                      members = plain(club.memberCount), online = {} }
      for _, memberId in ipairs(try(C_Club.GetClubMembers, club.clubId) or {}) do
        local m = try(C_Club.GetMemberInfo, club.clubId, memberId)
        if m and not isTrue(m.isSelf) and CLUB_ONLINE[plain(m.presence)] then
          entry.online[#entry.online + 1] = { name = shortName(m.name), level = plain(m.level),
            class = className(plain(m.classID)), zone = plain(m.zone) }
        end
      end
      out[#out + 1] = entry
    end
  end
  return out
end

-- Guild name, own rank and member counts; nil when not in a guild.
local function getGuild()
  if not (IsInGuild and IsInGuild()) then return nil end
  local name, rank, rankIndex = try(GetGuildInfo, "player")
  local total, online = try(GetNumGuildMembers)
  return { name = plain(name), rank = plain(rank), rankIndex = plain(rankIndex),
           members = plain(total), online = plain(online) }
end

-- Online friends (character list, Battle.net friends playing WoW, guild, communities) with
-- level and zone, so a session can be planned around who is actually playing and where.
local function getOnlineFriends()
  local out, seen = {}, {}
  local function add(source, name, level, class, zone, realm)
    name = shortName(name)
    if not name or seen[name] then return end
    seen[name] = true
    out[#out + 1] = { source = source, name = name, level = plain(level), class = plain(class),
                      zone = plain(zone), realm = plain(realm) }
  end

  if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
    for i = 1, (try(C_FriendList.GetNumFriends) or 0) do
      local f = try(C_FriendList.GetFriendInfoByIndex, i)
      if f and isTrue(f.connected) then add("friend", f.name, f.level, f.className, f.area) end
    end
  end

  if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
    for i = 1, (try(BNGetNumFriends) or 0) do
      local a = try(C_BattleNet.GetFriendAccountInfo, i)
      local g = a and a.gameAccountInfo
      if g and isTrue(g.isOnline) and plain(g.clientProgram) == "WoW" then
        add("bnet", g.characterName, g.characterLevel, g.className, g.areaName, g.realmName)
      end
    end
  end

  if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
    for i = 1, (try(GetNumGuildMembers) or 0) do
      local name, _, _, level, class, zone, _, _, online = try(GetGuildRosterInfo, i)
      if isTrue(online) and shortName(name) ~= UnitName("player") then
        add("guild", name, level, class, zone)
      end
    end
  end

  for _, club in ipairs(getCommunities() or {}) do
    for _, m in ipairs(club.online) do add("community", m.name, m.level, m.class, m.zone) end
  end
  return out
end

-- Count every XP point gained, including across level-ups, into a running total.
local function onXPUpdate()
  local xp, xpMax, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
  if tracker.lastXP then
    local gained
    if level > tracker.lastLevel then
      gained = (tracker.lastXPMax - tracker.lastXP) + xp
    else
      gained = xp - tracker.lastXP
    end
    if gained and gained > 0 then
      local h = history()
      h.xpTotal = h.xpTotal + gained
    end
  end
  tracker.lastXP, tracker.lastXPMax, tracker.lastLevel = xp, xpMax, level
end

-- Log each death with place and level. The combat log is restricted on this client,
-- so the killer is taken from the current target when it is hostile (best effort).
local function onDeath()
  local loc = getLocation()
  local killer, killerIsPlayer
  if UnitExists("target") and UnitCanAttack("player", "target") then
    killer = UnitName("target")
    killerIsPlayer = UnitIsPlayer("target") and true or false
  end
  push(history().deaths, {
    at = date("%Y-%m-%d %H:%M"), level = UnitLevel("player"),
    zone = loc.zone, subZone = loc.subZone, x = loc.x, y = loc.y,
    killer = killer, killerIsPlayer = killerIsPlayer or false,
    grouped = IsInGroup() and true or false,
  })
end

-- Track dungeon runs: entering a 5-player instance opens a run, leaving it closes the run.
-- The open run is stored in history so a /reload inside the dungeon does not reset it.
local function onZoneChange()
  local inInstance, instanceType = IsInInstance()
  local h = history()
  if inInstance and instanceType == "party" then
    if not h.openRun then
      local name = GetInstanceInfo()
      h.openRun = { dungeon = name, start = time(), startedAt = date("%Y-%m-%d %H:%M"),
                    startXP = h.xpTotal, level = UnitLevel("player"), party = partyMembers() }
    end
  elseif h.openRun then
    local run = h.openRun
    run.minutes = math.floor((time() - run.start) / 60 + 0.5)
    run.xp = h.xpTotal - run.startXP
    run.start, run.startXP = nil, nil
    push(h.runs, run)
    h.openRun = nil
  end
end

-- Addon overlap check: loaded addons that do the same job, so a long addon list can be trimmed.
-- Groups are matched by folder name prefix (case-insensitive). Leatrix Plus and ElvUI bundle many
-- features, so they are listed in several groups: whether they really clash depends on which of
-- their options are turned on.
local ADDON_GROUPS = {
  { label = "Bags", names = { "Baganator", "Bagnon", "AdiBags", "ArkInventory", "OneBag", "Combuctor", "BetterBags", "ElvUI" } },
  { label = "Damage meters", names = { "Details", "Recount", "Skada" } },
  { label = "Action bars", names = { "Bartender4", "Dominos", "ElvUI" } },
  { label = "Unit frames", names = { "ElvUI", "ShadowedUnitFrames", "PitBull4", "XPerl", "Z-Perl", "SUF" } },
  { label = "Nameplates", names = { "Plater", "TidyPlates", "Kui_Nameplates", "ElvUI" } },
  { label = "Leveling guides", names = { "RXPGuides", "Guidelime", "AAP", "AzerothAutoPilot", "TourGuide", "Zygor" } },
  { label = "Quest auto-accept", names = { "ForeverAutoQuest", "QuickQuest", "AutoTurnIn", "Leatrix_Plus" } },
  { label = "Waypoint arrows", names = { "TomTom", "Carbonite", "Waypoints" } },
  { label = "World map coordinates", names = { "WhereYouAt", "OpenMap", "Mapster", "Leatrix_Maps", "MapCoords" } },
  { label = "Auction house", names = { "Auctionator", "Auctioneer", "TradeSkillMaster", "TSM", "aux" } },
  { label = "Vendor price in tooltips", names = { "BetterVendorPrice", "VendorPrice", "Auctionator", "TradeSkillMaster" } },
  { label = "Fast loot", names = { "SpeedyAutoLoot", "FasterLoot", "AutoLooter", "Leatrix_Plus" } },
  { label = "Swing / auto shot timers", names = { "AutoshotForever", "Quartz", "WeaponSwingTimer", "SwingTimer" } },
  { label = "Chat", names = { "Prat", "Chatter", "ElvUI" } },
  { label = "Tooltips", names = { "TipTac", "TinyTooltip", "ElvUI" } },
  { label = "Rare scanners", names = { "RareScanner", "NPCScan", "SilverDragon", "UnitScan" } },
}

local function addonList()
  local num = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
  local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
  local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  local out = {}
  for i = 1, (try(num) or 0) do
    local name, title = try(info, i)
    if name then
      out[#out + 1] = { name = name, title = title and title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or name,
                        loaded = try(loaded, i) and true or false }
    end
  end
  return out
end

-- {label, addons = {names}} for every group with two or more loaded addons.
local function addonOverlaps(list)
  local loadedNames = {}
  for _, a in ipairs(list) do if a.loaded then loadedNames[#loadedNames + 1] = a.name end end
  local result = {}
  for _, group in ipairs(ADDON_GROUPS) do
    local hits, seen = {}, {}
    for _, name in ipairs(loadedNames) do
      local lower = name:lower()
      for _, prefix in ipairs(group.names) do
        if lower:sub(1, #prefix) == prefix:lower() then
          -- Plugins (Details_Streamer, ...) count as their parent addon.
          local root = name:match("^([^_]+)_") or name
          if prefix:find("_") then root = name end
          if not seen[root] then seen[root] = true; hits[#hits + 1] = root end
          break
        end
      end
    end
    if #hits > 1 then result[#result + 1] = { label = group.label, addons = hits } end
  end
  return result
end

-- Snapshot section: loaded addon count, the full list and the overlaps.
local function getAddons()
  local list = addonList()
  local loaded = {}
  for _, a in ipairs(list) do if a.loaded then loaded[#loaded + 1] = a.name end end
  return { loaded = loaded, total = #list, overlaps = addonOverlaps(list) }
end

-- Build each section independently so one failing API cannot wipe the whole snapshot.
-- Any error message is stored under `errors` to help debugging.
local function buildSnapshot()
  local snap, errors = {}, {}
  local function section(key, fn)
    local ok, value = pcall(fn)
    if ok then
      snap[key] = value
    else
      errors[key] = tostring(value)
    end
  end

  section("savedAt", function() return date("%Y-%m-%d %H:%M:%S") end)
  section("question", function() return session.question end)
  section("name", function() return UnitName("player") end)
  section("realm", function() return GetRealmName() end)
  -- Non-localized tokens ("HUNTER", "Troll", "Horde") so offline tools can filter quests.
  section("class", function() return select(2, UnitClass("player")) end)
  section("race", function() return select(2, UnitRace("player")) end)
  section("faction", function() return UnitFactionGroup("player") end)
  section("level", function() return UnitLevel("player") end)
  section("xp", function() return UnitXP("player") end)
  section("xpMax", function() return UnitXPMax("player") end)
  section("rested", function() return GetXPExhaustion() or 0 end)
  section("money", function() return GetMoney() end)
  -- Current health is a protected "secret" value on this client: storing it makes the
  -- SavedVariables write trip the "blocked action" dialog, so only the maximum is kept.
  section("healthMax", function()
    local ok, value = pcall(function() return UnitHealthMax("player") + 0 end)
    return ok and value or nil
  end)
  section("location", getLocation)
  section("instance", function()
    local inInstance, instanceType = IsInInstance()
    return inInstance and { name = GetInstanceInfo(), type = instanceType } or nil
  end)
  section("party", function() return IsInGroup() and partyMembers() or nil end)
  section("onlineFriends", getOnlineFriends)
  section("guild", getGuild)
  section("communities", getCommunities)
  section("pvpFlagged", function() return UnitIsPVP("player") and true or false end)
  section("currentRun", function()
    local run = history().openRun
    return run and { dungeon = run.dungeon, startedAt = run.startedAt, xpSoFar = history().xpTotal - (run.startXP or 0) } or nil
  end)
  section("target", getTarget)
  section("quests", getQuestLog)
  section("completedQuests", getCompletedQuests)
  section("equipment", getEquipment)
  section("bags", getBags)
  section("skills", getSkills)
  section("talents", getTalents)
  section("unspentTalentPoints", function() return try(UnitCharacterPoints, "player") end)
  section("pet", getPet)
  section("hearth", getHearth)
  section("upkeep", getUpkeep)
  section("flights", function() return ForeverScoutHistory and ForeverScoutHistory.flights end)
  section("recipes", function() return ForeverScoutHistory and ForeverScoutHistory.recipes end)
  section("buffs", function() return getAuras("player", "HELPFUL") end)
  section("debuffs", function() return getAuras("player", "HARMFUL") end)
  section("spellbook", getSpellbook)
  section("actionBars", getActionBars)
  section("lastQuestWindow", function() return session.lastQuestWindow end)
  section("lastTrainer", function() return session.lastTrainer end)
  section("lastMerchant", function() return session.lastMerchant end)
  section("lastRolls", function() return session.lastRolls end)
  section("locale", function() return GetLocale() end)
  section("addons", getAddons)
  -- Only collect API diagnostics while some section is still empty.
  local talentsFound = snap.talents and ((snap.talents.trees and #snap.talents.trees > 0) or (snap.talents.tabs and #snap.talents.tabs > 0))
  if not talentsFound or not (snap.skills and #snap.skills > 0) then
    section("apiDiagnostics", getApiDiagnostics)
  end

  if next(errors) then snap.errors = errors end
  -- During logout the client tears unit data down (XP, money and bags read as empty);
  -- never overwrite a good snapshot with one of those.
  local valid = (snap.xpMax or 0) > 0 and type(snap.bags) == "table" and next(snap.bags) ~= nil
  if valid then
    ForeverScoutDB = snap
  end
  return valid
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("QUEST_COMPLETE")
frame:RegisterEvent("TRAINER_SHOW")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("START_LOOT_ROLL")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("TAXIMAP_OPENED")
frame:RegisterEvent("TRADE_SKILL_SHOW")
-- Events that can change an upkeep alert. Some may not exist on every client, so each
-- registration is protected.
local ALERT_EVENTS = {
  BAG_UPDATE_DELAYED = true, UNIT_PET = true, UNIT_HAPPINESS = true, PET_UI_UPDATE = true,
  UPDATE_INVENTORY_DURABILITY = true, PLAYER_REGEN_ENABLED = true, PLAYER_ALIVE = true,
  PLAYER_UNGHOST = true, PLAYER_UPDATE_RESTING = true, PLAYER_MOUNT_DISPLAY_CHANGED = true,
}
for event in pairs(ALERT_EVENTS) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "PLAYER_LOGIN" then
    onXPUpdate()
    requestRosters()
    if C_Timer then C_Timer.After(10, function() scheduleAlerts() end) end
    -- Keep the snapshot fresh while playing, so a plain /reload always saves current data.
    -- Rosters are re-requested each tick; the server throttles them and the next tick reads them.
    if C_Timer and C_Timer.NewTicker then
      C_Timer.After(5, function() pcall(buildSnapshot) end)
      C_Timer.NewTicker(20, function()
        pcall(requestRosters)
        pcall(buildSnapshot)
        scheduleAlerts()
      end)
    end
  elseif event == "PLAYER_XP_UPDATE" then
    onXPUpdate()
  elseif event == "PLAYER_LEVEL_UP" then
    push(history().levelUps, { level = arg1, at = date("%Y-%m-%d %H:%M"), zone = GetZoneText() })
  elseif event == "PLAYER_DEAD" then
    onDeath()
  elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
    onZoneChange()
  elseif event == "PLAYER_LOGOUT" then
    -- Fires on /reload and logout: refresh the snapshot so a plain /reload is enough.
    -- The periodic refresh already holds a fresh snapshot; this only adds a last update when data is still readable.
    pcall(buildSnapshot)
    session.question = nil
  elseif event == "TAXIMAP_OPENED" then
    pcall(captureTaxi)
  elseif event == "TRADE_SKILL_SHOW" then
    -- Recipe data can arrive a moment after the window opens.
    pcall(captureTradeSkill)
    if C_Timer then C_Timer.After(1, function() pcall(captureTradeSkill) end) end
  elseif event == "START_LOOT_ROLL" then
    local link = try(GetLootRollItemLink, arg1)
    if link and isHunter() then adviseItem(link) end
  elseif event == "QUEST_DETAIL" then
    captureQuestWindow("offered")
  elseif event == "QUEST_COMPLETE" then
    captureQuestWindow("turnin")
  elseif event == "TRAINER_SHOW" then
    captureTrainer()
  elseif event == "MERCHANT_SHOW" then
    captureMerchant()
  end
  if ALERT_EVENTS[event] then scheduleAlerts() end
end)

-- /wow [question] : store the optional question and build the snapshot.
-- The player then types /reload themselves: any reload started from addon code
-- (ReloadUI or a prefilled chat line) is tainted and blocked on this client.
-- /feli and /scout are aliases.

-- Compact one-line export of the current snapshot, shown in a copy box so it can be pasted
-- straight into a chat with Claude without a /reload.
local function compactText(snap)
  local out = {}
  local function add(x) out[#out + 1] = x end
  local loc = snap.location or {}
  add(string.format("FX1 %s | nv %s %s/%s XP desc %s | %sc | %s - %s %.1f,%.1f",
    tostring(snap.savedAt), tostring(snap.level), tostring(snap.xp), tostring(snap.xpMax),
    tostring(snap.rested), tostring(snap.money), tostring(loc.zone), tostring(loc.subZone),
    tonumber(loc.x) or 0, tonumber(loc.y) or 0))
  if snap.question then add("PREGUNTA: " .. snap.question) end
  local h = snap.hearth or {}
  add("hogar: " .. tostring(h.bind) .. " cd " .. tostring(h.cooldownLeft))
  local u = snap.upkeep or {}
  add("bolsa libre " .. tostring(u.freeSlots) .. " dur min " .. tostring(u.lowestDurability))
  local b = {}
  for _, a in ipairs(snap.buffs or {}) do b[#b + 1] = tostring(a.name) .. (a.left and ("(" .. a.left .. "s)") or "") end
  add("buffs: " .. table.concat(b, ", "))
  local pet = snap.pet
  if pet then add(string.format("pet: %s %s nv %s xp %s/%s feliz %s", tostring(pet.name), tostring(pet.family),
    tostring(pet.level), tostring(pet.xp), tostring(pet.xpMax), tostring(pet.happiness))) end
  local party = {}
  for _, m in ipairs(snap.party or {}) do party[#party + 1] = tostring(m.name) .. " " .. tostring(m.class) .. " " .. tostring(m.level) .. " " .. tostring(m.online) .. " " .. tostring(m.mapName) end
  if #party > 0 then add("grupo: " .. table.concat(party, ", ")) end
  local friends = {}
  for _, f in ipairs(snap.onlineFriends or {}) do friends[#friends + 1] = tostring(f.name) .. " " .. tostring(f.level) .. " " .. tostring(f.zone) end
  add("friends online: " .. (#friends > 0 and table.concat(friends, ", ") or "none"))
  for _, q in ipairs(snap.quests or {}) do
    local objs = {}
    for _, o in ipairs(q.objectives or {}) do objs[#objs + 1] = tostring(o.text) end
    add(string.format("Q%s %s%s %s", tostring(q.id), q.complete and "[OK] " or "", tostring(q.title), table.concat(objs, "; ")))
  end
  local bag = {}
  for _, it in pairs(snap.bags or {}) do bag[#bag + 1] = tostring(it.name) .. " x" .. tostring(it.count) end
  table.sort(bag)
  add("bolsas: " .. table.concat(bag, ", "))
  local eq = {}
  for _, it in pairs(snap.equipment or {}) do if it and it.name then eq[#eq + 1] = it.name end end
  add("equipo: " .. table.concat(eq, ", "))
  return table.concat(out, " || ")
end

local copyFrame
local function showCopyBox(text)
  if not copyFrame then
    copyFrame = CreateFrame("Frame", "ForeverScoutCopyFrame", UIParent, "BackdropTemplate")
    copyFrame:SetSize(520, 70)
    copyFrame:SetPoint("TOP", UIParent, "TOP", 0, -120)
    copyFrame:SetFrameStrata("DIALOG")
    if copyFrame.SetBackdrop then
      copyFrame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      copyFrame:SetBackdropColor(0, 0, 0, 0.9)
    end
    local label = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", 0, -8)
    label:SetText("ForeverScout: Ctrl+C para copiar, pegalo en Claude. Esc para cerrar.")
    local box = CreateFrame("EditBox", nil, copyFrame, "InputBoxTemplate")
    box:SetSize(480, 24)
    box:SetPoint("BOTTOM", 0, 12)
    box:SetAutoFocus(true)
    box:SetMaxLetters(0)
    box:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
    -- Close once the text has been copied.
    box:SetScript("OnKeyUp", function(_, key)
      if key == "C" and IsControlKeyDown() then C_Timer.After(0.1, function() copyFrame:Hide() end) end
    end)
    copyFrame.box = box
  end
  copyFrame:Show()
  copyFrame.box:SetText(text)
  copyFrame.box:SetFocus()
  copyFrame.box:HighlightText()
end

-- /donde <npc name | npc id | party member>: points a TomTom arrow at the nearest spawn of an
-- NPC from Questie's database, or follows a party member's live position. With no argument it
-- uses the current target's NPC id. "/donde off" clears the arrow.
-- Questie (spawn data) and TomTom (arrow and live distance) must be enabled.
local YARD_IN_METERS = 0.9144

local function say(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cFF54E33BForeverScout|r: " .. text)
end

local function questieModule(name)
  if not (QuestieLoader and QuestieLoader.ImportModule) then return nil end
  return try(QuestieLoader.ImportModule, QuestieLoader, name)
end

-- Lowercase and strip esMX accents (UTF-8 two-byte letters) so "jabali" matches "Jabalí".
local ACCENTS = {
  ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ü"] = "u", ["ñ"] = "n",
  ["Á"] = "a", ["É"] = "e", ["Í"] = "i", ["Ó"] = "o", ["Ú"] = "u", ["Ü"] = "u", ["Ñ"] = "n",
}
local function fold(text)
  return (text:gsub("\195[\128-\191]", ACCENTS)):lower()
end

-- Name index over Questie's NPC table, built on first use (names come in the client locale).
local npcIndex
local function getNpcIndex()
  if npcIndex then return npcIndex end
  local db = questieModule("QuestieDB")
  if not (db and db.NPCPointers and db.QueryNPCSingle) then return nil end
  local index = {}
  for id in pairs(db.NPCPointers) do
    local name = try(db.QueryNPCSingle, id, "name")
    if type(name) == "string" then index[#index + 1] = { id = id, name = name, key = fold(name) } end
  end
  if #index > 0 then npcIndex = index end
  return npcIndex
end

-- Exact name or id matches win; otherwise every NPC whose name contains the query.
local function findNpcs(query)
  local index = getNpcIndex()
  if not index then return nil end
  local id, key = tonumber(query), fold(query)
  local exact, partial = {}, {}
  for _, e in ipairs(index) do
    if id then
      if e.id == id then exact[#exact + 1] = e end
    elseif e.key == key then
      exact[#exact + 1] = e
    elseif e.key:find(key, 1, true) then
      partial[#partial + 1] = e
    end
  end
  return #exact > 0 and exact or partial
end

-- Nearest spawn (world yards) across the given NPCs, using Questie's own distance helper.
local function nearestSpawn(entries)
  local db, du = questieModule("QuestieDB"), questieModule("DistanceUtils")
  if not (db and du and du.GetNearestSpawn) then return nil end
  local best
  for i = 1, math.min(#entries, 200) do
    local e = entries[i]
    local spawns = try(db.QueryNPCSingle, e.id, "spawns")
    if type(spawns) == "table" and next(spawns) then
      local spawn, zone, d = try(du.GetNearestSpawn, spawns)
      if spawn and d and (not best or d < best.dist) then
        best = { entry = e, x = spawn[1], y = spawn[2], zone = zone, dist = d }
      end
    end
  end
  return best
end

local arrowUid, followTicker
local function clearArrow()
  if followTicker then followTicker:Cancel(); followTicker = nil end
  if arrowUid and TomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, arrowUid) end
  arrowUid = nil
end

local function setArrow(mapID, x, y, title, silent)
  if arrowUid and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, arrowUid) end
  arrowUid = try(TomTom.AddWaypoint, TomTom, mapID, x / 100, y / 100,
    { title = title, crazy = true, persistent = false, silent = silent, from = "ForeverScout" })
  return arrowUid ~= nil
end

local function partyUnitByName(query)
  local key = fold(query)
  for i = 1, 4 do
    local unit = "party" .. i
    local name = UnitExists(unit) and plain(UnitName(unit))
    if type(name) == "string" and fold(name):find(key, 1, true) then return unit, name end
  end
end

-- Re-point the arrow at a moving party member every 2 seconds.
local function followPartyMember(unit, name)
  local last
  local function update()
    if not UnitExists(unit) or plain(UnitName(unit)) ~= name then
      say(name .. " left the party; arrow cleared.")
      clearArrow()
      return
    end
    local pos = unitMapPos(unit)
    if not (pos.mapID and pos.x and pos.y) then
      if last then return end  -- keep the last known point
      say(name .. ": position hidden (instance or other continent).")
      clearArrow()
      return
    end
    if last and last.mapID == pos.mapID and math.abs(last.x - pos.x) < 0.3 and math.abs(last.y - pos.y) < 0.3 then return end
    setArrow(pos.mapID, pos.x, pos.y, name, last ~= nil)
    last = pos
  end
  update()
  if arrowUid and C_Timer and C_Timer.NewTicker then followTicker = C_Timer.NewTicker(2, update) end
end

local function targetNpcId()
  local guid = plain(UnitGUID("target"))
  if type(guid) ~= "string" then return nil end
  return tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)") or guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
end

local function where(msg)
  msg = msg and msg:match("^%s*(.-)%s*$") or ""
  if msg == "off" or msg == "clear" then
    clearArrow()
    say("arrow cleared.")
    return
  end
  if not (TomTom and TomTom.AddWaypoint) then
    say("TomTom is not enabled; enable it to get the arrow.")
    return
  end
  if msg == "" then
    local id = targetNpcId()
    if not id then
      say("usage: /donde <npc name or id | party member>, /donde off. With no argument it uses your NPC target.")
      return
    end
    msg = tostring(id)
  end

  local unit, member = partyUnitByName(msg)
  if unit then
    clearArrow()
    say("following " .. member .. " (party member).")
    followPartyMember(unit, member)
    return
  end

  local found = findNpcs(msg)
  if not found then
    say("Questie is not loaded yet; try again in a few seconds.")
    return
  end
  if #found == 0 then
    say("no NPC matches \"" .. msg .. "\". Other players can only be tracked while in your party.")
    return
  end
  local best = nearestSpawn(found)
  if not best then
    say(found[1].name .. ": no known spawn in the database.")
    return
  end
  local zoneDB = questieModule("ZoneDB")
  local mapID = zoneDB and try(zoneDB.GetUiMapIdByAreaId, zoneDB, best.zone)
  if not mapID then
    say(best.entry.name .. ": spawn zone " .. tostring(best.zone) .. " has no map.")
    return
  end
  local info = try(C_Map.GetMapInfo, mapID)
  -- Only replace the current arrow once the new target is known.
  clearArrow()
  setArrow(mapID, best.x, best.y, best.entry.name, true)
  local distance
  if best.dist >= 500000 then
    distance = "other continent"
  else
    distance = string.format("%d yd (%d m)", math.floor(best.dist + 0.5), math.floor(best.dist * YARD_IN_METERS + 0.5))
  end
  say(string.format("%s (%d) — %s %.1f, %.1f — %s", best.entry.name, best.entry.id,
    info and info.name or "?", best.x, best.y, distance))
  if #found > 1 then
    local others = {}
    for i = 1, math.min(#found, 6) do
      if found[i] ~= best.entry then others[#others + 1] = found[i].name .. " (" .. found[i].id .. ")" end
    end
    say(#found .. " matches, nearest chosen. Others: " .. table.concat(others, ", ") .. (#found > 6 and ", ..." or "") .. ". Use /donde <id>.")
  end
end

SLASH_FOREVERSCOUTWHERE1 = "/donde"
SLASH_FOREVERSCOUTWHERE2 = "/where"
SlashCmdList.FOREVERSCOUTWHERE = where

-- Upkeep alerts: a raid-warning style message, a sound and a chat line when ammo, the pet,
-- bag space or durability need attention. Each alert fires when its condition starts and
-- repeats every ALERT_LIMITS.repeatSeconds while it lasts. "/wow alerts off" mutes them.
local ALERT_LIMITS = {
  ammo = 400,           -- equipped ammo below this (two quiver stacks of 200)
  freeSlots = 2,        -- free bag slots at or below this
  durability = 25,      -- lowest equipped item durability (percent) below this
  repeatSeconds = 300,
}
local PROJECTILE_CLASS = 6  -- item class ID of arrows and bullets
local alertState = {}

local function alertSettings()
  local h = history()
  h.alerts = h.alerts or { enabled = true }
  return h.alerts
end

local function alert(key, active, text)
  if not active then
    alertState[key] = nil
    return
  end
  local now = GetTime()
  if alertState[key] and now - alertState[key] < ALERT_LIMITS.repeatSeconds then return end
  alertState[key] = now
  if RaidNotice_AddMessage and RaidWarningFrame then
    pcall(RaidNotice_AddMessage, RaidWarningFrame, text, { r = 1, g = 0.5, b = 0.1 })
  end
  if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
  say(text)
end

local function itemClassID(itemID)
  local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  return select(6, try(getInfo, itemID))
end

-- Ammo in bags (quiver included): the equipped type, every type, and the best other stack.
-- In this client the ammo slot (0) only references the bag stacks, so they are counted directly.
local function ammoCounts()
  local equippedID = try(GetInventoryItemID, "player", 0)
  local equipped, total, byItem = 0, 0, {}
  for bag = 0, 4 do
    local slots = (C_Container and try(C_Container.GetContainerNumSlots, bag)) or try(GetContainerNumSlots, bag) or 0
    for slot = 1, slots do
      local info = C_Container and try(C_Container.GetContainerItemInfo, bag, slot)
      local id, count = info and info.itemID, info and info.stackCount
      if id and count and itemClassID(id) == PROJECTILE_CLASS then
        total = total + count
        byItem[id] = (byItem[id] or 0) + count
        if id == equippedID then equipped = equipped + count end
      end
    end
  end
  local otherID, other = nil, 0
  for id, count in pairs(byItem) do
    if id ~= equippedID and count > other then otherID, other = id, count end
  end
  return equippedID, equipped, total, otherID, other
end

local function checkAlerts()
  if not alertSettings().enabled then return end
  local _, class = UnitClass("player")
  local inCombat = InCombatLockdown and InCombatLockdown()
  local dead = UnitIsDeadOrGhost("player")

  if class == "HUNTER" and not dead then
    local equippedID, equipped, total, otherID, other = ammoCounts()
    local name = equippedID and itemNameFromLink(try(GetInventoryItemLink, "player", 0)) or "ammo"
    if not equippedID then
      alert("ammo", true, total > 0 and "No ammo equipped: drag arrows to the ammo slot." or "No ammo: buy arrows.")
    elseif equipped < ALERT_LIMITS.ammo then
      local hint = other > equipped and string.format(" Equip %s (%d).", itemNameFromLink(select(2, try(GetItemInfo, otherID))) or "your other ammo", other)
        or (total < ALERT_LIMITS.ammo and " Buy more." or "")
      alert("ammo", true, string.format("Low ammo: %d %s left.%s", equipped, name, hint))
    else
      alert("ammo", false)
    end

    if UnitExists("pet") then
      alert("petMissing", false)
      local petDead = UnitIsDead("pet")
      alert("petDead", petDead and not inCombat, "Pet is dead: cast Revive Pet.")
      -- 1 unhappy (75% damage), 2 content (100%), 3 happy (125%).
      local happiness = not petDead and plain(try(GetPetHappiness))
      alert("petUnhappy", happiness == 1, "Pet is unhappy (75% damage, may run away): Feed Pet now.")
      alert("petContent", happiness == 2 and not inCombat, "Pet is only content: Feed Pet for +25% damage.")
    else
      alert("petDead", false)
      alert("petUnhappy", false)
      alert("petContent", false)
      local away = (IsResting and IsResting()) or (IsMounted and IsMounted()) or (UnitOnTaxi and UnitOnTaxi("player"))
      alert("petMissing", UnitLevel("player") >= 10 and not away and not inCombat, "No pet out: Call Pet.")
    end
  end

  local u = getUpkeep()
  alert("bags", u.freeSlots <= ALERT_LIMITS.freeSlots,
    string.format("Bags almost full: %d free slot%s.", u.freeSlots, u.freeSlots == 1 and "" or "s"))
  alert("durability", not dead and u.lowestDurability < ALERT_LIMITS.durability,
    string.format("Gear at %d%% durability: repair.", u.lowestDurability))
end

-- Bag and unit events come in bursts; run one check a second after the last one.
local alertPending = false
scheduleAlerts = function()
  if alertPending then return end
  alertPending = true
  local function run()
    alertPending = false
    pcall(checkAlerts)
  end
  if C_Timer and C_Timer.After then C_Timer.After(1, run) else run() end
end

local function alertsCommand(arg)
  local cfg = alertSettings()
  if arg == "off" then
    cfg.enabled = false
    say("upkeep alerts off (/wow alerts on to enable).")
  elseif arg == "on" then
    cfg.enabled = true
    for k in pairs(alertState) do alertState[k] = nil end
    say("upkeep alerts on.")
    scheduleAlerts()
  else
    for k in pairs(alertState) do alertState[k] = nil end
    say(string.format("upkeep alerts %s: ammo < %d, free bag slots <= %d, durability < %d%%, pet dead / unhappy / content / missing. Repeat every %d min. /wow alerts on|off",
      cfg.enabled and "on" or "off", ALERT_LIMITS.ammo, ALERT_LIMITS.freeSlots, ALERT_LIMITS.durability, ALERT_LIMITS.repeatSeconds / 60))
    if cfg.enabled then pcall(checkAlerts) end
  end
end

local function addonsCommand()
  local a = getAddons()
  say(string.format("%d addons loaded (of %d installed).", #a.loaded, a.total))
  if #a.overlaps == 0 then
    say("no overlapping addons found.")
    return
  end
  for _, o in ipairs(a.overlaps) do
    say("|cffffd100" .. o.label .. "|r: " .. table.concat(o.addons, ", "))
  end
  say("same job twice: keep one per line (Leatrix Plus / ElvUI only clash if that option is on).")
end

local function command(msg)
  msg = msg and msg:match("^%s*(.-)%s*$") or ""
  -- "/wow <shift-clicked item link>" gives an instant Need/Greed verdict, no reload needed.
  local link = msg:match("(|c.-|Hitem:.-|h.-|h|r)") or msg:match("(|Hitem:.-|h.-|h)")
  if link then
    if isHunter() then
      adviseItem(link)
    else
      print("|cff33ff99ForeverScout|r: loot advice uses hunter stat weights; it is off for your class.")
    end
    return
  end
  if msg:lower() == "addons" then
    addonsCommand()
    return
  end
  local alertsArg = msg:match("^alerts%s*(%a*)$")
  if alertsArg then
    alertsCommand(alertsArg:lower())
    return
  end
  session.question = msg ~= "" and msg or nil
  buildSnapshot()
  -- Show the copy box right away; /reload is still available for the full detailed file.
  showCopyBox(compactText(ForeverScoutDB or {}))
end

SLASH_FOREVERSCOUT1 = "/wow"
SLASH_FOREVERSCOUT2 = "/feli"
SLASH_FOREVERSCOUT3 = "/scout"
SlashCmdList.FOREVERSCOUT = command
