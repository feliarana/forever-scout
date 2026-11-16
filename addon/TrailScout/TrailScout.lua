-- TrailScout: writes a per-character snapshot into SavedVariables.
-- WoW only flushes SavedVariables to disk on /reload, character switch or logout,
-- so /scout builds the snapshot and the following /reload writes it to disk.
--
-- Usage: /scout [optional question]  -> saves snapshot + question and shows a copy box;
-- type /reload to write the full snapshot to disk. See README.md for every feature.
-- It also remembers the last quest reward window, trainer and vendor you opened.
-- /whereis <npc | party member> points a TomTom arrow at it (see where()).
-- Upkeep alerts warn about ammo, pet, bags and durability (see checkAlerts(), /scout alerts).
-- Gear tooltips get a weighted score line against what is equipped (see addTooltipScore()).

local frame = CreateFrame("Frame")

-- Data captured from windows during the session; kept until the next snapshot.
local session = {}

-- Upkeep alerts (ammo, pet, bags, durability) and the first-login welcome line; defined
-- further down, used by the event handler.
local scheduleAlerts, welcome, routeResume

-- Call a function safely; return nil instead of raising if the API is missing or errors.
local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  -- Lua 5.1 compatible: keep every return value (GetItemInfo returns more than ten).
  local function pack(...) return select("#", ...), { ... } end
  local n, r = pack(pcall(fn, ...))
  if r[1] then return unpack(r, 2, n) end
  return nil
end

-- Every chat message goes through here so it carries the addon name.
local function say(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cFF54E33BTrailScout|r: " .. text)
end

-- Localization: the English text is the key, so a missing translation falls back to English.
-- Spanish clients (esMX, esES) get the table below; add another locale the same way.
local L = {}
local function T(text) return L[text] or text end
local clientLocale = GetLocale and GetLocale() or "enUS"
if clientLocale == "esMX" or clientLocale == "esES" then
  -- Loot advisor and tooltip
  L["NEED"] = "NECESIDAD"
  L["GREED"] = "CODICIA"
  L["not equippable"] = "no es equipable"
  L["a weapon your class cannot use"] = "arma que tu clase no puede usar"
  L["armor too heavy for your class"] = "armadura demasiado pesada para tu clase"
  L["your class cannot use shields"] = "tu clase no puede usar escudos"
  L["armor type you can wear from level 40"] = "tipo de armadura que podés usar desde el nivel 40"
  L["unknown slot (%s)"] = "ranura no reconocida (%s)"
  L[" (requires level %d)"] = " (requiere nivel %d)"
  L["upgrade, +%.1f points%s"] = "mejora, +%.1f puntos%s"
  L["not better than yours (%.1f)%s"] = "no mejora lo tuyo (%.1f)%s"
  L["not for you (%s)"] = "no es para vos (%s)"
  L["equipped, score %.1f"] = "equipado, puntaje %.1f"
  L["%+.1f vs equipped"] = "%+.1f contra lo equipado"
  L["(score %.1f)"] = "(puntaje %.1f)"
  L["needs level %d"] = "requiere nivel %d"
  L["no stat weights for your class yet, so there is no loot advice. Set your own: /scout weights agi=1 sta=0.5 (see /scout weights)."] =
    "todavía no hay pesos de estadísticas para tu clase, así que no hay consejo de botín. Poné los tuyos: /scout weights agi=1 sta=0.5 (mirá /scout weights)."
  -- Stat weights command
  L["stat weights (%s): %s"] = "pesos de estadísticas (%s): %s"
  L["yours"] = "tuyos"
  L["class default"] = "por defecto de la clase"
  L["none set"] = "sin definir"
  L["usage: /scout weights agi=2.3 sta=0.7 ... | /scout weights reset. Stats: %s. dps is melee weapon DPS, rdps is ranged weapon DPS."] =
    "uso: /scout weights agi=2.3 sta=0.7 ... | /scout weights reset. Estadísticas: %s. dps es el DPS del arma cuerpo a cuerpo, rdps el del arma a distancia."
  L["unknown stat \"%s\". Stats: %s."] = "estadística desconocida \"%s\". Estadísticas: %s."
  L["stat weights saved for this character."] = "pesos de estadísticas guardados para este personaje."
  L["stat weights reset to the class default."] = "pesos de estadísticas restablecidos a los de la clase."
  -- Copy box
  L["Ctrl+C to copy, then paste it into your AI chat. Esc to close."] = "Ctrl+C para copiar y pegalo en tu chat de IA. Esc para cerrar."
  L["Summary of your character (%d characters), already selected: just press Ctrl+C."] =
    "Resumen de tu personaje (%d caracteres), ya seleccionado: solo apretá Ctrl+C."
  -- /whereis
  L["%s left the party; arrow cleared."] = "%s salió del grupo; flecha borrada."
  L["%s: position hidden (instance or other continent)."] = "%s: posición oculta (instancia u otro continente)."
  L["arrow cleared."] = "flecha borrada."
  L["TomTom is not enabled; enable it to get the arrow."] = "TomTom no está activado; activalo para tener la flecha."
  L["usage: /whereis <npc or object name, npc id | party member>, /whereis map, /whereis off. With no argument it uses your NPC target."] =
    "uso: /whereis <nombre de npc u objeto, id de npc | miembro del grupo>, /whereis map, /whereis off. Sin argumento usa el NPC que tenés de objetivo."
  L["following %s (party member)."] = "siguiendo a %s (miembro del grupo)."
  L["Questie is not loaded yet; try again in a few seconds."] = "Questie todavía no cargó; probá de nuevo en unos segundos."
  L["nothing matches \"%s\" (NPCs and objects). Other players can only be tracked while in your party."] =
    "nada coincide con \"%s\" (NPCs y objetos). A otros jugadores solo se los puede seguir si están en tu grupo."
  L["Show on map"] = "Ver en mapa"
  L["nothing to show yet: use /whereis <name> first."] = "todavía no hay nada para mostrar: usá /whereis <nombre> primero."
  L["%s: no known spawn in the database."] = "%s: sin aparición conocida en la base de datos."
  L["%s: spawn zone %s has no map."] = "%s: la zona de aparición %s no tiene mapa."
  L["other continent"] = "otro continente"
  L["%d matches, nearest chosen. Others: %s. Use /whereis <id>."] = "%d coincidencias, se eligió la más cercana. Otras: %s. Usá /whereis <id>."
  -- Upkeep alerts
  L["No ammo equipped: drag arrows to the ammo slot."] = "Sin munición equipada: arrastrá flechas a la ranura de munición."
  L["No ammo: buy arrows."] = "Sin munición: comprá flechas."
  L["your other ammo"] = "tu otra munición"
  L[" Equip %s (%d)."] = " Equipá %s (%d)."
  L[" Buy more."] = " Comprá más."
  L["Low ammo: %d %s left.%s"] = "Poca munición: quedan %d %s.%s"
  L["Pet is dead: cast Revive Pet."] = "La mascota está muerta: lanzá Revivir mascota."
  L["Pet is unhappy (75% damage, may run away): Feed Pet now."] = "La mascota está descontenta (75% de daño, puede escaparse): alimentala ya."
  L["Pet is only content: Feed Pet for +25% damage."] = "La mascota solo está conforme: alimentala para +25% de daño."
  L["No pet out: Call Pet."] = "Sin mascota: lanzá Llamar a mascota."
  L["%d unspent talent point(s): open the talent window."] = "%d punto(s) de talento sin gastar: abrí la ventana de talentos."
  L["Bags almost full: %d free slot(s)."] = "Bolsas casi llenas: %d lugar(es) libre(s)."
  L["Gear at %d%% durability: repair."] = "Equipo al %d%% de durabilidad: reparalo."
  L["upkeep alerts off (/scout alerts on to enable)."] = "alertas apagadas (/scout alerts on para activarlas)."
  L["upkeep alerts on."] = "alertas activadas."
  L["on"] = "activadas"
  L["off"] = "apagadas"
  L["upkeep alerts %s: ammo < %d, free bag slots <= %d, durability < %d%%, pet dead / unhappy / content / missing, unspent talent points. Repeat every %d min. /scout alerts on|off"] =
    "alertas %s: munición < %d, lugares libres <= %d, durabilidad < %d%%, mascota muerta / descontenta / conforme / ausente, puntos de talento sin gastar. Se repiten cada %d min. /scout alerts on|off"
  -- Addon overlap check
  L["%d addons loaded (of %d installed)."] = "%d addons cargados (de %d instalados)."
  L["no overlapping addons found."] = "no hay addons superpuestos."
  L["same job twice: keep one per line (Leatrix Plus / ElvUI only clash if that option is on)."] =
    "mismo trabajo dos veces: dejá uno por línea (Leatrix Plus / ElvUI solo chocan si esa opción está activa)."
  -- Help and welcome
  L["loaded"] = "cargado"
  L["not installed or disabled"] = "no instalado o desactivado"
  L["Optional addons, only needed for /whereis: Questie %s, TomTom %s."] = "Addons opcionales, solo necesarios para /whereis: Questie %s, TomTom %s."
  L["loaded. Type /scout help to see what it does."] = "cargado. Escribí /scout help para ver qué hace."
  L["TrailScout saves a snapshot of your character (quests, gear, bags, talents, friends) that an AI assistant or the offline tools can read to plan your next steps."] =
    "TrailScout guarda una foto de tu personaje (misiones, equipo, bolsas, talentos, amigos) que un asistente de IA o las herramientas offline pueden leer para planificar tus próximos pasos."
  L["/scout [question]: build the snapshot and open a box to copy a summary into an AI chat."] =
    "/scout [pregunta]: arma la foto y abre una caja para copiar un resumen a un chat de IA."
  L["/reload: writes the full snapshot to disk (the game only saves addon data on reload or logout)."] =
    "/reload: escribe la foto completa al disco (el juego solo guarda datos de addons al recargar o salir)."
  L["/whereis <npc | object | party member>: finds it, with an arrow (TomTom) and a link to see it on the map. /whereis map opens the map again, /whereis off clears the arrow. Needs Questie."] =
    "/whereis <npc | objeto | miembro del grupo>: lo encuentra, con flecha (TomTom) y un link para verlo en el mapa. /whereis map vuelve a abrir el mapa, /whereis off borra la flecha. Necesita Questie."
  L["/scout <shift-clicked item>: NEED or GREED verdict against what you wear."] =
    "/scout <item con shift-clic>: veredicto de NECESIDAD o CODICIA contra lo que tenés puesto."
  L["/scout weights: show or set the stat weights used for loot advice and tooltips."] =
    "/scout weights: muestra o cambia los pesos de estadísticas del consejo de botín y los tooltips."
  L["/scout alerts [on|off]: warnings for bags, durability, talent points, and ammo and pet for hunters."] =
    "/scout alerts [on|off]: avisos de bolsas, durabilidad, puntos de talento, y munición y mascota para cazadores."
  L["/scout route [next|<n>|clear]: walk a route made by tools/map_route.py --addon, one TomTom waypoint per stop."] =
    "/scout route [next|<n>|clear]: recorre una ruta hecha con tools/map_route.py --addon, un punto de TomTom por parada."
  L["route finished."] = "ruta terminada."
  L["route cleared."] = "ruta borrada."
  L["next stop: %s (%d of %d)"] = "próxima parada: %s (%d de %d)"
  L["you reached %s. Type /scout route next when you are done here."] = "llegaste a %s. Escribí /scout route next cuando termines acá."
  L["no route loaded. Create one with tools/map_route.py --addon, then /reload."] =
    "no hay ruta cargada. Creá una con tools/map_route.py --addon y después /reload."
  L["route \"%s\": %d stops."] = "ruta \"%s\": %d paradas."
  L["new route loaded: %s (%d stops). Type /scout route to start."] = "ruta nueva cargada: %s (%d paradas). Escribí /scout route para empezar."
  L["/scout addons: loaded addons that do the same job."] = "/scout addons: addons cargados que hacen el mismo trabajo."
  L["Privacy: the snapshot and the copy box include names of party members, friends, guild and communities. It stays on your computer until you paste or share it."] =
    "Privacidad: la foto y la caja de copiar incluyen nombres de miembros del grupo, amigos, hermandad y comunidades. Queda en tu computadora hasta que la pegues o compartas."
end

-- A string value that is safe to store: client APIs can return restricted ("secret") values,
-- and any operation on one raises an error, so a value that survives a comparison inside
-- pcall is a plain one.
local function plainText(value)
  if type(value) ~= "string" then return nil end
  local ok = pcall(function() return value == value end)
  return ok and value or nil
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
  ITEM_MOD_SPELL_POWER_SHORT = "sp",
  ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal",
  ITEM_MOD_POWER_REGEN0_SHORT = "mp5",
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

-- Loot advisor: scores an item with per-class stat weights and compares it to what is equipped,
-- so a Need/Greed decision can be made in chat without a /reload.
-- Weights per class token. `dps` is melee weapon DPS, `rdps` ranged weapon DPS. Only classes
-- with a sourced set are listed (hunter: RestedXP, levels 20-29); any player can set their own
-- with "/scout weights", saved per character in TrailScoutHistory.weights.
local CLASS_WEIGHTS = {
  HUNTER = { agi = 2.33, spi = 1.12, sta = 0.75, int = 0.55, str = 0.20, armor = 0.035,
             ap = 0.8, rap = 0.8, crit = 10, hit = 10, dps = 3, rdps = 14 },
}
-- Stat names "/scout weights" accepts, in display order.
local WEIGHT_STATS = { "agi", "str", "sta", "int", "spi", "armor", "ap", "rap", "crit", "hit",
                       "sp", "heal", "mp5", "dps", "rdps" }

local function playerClass()
  return select(2, UnitClass("player"))
end

-- Weights in use: the character's own, else the class default, else nil (no loot advice).
local function activeWeights()
  local h = TrailScoutHistory
  if h and type(h.weights) == "table" and next(h.weights) then return h.weights, "yours" end
  local weights = CLASS_WEIGHTS[playerClass()]
  if weights then return weights, "class default" end
  return nil, "none set"
end

-- Weapon subclasses a hunter can equip (axes, bows, guns, polearms, swords, staves, misc, fist, daggers, thrown, crossbows).
-- Other classes have no list yet, so their weapons are never rejected.
local CLASS_WEAPONS = {
  HUNTER = { [0] = true, [1] = true, [2] = true, [3] = true, [6] = true, [7] = true, [8] = true,
             [10] = true, [13] = true, [14] = true, [15] = true, [16] = true, [18] = true },
}
-- Heaviest armor subclass each class wears {before level 40, from level 40}, Classic rules:
-- 1 cloth, 2 leather, 3 mail, 4 plate. Subclass 6 is shields.
local ARMOR_LIMIT = {
  WARRIOR = { 3, 4 }, PALADIN = { 3, 4 }, HUNTER = { 2, 3 }, SHAMAN = { 2, 3 }, ROGUE = { 2, 2 },
  DRUID = { 2, 2 }, PRIEST = { 1, 1 }, MAGE = { 1, 1 }, WARLOCK = { 1, 1 },
}
local SHIELD_CLASSES = { WARRIOR = true, PALADIN = true, SHAMAN = true }

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
  local weights = activeWeights()
  if not weights then return 0 end
  local score = 0
  for key, value in pairs(stats) do
    local short = STAT_KEYS[key]
    if short == "dps" then
      local ranged = equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" or equipLoc == "INVTYPE_THROWN"
      score = score + value * ((ranged and weights.rdps or weights.dps) or 0)
    elseif short and weights[short] then
      score = score + value * weights[short]
    end
  end
  return score
end

-- Weighted score of an item against what is equipped in its slot.
-- Returns nil while the item is not cached yet. Otherwise a table with one of:
--   skip = reason        not gear the weights apply to (non-equippable, ammo, bags, shirts...)
--   unusable = reason    gear this class cannot wear or wield at this level
--   score, current, delta, reqLevel, equipped (true when this exact item is equipped)
local function evaluateItem(link)
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local name, _, _, _, reqLevel, _, _, _, equipLoc, _, _, classID, subClassID = try(getInfo, link)
  if not name then return nil end
  if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" then
    return { skip = T("not equippable") }
  end
  local class = playerClass()
  local weapons = CLASS_WEAPONS[class]
  if classID == 2 and weapons and not weapons[subClassID] then
    return { unusable = T("a weapon your class cannot use") }
  end
  if classID == 4 then
    local limit = ARMOR_LIMIT[class]
    if subClassID == 6 and not SHIELD_CLASSES[class] then
      return { unusable = T("your class cannot use shields") }
    end
    if limit and subClassID and subClassID >= 1 and subClassID <= 4 then
      if subClassID > limit[2] then return { unusable = T("armor too heavy for your class") } end
      if subClassID > limit[1] and UnitLevel("player") < 40 then
        return { unusable = T("armor type you can wear from level 40") }
      end
    end
  end
  local slots = SLOTS_BY_EQUIPLOC[equipLoc]
  if not slots then return { skip = string.format(T("unknown slot (%s)"), tostring(equipLoc)) } end
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
  if e.reqLevel and e.reqLevel > UnitLevel("player") then note = string.format(T(" (requires level %d)"), e.reqLevel) end
  if e.delta > 0.5 then
    return "NEED", string.format(T("upgrade, +%.1f points%s"), e.delta, note), e.delta
  end
  return "GREED", string.format(T("not better than yours (%.1f)%s"), e.delta, note), e.delta
end

-- Loot advice and the tooltip score need stat weights: a class without a default set gets
-- none until the player sets their own with "/scout weights".
local function hasWeights()
  return activeWeights() ~= nil
end

local NO_WEIGHTS_HELP = "no stat weights for your class yet, so there is no loot advice. Set your own: /scout weights agi=1 sta=0.5 (see /scout weights)."

local function adviseItem(link, attempt)
  local verdict, reason, delta = judgeItem(link)
  if not verdict then
    -- Item data may not be cached yet; retry a few times.
    if (attempt or 0) < 5 and C_Timer then C_Timer.After(0.4, function() adviseItem(link, (attempt or 0) + 1) end) end
    return
  end
  local color = verdict == "NEED" and ("|cff00ff00" .. T("NEED") .. "|r") or ("|cffffd100" .. T("GREED") .. "|r")
  say(link .. " -> " .. color .. " (" .. reason .. ")")
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
-- weighted score difference against what is equipped in that slot. Needs stat weights (see activeWeights()).
local function addTooltipScore(tooltip)
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end  -- skip comparison tooltips
  if not hasWeights() then return end
  local _, link = tooltip:GetItem()
  if not link then return end
  local e = evaluateItem(link)
  if not e or e.skip then return end
  local text
  if e.unusable then
    text = "|cff808080TrailScout: " .. string.format(T("not for you (%s)"), e.unusable) .. "|r"
  elseif e.equipped then
    text = "|cff808080TrailScout: " .. string.format(T("equipped, score %.1f"), e.score) .. "|r"
  else
    local color = e.delta > 0.5 and "|cff00ff00" or (e.delta < -0.5 and "|cffff4040" or "|cffbbbbbb")
    text = color .. "TrailScout: " .. string.format(T("%+.1f vs equipped"), e.delta) .. "|r |cff808080"
      .. string.format(T("(score %.1f)"), e.score) .. "|r"
    if e.reqLevel and e.reqLevel > UnitLevel("player") then
      text = text .. " |cffff8000" .. string.format(T("needs level %d"), e.reqLevel) .. "|r"
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
        -- Stack by the full item string, not the item ID: random-suffix gear ("of the Monkey",
        -- "of the Bear") shares one ID but has different stats.
        local key = link:match("|H(item:[^|]+)|h") or itemIdFromLink(link) or link
        local entry = items[key]
        if entry then
          entry.count = entry.count + (count or 1)
        else
          entry = describeItem(link)
          entry.count = count or 1
          items[key] = entry
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

-- Talent text as the tooltip shows it, without colour codes; nil while the client has not
-- loaded it yet. Lets an assistant recommend talents for any class without a guide.
local talentsIncomplete = false
local function spellDescription(spellID)
  if not spellID then return nil end
  local text = (C_Spell and try(C_Spell.GetSpellDescription, spellID)) or try(GetSpellDescription, spellID)
  text = plainText(text)
  if type(text) ~= "string" or text == "" then
    talentsIncomplete = true
    return nil
  end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+", " ")
  if #text > 300 then text = text:sub(1, 297) .. "..." end
  return text
end

-- One trait tree: its point currencies and every node with rank, position, description and
-- whether a point can go there (open: prerequisites met; canBuy: open and a point is free).
local function readTraitTree(configID, treeID)
  local tree = { treeID = treeID, nodes = {} }
  local currencies = try(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
  if type(currencies) == "table" then
    tree.currencies = {}
    for _, c in ipairs(currencies) do
      tree.currencies[#tree.currencies + 1] = { id = c.traitCurrencyID, spent = c.spent, available = c.quantity, max = c.maxQuantity }
    end
  end
  local nodes = try(C_Traits.GetTreeNodes, treeID) or {}
  tree.nodeCount = #nodes
  for index, nodeID in ipairs(nodes) do
    local node = try(C_Traits.GetNodeInfo, configID, nodeID)
    -- Diagnostics for a tree the client lists but does not describe: keep the plain fields
    -- of its first node so the cause can be read from the saved file.
    if index == 1 and type(node) == "table" then
      tree.firstNode = { nodeID = nodeID }
      for key, value in pairs(node) do
        local kind = type(value)
        if kind == "number" or kind == "boolean" or kind == "string" then
          pcall(function() if value == value then tree.firstNode[key] = value end end)
        end
      end
    end
    if node and node.ID and node.ID ~= 0 then
      local entryID = (node.activeEntry and node.activeEntry.entryID) or (node.entryIDs and node.entryIDs[1])
      local name, desc
      if entryID then
        local entry = try(C_Traits.GetEntryInfo, configID, entryID)
        if entry and entry.definitionID then
          local def = try(C_Traits.GetDefinitionInfo, entry.definitionID)
          if def then
            name = def.overrideName or spellName(def.spellID)
            desc = def.overrideDescription or spellDescription(def.spellID)
          end
        end
      end
      -- Read defensively: these flags may be restricted values.
      local open, canBuy
      pcall(function()
        open = (node.isAvailable == true) or nil
        canBuy = (node.canPurchaseRank == true) or nil
      end)
      tree.nodes[#tree.nodes + 1] = {
        name = name, desc = desc, rank = node.activeRank or node.currentRank, max = node.maxRanks,
        x = node.posX, y = node.posY, open = open, canBuy = canBuy,
      }
    end
  end
  if #tree.nodes > 0 then tree.firstNode = nil end
  return tree
end

local function getTraitTalents()
  if not (C_ClassTalents and C_Traits) then return nil end
  local configID = try(C_ClassTalents.GetActiveConfigID)
  if not configID then return nil end
  local config = try(C_Traits.GetConfigInfo, configID)
  if not config or not config.treeIDs then return nil end
  local result = { configID = configID, trees = {} }
  for _, treeID in ipairs(config.treeIDs) do
    result.trees[#result.trees + 1] = readTraitTree(configID, treeID)
  end
  return result
end

-- Every other trait system the client exposes besides the class talents: on Forever that is
-- where account-wide perks such as the Legacy trees live. System IDs are not documented for
-- this client, so a small range is probed and whatever answers is recorded as it is. On
-- Forever 1.60 the Legacy trees are system 45 (trees 1187-1189, one shared point currency).
local TRAIT_SYSTEM_PROBE = 100
local function getTraitSystems()
  if not (C_Traits and C_Traits.GetConfigIDBySystemID) then return nil end
  local classConfigID = C_ClassTalents and try(C_ClassTalents.GetActiveConfigID)
  local systems, seen = {}, {}
  for systemID = 1, TRAIT_SYSTEM_PROBE do
    local configID = try(C_Traits.GetConfigIDBySystemID, systemID)
    if type(configID) == "number" and configID ~= classConfigID and not seen[configID] then
      seen[configID] = true
      local config = try(C_Traits.GetConfigInfo, configID)
      if config and type(config.treeIDs) == "table" and #config.treeIDs > 0 then
        local system = { systemID = systemID, configID = configID, name = plainText(config.name),
                         configType = config.type, trees = {} }
        for _, treeID in ipairs(config.treeIDs) do
          system.trees[#system.trees + 1] = readTraitTree(configID, treeID)
        end
        systems[#systems + 1] = system
      end
    end
  end
  return systems
end

-- Names of the client APIs that could hold talent-like systems, so a missing one (legacy
-- points on a client build that keeps them elsewhere) can be found from the saved file.
local function getTraitApiNames()
  local found = {}
  for name, value in pairs(_G) do
    if type(name) == "string" and (name:find("Trait") or name:find("Legacy") or name:find("Perk")) then
      if type(value) == "table" and name:match("^C_") then
        local fns = {}
        for fnName, fn in pairs(value) do
          if type(fn) == "function" then fns[#fns + 1] = fnName end
        end
        table.sort(fns)
        found[name] = fns
      elseif type(value) == "function" then
        found.globals = found.globals or {}
        found.globals[#found.globals + 1] = name
      end
    end
  end
  if found.globals then table.sort(found.globals) end
  return found
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
  local h = TrailScoutHistory or {}
  TrailScoutHistory = h
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
-- The recipe list API keeps answering with the last profession that had recipes, so opening
-- one without any (fishing) used to save another profession's list under its name. Each
-- recipe is therefore filed under the profession the client says it belongs to.
local function sameRecipeNames(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i].name ~= b[i].name then return false end
  end
  return true
end

-- Drop a profession whose saved list is a copy of another one's (data from older versions):
-- the later capture is the wrong one.
local function dropDuplicateRecipes(recipes)
  local names = {}
  for name in pairs(recipes) do names[#names + 1] = name end
  for _, name in ipairs(names) do
    for _, other in ipairs(names) do
      local mine, theirs = recipes[name], recipes[other]
      if name ~= other and mine and theirs and #mine.list > 0 and sameRecipeNames(mine.list, theirs.list)
        and (mine.at or "") > (theirs.at or "") then
        recipes[name] = nil
      end
    end
  end
end

local function captureTradeSkill()
  local h = TrailScoutHistory or {}
  TrailScoutHistory = h
  h.recipes = h.recipes or {}
  local now = date("%Y-%m-%d %H:%M")
  local byProfession = {}

  -- Classic-era window: the list belongs to the open trade skill.
  local profession = try(GetTradeSkillLine)
  local list = {}
  for i = 1, (try(GetNumTradeSkills) or 0) do
    local name, kind = try(GetTradeSkillInfo, i)
    if name and kind ~= "header" then list[#list + 1] = { name = name, color = kind } end
  end
  if type(profession) == "string" and #list > 0 then byProfession[profession] = list end

  if not next(byProfession) and C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
    local base = C_TradeSkillUI.GetBaseProfessionInfo and try(C_TradeSkillUI.GetBaseProfessionInfo) or {}
    for _, id in ipairs(try(C_TradeSkillUI.GetAllRecipeIDs) or {}) do
      local info = try(C_TradeSkillUI.GetRecipeInfo, id)
      if info and info.learned then
        local owner = C_TradeSkillUI.GetProfessionInfoByRecipeID and try(C_TradeSkillUI.GetProfessionInfoByRecipeID, id)
        local name = owner and (plainText(owner.parentProfessionName) or plainText(owner.professionName))
        if not name or name == "" then name = plainText(base.parentProfessionName) or plainText(base.professionName) end
        if name and name ~= "" then
          byProfession[name] = byProfession[name] or {}
          table.insert(byProfession[name], { name = info.name, color = info.relativeDifficulty })
        end
      end
    end
  end

  for name, recipes in pairs(byProfession) do
    -- Without per-recipe ownership a copy of another profession's list is the stale answer.
    local copy = false
    for other, saved in pairs(h.recipes) do
      if other ~= name and sameRecipeNames(recipes, saved.list) then copy = true end
    end
    if not copy then h.recipes[name] = { at = now, list = recipes } end
  end
  dropDuplicateRecipes(h.recipes)
end

-- Pet happiness: 1 unhappy (75% damage), 2 content (100%), 3 happy (125%), plus the damage
-- percentage. Forever reports it through C_PetInfo; the global is the Classic-era fallback.
-- Returns nil when the client gives no usable number.
local function petHappiness()
  local happiness, damage
  if C_PetInfo and C_PetInfo.GetPetHappiness then happiness, damage = try(C_PetInfo.GetPetHappiness) end
  if happiness == nil then happiness, damage = try(GetPetHappiness) end
  local ok, value = pcall(function() return happiness + 0 end)
  if not ok then return nil end
  local okDamage, damageValue = pcall(function() return damage + 0 end)
  return value, okDamage and damageValue or nil
end

local function getPet()
  if not UnitExists("pet") then return nil end
  local pet = { name = UnitName("pet"), level = UnitLevel("pet"), family = try(UnitCreatureFamily, "pet") }
  pet.happiness, pet.damagePercent = petHappiness()
  -- What the pet eats, so food in the bags can be matched to it.
  local diet = { (C_PetInfo and try(C_PetInfo.GetPetFoodTypes)) or try(GetPetFoodTypes) }
  if type(diet[1]) == "table" then diet = diet[1] end
  local foods = {}
  for _, food in ipairs(diet) do
    if type(food) == "string" then foods[#foods + 1] = food end
  end
  if #foods > 0 then pet.foodTypes = foods end
  pcall(function()
    local loyalty = (C_PetInfo and C_PetInfo.GetPetLoyalty and C_PetInfo.GetPetLoyalty()) or (GetPetLoyalty and GetPetLoyalty())
    if type(loyalty) == "string" then pet.loyalty = loyalty end
  end)
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
  TrailScoutHistory = TrailScoutHistory or {}
  local h = TrailScoutHistory
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

-- XP pacing. A play session survives /reload and ends after SESSION_GAP seconds without a
-- snapshot. One XP sample is kept every SAMPLE_EVERY seconds (about the last hour), so the
-- recent rate is not diluted by an AFK break earlier in the session.
local SESSION_GAP, SAMPLE_EVERY, MAX_SAMPLES, MIN_PACE_SECONDS = 1800, 300, 13, 300

local function getPace()
  local h, now = history(), time()
  local s = h.pace
  if not s or now - (s.lastSeen or 0) > SESSION_GAP then
    s = { start = now, startedAt = date("%Y-%m-%d %H:%M"), startXP = h.xpTotal, samples = {} }
    h.pace = s
  end
  s.lastSeen = now
  s.samples = s.samples or {}
  local last = s.samples[#s.samples]
  if not last or now - last.t >= SAMPLE_EVERY then
    s.samples[#s.samples + 1] = { t = now, xp = h.xpTotal }
    while #s.samples > MAX_SAMPLES do table.remove(s.samples, 1) end
  end

  local pace = { sessionStartedAt = s.startedAt, sessionSeconds = now - s.start,
                 sessionXP = h.xpTotal - s.startXP }
  if pace.sessionSeconds >= MIN_PACE_SECONDS then
    pace.xpPerHour = math.floor(pace.sessionXP * 3600 / pace.sessionSeconds)
  end
  local first = s.samples[1]
  if first and now - first.t >= MIN_PACE_SECONDS then
    pace.recentSeconds = now - first.t
    pace.recentXPPerHour = math.floor((h.xpTotal - first.xp) * 3600 / pace.recentSeconds)
  end
  return pace
end

-- Quest log size and cap, so advice can tell whether another quest still fits.
local function getQuestLogSize()
  local out = {}
  local _, count
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then _, count = try(C_QuestLog.GetNumQuestLogEntries) end
  if not count then _, count = try(GetNumQuestLogEntries) end
  out.count = plain(count)
  out.max = plain((C_QuestLog and try(C_QuestLog.GetMaxNumQuestsCanAccept)) or MAX_QUESTS or MAX_QUESTLOG_QUESTS)
  return out
end

-- Unspent talent points. Forever keeps them in the trait tree currency; UnitCharacterPoints
-- is the classic fallback.
local function unspentTalentPoints()
  local points = plain(try(UnitCharacterPoints, "player"))
  if type(points) ~= "number" then points = 0 end
  if C_ClassTalents and C_Traits then
    local configID = try(C_ClassTalents.GetActiveConfigID)
    local config = configID and try(C_Traits.GetConfigInfo, configID)
    for _, treeID in ipairs(config and config.treeIDs or {}) do
      for _, c in ipairs(try(C_Traits.GetTreeCurrencyInfo, configID, treeID, false) or {}) do
        local quantity = plain(c.quantity)
        if type(quantity) == "number" and quantity > points then points = quantity end
      end
    end
  end
  return points
end

-- Log each death with place and level. The combat log is restricted on this client,
-- so the killer is taken from the current target when it is hostile (best effort).
-- With no hostile target the killer is unknown: killer and killerIsPlayer stay nil, so a
-- death is never recorded as "not a player" without evidence.
local lastDeathAt
local function onDeath()
  -- PLAYER_DEAD fires twice per death on this client; keep one entry.
  local now = GetTime()
  if lastDeathAt and now - lastDeathAt < 10 then return end
  lastDeathAt = now
  local loc = getLocation()
  local killer, killerIsPlayer
  if UnitExists("target") and UnitCanAttack("player", "target") then
    killer = plain(UnitName("target"))
    killerIsPlayer = UnitIsPlayer("target") and true or false
  end
  push(history().deaths, {
    at = date("%Y-%m-%d %H:%M"), level = UnitLevel("player"),
    zone = loc.zone, subZone = loc.subZone, x = loc.x, y = loc.y,
    killer = killer, killerIsPlayer = killerIsPlayer,
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

-- Heavy sections (thousands of completed quest IDs, the whole spellbook, 120 action slots plus
-- their bindings, the addon list) are cached and only rebuilt after an event that can change
-- them, so the periodic refresh stays cheap. A section missing from `heavyFresh` is rebuilt.
local heavyCache, heavyFresh = {}, {}
local talentRetries, perkRetries = 0, 0
local HEAVY_EVENTS = {
  QUEST_TURNED_IN = "completedQuests",
  TRAIT_CONFIG_UPDATED = "talents", TRAIT_TREE_CURRENCY_INFO_UPDATED = "talents",
  PLAYER_LEVEL_UP = "talents", PLAYER_TALENT_UPDATE = "talents",
  SPELLS_CHANGED = "spellbook", LEARNED_SPELL_IN_TAB = "spellbook",
  ACTIONBAR_SLOT_CHANGED = "actionBars", UPDATE_BINDINGS = "actionBars",
}

local function invalidateHeavy()
  for key in pairs(heavyFresh) do heavyFresh[key] = nil end
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
  -- Like section(), but reuses the cached value until its event invalidates it. A failed
  -- build keeps the previous value and is retried on the next snapshot.
  local function heavySection(key, fn)
    if not heavyFresh[key] then
      local ok, value = pcall(fn)
      if ok then
        heavyCache[key], heavyFresh[key] = value, true
      else
        errors[key] = tostring(value)
      end
    end
    snap[key] = heavyCache[key]
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
  section("questLog", getQuestLogSize)
  section("pace", getPace)
  heavySection("completedQuests", getCompletedQuests)
  section("equipment", getEquipment)
  section("bags", getBags)
  section("skills", getSkills)
  -- Talent text arrives late from the server: rebuild on the next snapshots until it is all
  -- there (a few tries, since some talents have no description at all).
  talentsIncomplete = false
  local talentsWereFresh = heavyFresh.talents
  heavySection("talents", getTalents)
  heavySection("traitSystems", getTraitSystems)
  if not talentsWereFresh and talentsIncomplete and talentRetries < 5 then
    talentRetries = talentRetries + 1
    heavyFresh.talents, heavyFresh.traitSystems = nil, nil
  end
  -- Keep the API names until some other trait system comes back with readable nodes.
  local perksFound = false
  for _, system in ipairs(snap.traitSystems or {}) do
    for _, tree in ipairs(system.trees or {}) do
      if #tree.nodes > 0 then perksFound = true end
    end
  end
  if not perksFound then
    heavySection("traitApi", getTraitApiNames)
    -- Perk trees (legacy) arrive some time after login: probe again on the next snapshots,
    -- for about five minutes, instead of caching the empty answer.
    if perkRetries < 15 then
      perkRetries = perkRetries + 1
      heavyFresh.traitSystems = nil
    end
  end
  section("unspentTalentPoints", function() return try(UnitCharacterPoints, "player") end)
  section("pet", getPet)
  section("hearth", getHearth)
  section("upkeep", getUpkeep)
  section("flights", function() return TrailScoutHistory and TrailScoutHistory.flights end)
  section("recipes", function() return TrailScoutHistory and TrailScoutHistory.recipes end)
  section("buffs", function() return getAuras("player", "HELPFUL") end)
  section("debuffs", function() return getAuras("player", "HARMFUL") end)
  heavySection("spellbook", getSpellbook)
  heavySection("actionBars", getActionBars)
  section("lastQuestWindow", function() return session.lastQuestWindow end)
  section("lastTrainer", function() return session.lastTrainer end)
  section("lastMerchant", function() return session.lastMerchant end)
  section("lastRolls", function() return session.lastRolls end)
  section("locale", function() return GetLocale() end)
  heavySection("addons", getAddons)  -- the loaded addon list cannot change without a /reload
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
    TrailScoutDB = snap
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
  PLAYER_LEVEL_UP = true, TRAIT_CONFIG_UPDATED = true,
}
for event in pairs(ALERT_EVENTS) do pcall(frame.RegisterEvent, frame, event) end
for event in pairs(HEAVY_EVENTS) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, arg1, arg2)
  if HEAVY_EVENTS[event] then
    -- Only mark the section stale; the next snapshot rebuilds it. Trait systems (legacy
    -- perks) change together with talents.
    heavyFresh[HEAVY_EVENTS[event]] = nil
    if HEAVY_EVENTS[event] == "talents" then heavyFresh.traitSystems, talentRetries, perkRetries = nil, 0, 0 end
  end
  if event == "PLAYER_LOGIN" then
    -- Clean recipe lists saved under the wrong profession by older versions.
    pcall(function()
      if TrailScoutHistory and TrailScoutHistory.recipes then dropDuplicateRecipes(TrailScoutHistory.recipes) end
    end)
    onXPUpdate()
    requestRosters()
    if C_Timer then
      C_Timer.After(10, function() scheduleAlerts() end)
      C_Timer.After(6, function() pcall(welcome) end)
      C_Timer.After(4, function() pcall(routeResume) end)
    end
    -- Keep the snapshot fresh while playing, so a plain /reload always saves current data.
    -- Rosters are re-requested each tick; the server throttles them and the next tick reads them.
    if C_Timer and C_Timer.NewTicker then
      C_Timer.After(5, function() pcall(buildSnapshot) end)
      C_Timer.NewTicker(20, function()
        -- Never spend frame time on a snapshot mid-fight; the first tick after combat catches
        -- up, and a /reload in combat still refreshes through PLAYER_LOGOUT.
        if not (InCombatLockdown and InCombatLockdown()) then
          pcall(requestRosters)
          pcall(buildSnapshot)
        end
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
    if link and hasWeights() then adviseItem(link) end
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

-- /scout [question] : store the optional question and build the snapshot.
-- The player then types /reload themselves: any reload started from addon code
-- (ReloadUI or a prefilled chat line) is tainted and blocked on this client.
-- /wow and /feli are older aliases.

-- Compact one-line export of the current snapshot, shown in a copy box so it can be pasted
-- straight into a chat with Claude without a /reload.
local function compactText(snap)
  local out = {}
  local function add(x) out[#out + 1] = x end
  local loc = snap.location or {}
  add(string.format("FX1 %s | level %s %s/%s XP rested %s | %s copper | %s - %s %.1f,%.1f",
    tostring(snap.savedAt), tostring(snap.level), tostring(snap.xp), tostring(snap.xpMax),
    tostring(snap.rested), tostring(snap.money), tostring(loc.zone), tostring(loc.subZone),
    tonumber(loc.x) or 0, tonumber(loc.y) or 0))
  if snap.question then add("QUESTION: " .. snap.question) end
  local h = snap.hearth or {}
  add("hearthstone: " .. tostring(h.bind) .. " cooldown " .. tostring(h.cooldownLeft) .. "s")
  local u = snap.upkeep or {}
  add("free bag slots " .. tostring(u.freeSlots) .. ", lowest durability " .. tostring(u.lowestDurability) .. "%")
  local b = {}
  for _, a in ipairs(snap.buffs or {}) do b[#b + 1] = tostring(a.name) .. (a.left and ("(" .. a.left .. "s)") or "") end
  add("buffs: " .. table.concat(b, ", "))
  local pet = snap.pet
  if pet then add(string.format("pet: %s %s level %s xp %s/%s happiness %s", tostring(pet.name), tostring(pet.family),
    tostring(pet.level), tostring(pet.xp), tostring(pet.xpMax), tostring(pet.happiness))) end
  local party = {}
  for _, m in ipairs(snap.party or {}) do party[#party + 1] = tostring(m.name) .. " " .. tostring(m.class) .. " " .. tostring(m.level) .. " " .. tostring(m.online) .. " " .. tostring(m.mapName) end
  if #party > 0 then add("party: " .. table.concat(party, ", ")) end
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
  add("bags: " .. table.concat(bag, ", "))
  local eq = {}
  for _, it in pairs(snap.equipment or {}) do if it and it.name then eq[#eq + 1] = it.name end end
  add("gear: " .. table.concat(eq, ", "))
  return table.concat(out, " || ")
end

local copyFrame
local function showCopyBox(text)
  if not copyFrame then
    copyFrame = CreateFrame("Frame", "TrailScoutCopyFrame", UIParent, "BackdropTemplate")
    copyFrame:SetSize(520, 88)
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
    label:SetText("TrailScout: " .. T("Ctrl+C to copy, then paste it into your AI chat. Esc to close."))
    -- Second line: says what the text is, since the one-line box only shows a slice of it.
    local info = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOP", 0, -24)
    copyFrame.info = info
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
  copyFrame.info:SetText(string.format(T("Summary of your character (%d characters), already selected: just press Ctrl+C."), #text))
  copyFrame.box:SetText(text)
  copyFrame.box:SetFocus()
  -- Show the start of the summary (level, zone) instead of the tail of the gear list.
  copyFrame.box:SetCursorPosition(0)
  copyFrame.box:HighlightText()
end

-- /whereis <npc name | npc id | party member>: points a TomTom arrow at the nearest spawn of an
-- NPC from Questie's database, or follows a party member's live position. With no argument it
-- uses the current target's NPC id. "/whereis off" clears the arrow.
-- Questie (spawn data) and TomTom (arrow and live distance) must be enabled.
local YARD_IN_METERS = 0.9144

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

-- Name index over Questie's NPC and object tables (objects are things in the world such as
-- chests, plants and quest items on the ground), built on first use. Names come in the
-- client locale.
local npcIndex
local function getNpcIndex()
  if npcIndex then return npcIndex end
  local db = questieModule("QuestieDB")
  if not (db and db.NPCPointers and db.QueryNPCSingle) then return nil end
  local index = {}
  for id in pairs(db.NPCPointers) do
    local name = try(db.QueryNPCSingle, id, "name")
    if type(name) == "string" then index[#index + 1] = { id = id, name = name, key = fold(name), kind = "npc" } end
  end
  if db.ObjectPointers and db.QueryObjectSingle then
    for id in pairs(db.ObjectPointers) do
      local name = try(db.QueryObjectSingle, id, "name")
      if type(name) == "string" then index[#index + 1] = { id = id, name = name, key = fold(name), kind = "object" } end
    end
  end
  if #index > 0 then npcIndex = index end
  return npcIndex
end

-- Exact name matches win; otherwise every NPC or object whose name contains the query.
-- A number is an NPC ID (objects are found by name).
local function findNpcs(query)
  local index = getNpcIndex()
  if not index then return nil end
  local id, key = tonumber(query), fold(query)
  local exact, partial = {}, {}
  for _, e in ipairs(index) do
    if id then
      if e.id == id and e.kind == "npc" then exact[#exact + 1] = e end
    elseif e.key == key then
      exact[#exact + 1] = e
    elseif e.key:find(key, 1, true) then
      partial[#partial + 1] = e
    end
  end
  return #exact > 0 and exact or partial
end

-- Nearest spawn (world yards) across the given NPCs and objects, using Questie's own
-- distance helper.
local function nearestSpawn(entries)
  local db, du = questieModule("QuestieDB"), questieModule("DistanceUtils")
  if not (db and du and du.GetNearestSpawn) then return nil end
  local best
  for i = 1, math.min(#entries, 200) do
    local e = entries[i]
    local query = e.kind == "object" and db.QueryObjectSingle or db.QueryNPCSingle
    local spawns = try(query, e.id, "spawns")
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
    { title = title, crazy = true, persistent = false, silent = silent, from = "TrailScout" })
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
      say(string.format(T("%s left the party; arrow cleared."), name))
      clearArrow()
      return
    end
    local pos = unitMapPos(unit)
    if not (pos.mapID and pos.x and pos.y) then
      if last then return end  -- keep the last known point
      say(string.format(T("%s: position hidden (instance or other continent)."), name))
      clearArrow()
      return
    end
    if last and last.mapID == pos.mapID and math.abs(last.x - pos.x) < 0.3 and math.abs(last.y - pos.y) < 0.3 then return end
    setArrow(pos.mapID, pos.x, pos.y, name, last ~= nil)
    lastWhere = { mapID = pos.mapID, x = pos.x, y = pos.y, name = name }
    last = pos
  end
  update()
  if arrowUid and C_Timer and C_Timer.NewTicker then followTicker = C_Timer.NewTicker(2, update) end
end

-- "Show on map": the last place /whereis found, opened on the world map so a far target can
-- be judged at a glance. Reached by a clickable chat link (an "addon:" hyperlink, delivered
-- by the client through the SetItemRef event) or by "/whereis map".
local lastWhere
local MAP_LINK = "addon:TrailScout:map"

local function showOnMap()
  if not lastWhere then
    say(T("nothing to show yet: use /whereis <name> first."))
    return
  end
  if OpenWorldMap then
    pcall(OpenWorldMap, lastWhere.mapID)
  elseif ToggleWorldMap and WorldMapFrame and not WorldMapFrame:IsShown() then
    pcall(ToggleWorldMap)
  end
  if WorldMapFrame and WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, lastWhere.mapID) end
end

local function mapLink()
  return "|cff71d5ff|H" .. MAP_LINK .. "|h[" .. T("Show on map") .. "]|h|r"
end

if EventRegistry and EventRegistry.RegisterCallback then
  -- The callback receives the owner first on some builds; look for the link in any argument.
  pcall(EventRegistry.RegisterCallback, EventRegistry, "SetItemRef", function(...)
    for i = 1, select("#", ...) do
      local value = select(i, ...)
      if type(value) == "string" and value:find(MAP_LINK, 1, true) then
        showOnMap()
        return
      end
    end
  end, "TrailScout")
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
    say(T("arrow cleared."))
    return
  end
  local lower = msg:lower()
  if lower == "map" or lower == "mapa" then
    showOnMap()
    return
  end
  -- Without TomTom there is no arrow, but the place is still found and can be opened on
  -- the map.
  local hasTomTom = TomTom and TomTom.AddWaypoint
  if msg == "" then
    local id = targetNpcId()
    if not id then
      say(T("usage: /whereis <npc or object name, npc id | party member>, /whereis map, /whereis off. With no argument it uses your NPC target."))
      return
    end
    msg = tostring(id)
  end

  local unit, member = partyUnitByName(msg)
  if unit then
    if not hasTomTom then
      say(T("TomTom is not enabled; enable it to get the arrow."))
      return
    end
    clearArrow()
    followPartyMember(unit, member)
    say(string.format(T("following %s (party member)."), member) .. (lastWhere and lastWhere.name == member and (" " .. mapLink()) or ""))
    return
  end

  local found = findNpcs(msg)
  if not found then
    say(T("Questie is not loaded yet; try again in a few seconds."))
    return
  end
  if #found == 0 then
    say(string.format(T("nothing matches \"%s\" (NPCs and objects). Other players can only be tracked while in your party."), msg))
    return
  end
  local best = nearestSpawn(found)
  if not best then
    say(string.format(T("%s: no known spawn in the database."), found[1].name))
    return
  end
  local zoneDB = questieModule("ZoneDB")
  local mapID = zoneDB and try(zoneDB.GetUiMapIdByAreaId, zoneDB, best.zone)
  if not mapID then
    say(string.format(T("%s: spawn zone %s has no map."), best.entry.name, tostring(best.zone)))
    return
  end
  local info = try(C_Map.GetMapInfo, mapID)
  -- Only replace the current arrow once the new target is known.
  clearArrow()
  if hasTomTom then setArrow(mapID, best.x, best.y, best.entry.name, true) end
  lastWhere = { mapID = mapID, x = best.x, y = best.y, name = best.entry.name }
  local distance
  if best.dist >= 500000 then
    distance = T("other continent")
  else
    distance = string.format("%d yd (%d m)", math.floor(best.dist + 0.5), math.floor(best.dist * YARD_IN_METERS + 0.5))
  end
  say(string.format("%s (%d) — %s %.1f, %.1f — %s %s", best.entry.name, best.entry.id,
    info and info.name or "?", best.x, best.y, distance, mapLink()))
  if not hasTomTom then say(T("TomTom is not enabled; enable it to get the arrow.")) end
  if #found > 1 then
    local others = {}
    for i = 1, math.min(#found, 6) do
      if found[i] ~= best.entry then others[#others + 1] = found[i].name .. " (" .. found[i].id .. ")" end
    end
    say(string.format(T("%d matches, nearest chosen. Others: %s. Use /whereis <id>."), #found, table.concat(others, ", ") .. (#found > 6 and ", ..." or "")))
  end
end

-- /scout route: walks a route written by "tools/map_route.py --addon" into Route.lua (the
-- global TrailScoutRoute, read again on every /reload). Every remaining stop becomes a
-- TomTom waypoint and the arrow points at the current one. Waypoint stops ("poi") advance on
-- arrival; quest stops wait for "/scout route next", since killing or looting takes a while.
-- The current stop is saved, so a /reload resumes the same route where it was.
local ROUTE_ARRIVE = 1.5  -- map percent around a stop that counts as being there
local routeUids, routeIndex, routeTicker, routeArrived = {}, nil, nil, nil

local function routeData()
  local route = TrailScoutRoute
  if type(route) == "table" and type(route.points) == "table" and #route.points > 0 then return route end
  return nil
end

local function routeRemoveWaypoint(index)
  if routeUids[index] and TomTom and TomTom.RemoveWaypoint then
    pcall(TomTom.RemoveWaypoint, TomTom, routeUids[index])
  end
  routeUids[index] = nil
end

local function routeStop()
  if routeTicker then routeTicker:Cancel(); routeTicker = nil end
  local indexes = {}
  for index in pairs(routeUids) do indexes[#indexes + 1] = index end
  for _, index in ipairs(indexes) do routeRemoveWaypoint(index) end
  routeIndex, routeArrived = nil, nil
end

local function routeAddWaypoint(index, arrow)
  local point = routeData().points[index]
  routeRemoveWaypoint(index)
  routeUids[index] = try(TomTom.AddWaypoint, TomTom, point.m, point.x / 100, point.y / 100,
    { title = point.label, crazy = arrow, persistent = false, silent = true, from = "TrailScout" })
end

-- Point the arrow at stop `index`; past the last stop the route ends, or restarts on a loop.
local function routeGoTo(index)
  local route = routeData()
  if index > #route.points then
    if not route.loop then
      routeStop()
      history().routeState = nil
      say(T("route finished."))
      return
    end
    index = 1
  end
  routeIndex, routeArrived = index, nil
  history().routeState = { id = route.createdAt, index = index }
  routeAddWaypoint(index, true)
  say(string.format(T("next stop: %s (%d of %d)"), route.points[index].label, index, #route.points))
end

local function routeTick()
  local route = routeData()
  if not (route and routeIndex) then return end
  local point, pos = route.points[routeIndex], unitMapPos("player")
  if pos.mapID ~= point.m or not (pos.x and pos.y) then return end
  if math.abs(pos.x - point.x) > ROUTE_ARRIVE or math.abs(pos.y - point.y) > ROUTE_ARRIVE then return end
  if point.kind == "poi" then
    routeRemoveWaypoint(routeIndex)
    routeGoTo(routeIndex + 1)
  elseif routeArrived ~= routeIndex then
    routeArrived = routeIndex
    say(string.format(T("you reached %s. Type /scout route next when you are done here."), point.label))
  end
end

local function routeStart(index, quiet)
  local route = routeData()
  if not route then
    say(T("no route loaded. Create one with tools/map_route.py --addon, then /reload."))
    return
  end
  if not (TomTom and TomTom.AddWaypoint) then
    say(T("TomTom is not enabled; enable it to get the arrow."))
    return
  end
  routeStop()
  index = math.max(1, math.min(index or 1, #route.points))
  for i = index + 1, #route.points do routeAddWaypoint(i, false) end
  if C_Timer and C_Timer.NewTicker then routeTicker = C_Timer.NewTicker(1, routeTick) end
  if not quiet then say(string.format(T("route \"%s\": %d stops."), tostring(route.title), #route.points)) end
  routeGoTo(index)
end

-- After login: resume the route that was being walked, or announce a new route file once.
routeResume = function()
  local route = routeData()
  if not route then return end
  local h = history()
  local state = h.routeState
  if state and state.id == route.createdAt and TomTom and TomTom.AddWaypoint then
    routeStart(state.index, true)
  elseif h.routeSeen ~= route.createdAt then
    h.routeSeen = route.createdAt
    say(string.format(T("new route loaded: %s (%d stops). Type /scout route to start."), tostring(route.title), #route.points))
  end
end

local function routeCommand(arg)
  if arg == "clear" or arg == "off" or arg == "stop" then
    routeStop()
    history().routeState = nil
    say(T("route cleared."))
  elseif arg == "next" and routeIndex then
    routeRemoveWaypoint(routeIndex)
    routeGoTo(routeIndex + 1)
  elseif tonumber(arg) then
    routeStart(tonumber(arg))
  else
    -- Plain "/scout route" starts the route, or carries on from the saved stop.
    local route, state = routeData(), history().routeState
    routeStart(route and state and state.id == route.createdAt and state.index or 1)
  end
end

SLASH_TRAILSCOUTWHERE1 = "/whereis"
SLASH_TRAILSCOUTWHERE2 = "/where"
SLASH_TRAILSCOUTWHERE3 = "/donde"  -- former name, kept so old habits still work
SlashCmdList.TRAILSCOUTWHERE = where

-- Upkeep alerts: a raid-warning style message, a sound and a chat line when ammo, the pet,
-- bag space or durability need attention. Each alert fires when its condition starts and
-- repeats every ALERT_LIMITS.repeatSeconds while it lasts. "/scout alerts off" mutes them.
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
      alert("ammo", true, total > 0 and T("No ammo equipped: drag arrows to the ammo slot.") or T("No ammo: buy arrows."))
    elseif equipped < ALERT_LIMITS.ammo then
      local hint = other > equipped and string.format(T(" Equip %s (%d)."), itemNameFromLink(select(2, try(GetItemInfo, otherID))) or T("your other ammo"), other)
        or (total < ALERT_LIMITS.ammo and T(" Buy more.") or "")
      alert("ammo", true, string.format(T("Low ammo: %d %s left.%s"), equipped, name, hint))
    else
      alert("ammo", false)
    end

    if UnitExists("pet") then
      alert("petMissing", false)
      local petDead = UnitIsDead("pet")
      alert("petDead", petDead and not inCombat, T("Pet is dead: cast Revive Pet."))
      -- 1 unhappy (75% damage), 2 content (100%), 3 happy (125%).
      local happiness = not petDead and petHappiness()
      alert("petUnhappy", happiness == 1, T("Pet is unhappy (75% damage, may run away): Feed Pet now."))
      alert("petContent", happiness == 2 and not inCombat, T("Pet is only content: Feed Pet for +25% damage."))
    else
      alert("petDead", false)
      alert("petUnhappy", false)
      alert("petContent", false)
      local away = (IsResting and IsResting()) or (IsMounted and IsMounted()) or (UnitOnTaxi and UnitOnTaxi("player"))
      alert("petMissing", UnitLevel("player") >= 10 and not away and not inCombat, T("No pet out: Call Pet."))
    end
  end

  local points = unspentTalentPoints()
  alert("talents", points > 0 and not inCombat and not dead,
    string.format(T("%d unspent talent point(s): open the talent window."), points))

  local u = getUpkeep()
  alert("bags", u.freeSlots <= ALERT_LIMITS.freeSlots,
    string.format(T("Bags almost full: %d free slot(s)."), u.freeSlots))
  alert("durability", not dead and u.lowestDurability < ALERT_LIMITS.durability,
    string.format(T("Gear at %d%% durability: repair."), u.lowestDurability))
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
    say(T("upkeep alerts off (/scout alerts on to enable)."))
  elseif arg == "on" then
    cfg.enabled = true
    for k in pairs(alertState) do alertState[k] = nil end
    say(T("upkeep alerts on."))
    scheduleAlerts()
  else
    for k in pairs(alertState) do alertState[k] = nil end
    say(string.format(T("upkeep alerts %s: ammo < %d, free bag slots <= %d, durability < %d%%, pet dead / unhappy / content / missing, unspent talent points. Repeat every %d min. /scout alerts on|off"),
      cfg.enabled and T("on") or T("off"), ALERT_LIMITS.ammo, ALERT_LIMITS.freeSlots, ALERT_LIMITS.durability, ALERT_LIMITS.repeatSeconds / 60))
    if cfg.enabled then pcall(checkAlerts) end
  end
end

local function addonsCommand()
  local a = getAddons()
  say(string.format(T("%d addons loaded (of %d installed)."), #a.loaded, a.total))
  if #a.overlaps == 0 then
    say(T("no overlapping addons found."))
    return
  end
  for _, o in ipairs(a.overlaps) do
    say("|cffffd100" .. o.label .. "|r: " .. table.concat(o.addons, ", "))
  end
  say(T("same job twice: keep one per line (Leatrix Plus / ElvUI only clash if that option is on)."))
end

-- "/scout help": what the addon is for and every command, for someone who never used it.
local HELP_LINES = {
  "TrailScout saves a snapshot of your character (quests, gear, bags, talents, friends) that an AI assistant or the offline tools can read to plan your next steps.",
  "/scout [question]: build the snapshot and open a box to copy a summary into an AI chat.",
  "/reload: writes the full snapshot to disk (the game only saves addon data on reload or logout).",
  "/whereis <npc | object | party member>: finds it, with an arrow (TomTom) and a link to see it on the map. /whereis map opens the map again, /whereis off clears the arrow. Needs Questie.",
  "/scout <shift-clicked item>: NEED or GREED verdict against what you wear.",
  "/scout weights: show or set the stat weights used for loot advice and tooltips.",
  "/scout alerts [on|off]: warnings for bags, durability, talent points, and ammo and pet for hunters.",
  "/scout route [next|<n>|clear]: walk a route made by tools/map_route.py --addon, one TomTom waypoint per stop.",
  "/scout addons: loaded addons that do the same job.",
  "Privacy: the snapshot and the copy box include names of party members, friends, guild and communities. It stays on your computer until you paste or share it.",
}

local function helpCommand()
  for _, line in ipairs(HELP_LINES) do say(T(line)) end
  -- Questie and TomTom are optional: only /whereis uses them. Say which ones are loaded.
  local function status(loaded) return loaded and T("loaded") or T("not installed or disabled") end
  say(string.format(T("Optional addons, only needed for /whereis: Questie %s, TomTom %s."),
    status(QuestieLoader ~= nil), status(TomTom ~= nil)))
  if not hasWeights() then say(T(NO_WEIGHTS_HELP)) end
end

-- "/scout weights": show, set ("agi=2.3 sta=0.7") or reset the stat weights of this character.
local WEIGHTS_USAGE = "usage: /scout weights agi=2.3 sta=0.7 ... | /scout weights reset. Stats: %s. dps is melee weapon DPS, rdps is ranged weapon DPS."

local function weightsCommand(arg)
  local h = history()
  local statList = table.concat(WEIGHT_STATS, ", ")
  if arg == "reset" then
    h.weights = nil
    say(T("stat weights reset to the class default."))
  elseif arg ~= "" then
    local valid, parsed = {}, {}
    for _, stat in ipairs(WEIGHT_STATS) do valid[stat] = true end
    for stat, value in arg:gmatch("(%a%w*)%s*=%s*(-?[%d%.]+)") do
      if not valid[stat] then
        say(string.format(T("unknown stat \"%s\". Stats: %s."), stat, statList))
        return
      end
      parsed[stat] = tonumber(value)
    end
    if not next(parsed) then
      say(string.format(T(WEIGHTS_USAGE), statList))
      return
    end
    -- New values are merged over the weights already in use, so one stat can be tuned alone.
    local merged = {}
    for stat, value in pairs(activeWeights() or {}) do merged[stat] = value end
    for stat, value in pairs(parsed) do merged[stat] = value end
    h.weights = merged
    say(T("stat weights saved for this character."))
  end
  local weights, source = activeWeights()
  local parts = {}
  for _, stat in ipairs(WEIGHT_STATS) do
    if weights and weights[stat] then parts[#parts + 1] = stat .. "=" .. weights[stat] end
  end
  say(string.format(T("stat weights (%s): %s"), T(source), #parts > 0 and table.concat(parts, " ") or "-"))
  if arg == "" then say(string.format(T(WEIGHTS_USAGE), statList)) end
end

-- One line on the first login of each character, pointing at the help.
welcome = function()
  local h = history()
  if h.welcomed then return end
  h.welcomed = true
  say(T("loaded. Type /scout help to see what it does."))
end

local function command(msg)
  msg = msg and msg:match("^%s*(.-)%s*$") or ""
  -- "/scout <shift-clicked item link>" gives an instant Need/Greed verdict, no reload needed.
  local link = msg:match("(|c.-|Hitem:.-|h.-|h|r)") or msg:match("(|Hitem:.-|h.-|h)")
  if link then
    if hasWeights() then
      adviseItem(link)
    else
      say(T(NO_WEIGHTS_HELP))
    end
    return
  end
  local lower = msg:lower()
  if lower == "help" or lower == "?" or lower == "ayuda" then
    helpCommand()
    return
  end
  if lower == "addons" then
    addonsCommand()
    return
  end
  local routeArg = lower:match("^route%s*(.*)$") or lower:match("^ruta%s*(.*)$")
  if routeArg then
    routeCommand(routeArg)
    return
  end
  local weightsArg = lower:match("^weights%s*(.*)$") or lower:match("^pesos%s*(.*)$")
  if weightsArg then
    weightsCommand(weightsArg)
    return
  end
  local alertsArg = msg:match("^alerts%s*(%a*)$")
  if alertsArg then
    alertsCommand(alertsArg:lower())
    return
  end
  session.question = msg ~= "" and msg or nil
  invalidateHeavy()  -- an explicit /scout always rebuilds everything
  buildSnapshot()
  -- Show the copy box right away; /reload is still available for the full detailed file.
  showCopyBox(compactText(TrailScoutDB or {}))
end

SLASH_TRAILSCOUT1 = "/scout"
SLASH_TRAILSCOUT2 = "/wow"
SLASH_TRAILSCOUT3 = "/feli"
SlashCmdList.TRAILSCOUT = command
