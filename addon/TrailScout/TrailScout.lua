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
local scheduleAlerts, welcome, routeResume, setupUi

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
  L["armor type you can wear from level 40"] = "tipo de armadura que puedes usar desde el nivel 40"
  L["unknown slot (%s)"] = "ranura no reconocida (%s)"
  L[" (requires level %d)"] = " (requiere nivel %d)"
  L["upgrade, +%.1f points%s"] = "mejora, +%.1f puntos%s"
  L["not better than yours (%.1f)%s"] = "no mejora lo tuyo (%.1f)%s"
  L["not for you (%s)"] = "no es para ti (%s)"
  L["equipped, score %.1f"] = "equipado, puntaje %.1f"
  L["%+.1f vs equipped"] = "%+.1f contra lo equipado"
  L["(score %.1f)"] = "(puntaje %.1f)"
  L["needs level %d"] = "requiere nivel %d"
  L["no stat weights for your class yet, so there is no loot advice. Set your own: /scout weights agi=1 sta=0.5 (see /scout weights)."] =
    "todavía no hay pesos de estadísticas para tu clase, así que no hay consejo de botín. Pon los tuyos: /scout weights agi=1 sta=0.5 (mira /scout weights)."
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
  L["Ctrl+C to copy, then paste it into your AI chat. Esc to close."] = "Ctrl+C para copiar y pégalo en tu chat de IA. Esc para cerrar."
  L["Summary of your character (%d characters), already selected: just press Ctrl+C."] =
    "Resumen de tu personaje (%d caracteres), ya seleccionado: solo presiona Ctrl+C."
  -- /whereis
  L["%s left the party; arrow cleared."] = "%s salió del grupo; flecha borrada."
  L["%s: position hidden (instance or other continent)."] = "%s: posición oculta (instancia u otro continente)."
  L["arrow cleared."] = "flecha borrada."
  L["TomTom is not enabled; enable it to get the arrow."] = "TomTom no está activado; actívalo para tener la flecha."
  L["usage: /whereis <npc or object name, npc id | party member>, /whereis map, /whereis off. With no argument it uses your NPC target."] =
    "uso: /whereis <nombre de npc u objeto, id de npc | miembro del grupo>, /whereis map, /whereis off. Sin argumento usa el NPC que tienes de objetivo."
  L["following %s (party member)."] = "siguiendo a %s (miembro del grupo)."
  L["Questie is not loaded yet; try again in a few seconds."] = "Questie todavía no cargó; prueba de nuevo en unos segundos."
  L["nothing matches \"%s\" (NPCs and objects). Other players can only be tracked while in your party."] =
    "nada coincide con \"%s\" (NPCs y objetos). A otros jugadores solo se los puede seguir si están en tu grupo."
  L["Show on map"] = "Ver en mapa"
  L["nothing to show yet: use /whereis <name> first."] = "todavía no hay nada para mostrar: usa /whereis <nombre> primero."
  L["%s: no known spawn in the database."] = "%s: sin aparición conocida en la base de datos."
  L["%s: spawn zone %s has no map."] = "%s: la zona de aparición %s no tiene mapa."
  L["other continent"] = "otro continente"
  L["%d matches, nearest chosen. Others: %s. Use /whereis <id>."] = "%d coincidencias, se eligió la más cercana. Otras: %s. Usa /whereis <id>."
  -- Upkeep alerts
  L["No ammo equipped: drag arrows to the ammo slot."] = "Sin munición equipada: arrastra flechas a la ranura de munición."
  L["No ammo: buy arrows."] = "Sin munición: compra flechas."
  L["your other ammo"] = "tu otra munición"
  L[" Equip %s (%d)."] = " Equipa %s (%d)."
  L[" Buy more."] = " Compra más."
  L["Low ammo: %d %s left.%s"] = "Poca munición: quedan %d %s.%s"
  L["Pet is dead: cast Revive Pet."] = "La mascota está muerta: lanza Revivir mascota."
  L["Pet is unhappy (75% damage, may run away): Feed Pet now."] = "La mascota está descontenta (75% de daño, puede escaparse): aliméntala ya."
  L["Pet is only content: Feed Pet for +25% damage."] = "La mascota solo está conforme: aliméntala para +25% de daño."
  L["No pet out: Call Pet."] = "Sin mascota: lanza Llamar a mascota."
  L["%d unspent talent point(s): open the talent window."] = "%d punto(s) de talento sin gastar: abre la ventana de talentos."
  L["Bags almost full: %d free slot(s)."] = "Bolsas casi llenas: %d lugar(es) libre(s)."
  L["Gear at %d%% durability: repair."] = "Equipo al %d%% de durabilidad: repáralo."
  L["upkeep alerts off (/scout alerts on to enable)."] = "alertas apagadas (/scout alerts on para activarlas)."
  L["upkeep alerts on."] = "alertas activadas."
  L["on"] = "activadas"
  L["off"] = "apagadas"
  L["upkeep alerts %s: ammo < %d, free bag slots <= %d, durability < %d%%, pet dead / unhappy / content / missing, unspent talent points. Repeat every %d min. /scout alerts on|off"] =
    "alertas %s: munición < %d, lugares libres <= %d, durabilidad < %d%%, mascota muerta / descontenta / conforme / ausente, puntos de talento sin gastar. Se repiten cada %d min. /scout alerts on|off"
  -- Addon overlap check
  L["Bags"] = "Bolsas"
  L["Damage meters"] = "Medidores de daño"
  L["Action bars"] = "Barras de acción"
  L["Unit frames"] = "Marcos de unidad"
  L["Nameplates"] = "Placas de nombre"
  L["Leveling guides"] = "Guías de subida de nivel"
  L["Quest auto-accept"] = "Aceptar misiones automáticamente"
  L["Waypoint arrows"] = "Flechas de ruta"
  L["World map coordinates"] = "Coordenadas en el mapa"
  L["Auction house"] = "Casa de subastas"
  L["Vendor price in tooltips"] = "Precio de vendedor en tooltips"
  L["Fast loot"] = "Botín rápido"
  L["Swing / auto shot timers"] = "Temporizadores de golpe / disparo automático"
  L["Rare scanners"] = "Detectores de raros"
  L["%d addons loaded (of %d installed)."] = "%d addons cargados (de %d instalados)."
  L["no overlapping addons found."] = "no hay addons superpuestos."
  L["same job twice: keep one per line (Leatrix Plus / ElvUI only clash if that option is on)."] =
    "mismo trabajo dos veces: deja uno por línea (Leatrix Plus / ElvUI solo chocan si esa opción está activa)."
  -- Settings and help window
  L["Floating button (drag it anywhere on screen)"] = "Botón flotante (arrástralo a cualquier lugar de la pantalla)"
  L["Start"] =
    "Inicio"
  L["Copy with my question"] =
    "Copiar con mi pregunta"
  L["Find an NPC, an object or a party member"] =
    "Encontrar un NPC, un objeto o un miembro del grupo"
  L["Find"] =
    "Buscar"
  L["Clear arrow"] =
    "Quitar flecha"
  L["Type part of the name; the answer appears in chat. Questie (%s) is needed to find things, TomTom (%s) adds the arrow."] =
    "Escribe parte del nombre; la respuesta aparece en el chat. Hace falta Questie (%s) para encontrar cosas, y TomTom (%s) agrega la flecha."
  L["Left-click: ask an AI, find things, settings and help"] =
    "Clic izquierdo: preguntarle a una IA, buscar cosas, ajustes y ayuda"
  L["What should I do next?"] =
    "¿Qué hago ahora?"
  L["What should I do next? Give me the next steps in order."] =
    "¿Qué me conviene hacer ahora? Dame los próximos pasos en orden. Respóndeme en español."
  L["Which quests do I do or skip?"] =
    "¿Qué misiones hago o salteo?"
  L["Which of my quests should I do now, and which should I skip or abandon? Say why."] =
    "¿Cuáles de mis misiones me conviene hacer ahora, y cuáles saltear o abandonar? Explícame por qué. Respóndeme en español."
  L["Where do my talent points go?"] =
    "¿Dónde pongo mis talentos?"
  L["Where should I put my next talent points for my class and the way I am playing?"] =
    "¿Dónde me conviene poner mis próximos puntos de talento, para mi clase y mi forma de jugar? Respóndeme en español."
  L["What do I sell or keep?"] =
    "¿Qué vendo y qué guardo?"
  L["Looking at my bags, what should I sell and what should I keep?"] =
    "Mirando mis bolsas, ¿qué me conviene vender y qué guardar? Respóndeme en español."
  L["Is anything in my bags better?"] =
    "¿Tengo algo mejor en las bolsas?"
  L["Is any gear in my bags better than what I am wearing?"] =
    "¿Hay en mis bolsas algún equipo mejor que el que llevo puesto? Respóndeme en español."
  L["Stat weights for my class"] =
    "Pesos para mi clase"
  L["What stat weights should I use for my class and role while leveling? Answer with a single line I can type in game, in this exact form: /scout weights int=1 spi=0.8 sta=0.5"] =
    "¿Qué pesos de estadísticas me conviene usar para mi clase y mi rol mientras subo de nivel? Respóndeme en español, con una sola línea que pueda escribir en el juego, exactamente con esta forma: /scout weights int=1 spi=0.8 sta=0.5"
  L["1. Press one of the questions below, or write your own.\n2. A box opens with the text already selected: press Ctrl+C.\n3. Open your AI chat (ChatGPT, Claude, Gemini or any other) and paste with Ctrl+V.\n4. Read the answer. Ask again whenever your character changes."] =
    "1. Presiona una de las preguntas de abajo, o escribe la tuya.\n2. Se abre una caja con el texto ya seleccionado: presiona Ctrl+C.\n3. Abre tu chat de IA (ChatGPT, Claude, Gemini o cualquier otro) y pega con Ctrl+V.\n4. Lee la respuesta. Vuelve a preguntar cada vez que tu personaje cambie."
  L["the settings window could not be built on this client; here is the help instead."] =
    "no se pudo armar la ventana de ajustes en este cliente; va la ayuda en su lugar."
  L["/scout config: a window with every switch and the full help (also on the minimap button)."] =
    "/scout config: una ventana con todos los interruptores y la ayuda completa (también en el botón del minimapa)."
  L["Settings"] =
    "Ajustes"
  L["Help"] =
    "Ayuda"
  L["Apply"] =
    "Aplicar"
  L["Reset"] =
    "Restablecer"
  L["Reminders (master switch)"] =
    "Avisos (interruptor general)"
  L["Bags almost full"] =
    "Bolsas casi llenas"
  L["Gear about to break"] =
    "Equipo a punto de romperse"
  L["Unspent talent points"] =
    "Puntos de talento sin gastar"
  L["Low ammo (hunters)"] =
    "Poca munición (cazadores)"
  L["Pet dead, missing or unhappy (hunters)"] =
    "Mascota muerta, ausente o descontenta (cazadores)"
  L["NEED / GREED advice in chat when a loot roll starts"] =
    "Consejo de NECESIDAD / CODICIA en el chat cuando empieza una tirada de botín"
  L["Score line on gear tooltips"] =
    "Línea de puntaje en los tooltips de equipo"
  L["Minimap button"] =
    "Botón del minimapa"
  L["Stat weights (%s). Stats: %s"] =
    "Pesos de estadísticas (%s). Estadísticas: %s"
  L["Copy summary"] =
    "Copiar resumen"
  L["Start route"] =
    "Iniciar ruta"
  L["Clear route"] =
    "Borrar ruta"
  L["Check my addons"] =
    "Revisar mis addons"
  L["Right-click: copy the summary for an AI"] =
    "Clic derecho: copiar el resumen para una IA"
  L["Drag: move this button"] =
    "Arrastrar: mover este botón"
  L["What TrailScout is for"] =
    "Para qué sirve TrailScout"
  L["It takes a snapshot of your character (quests with progress, gear, bags, talents, professions, party and friends online) so an AI assistant can plan your next steps with you. It never plays for you: it only reads what any addon can read and shows you information."] =
    "Saca una foto de tu personaje (misiones con su progreso, equipo, bolsas, talentos, profesiones, grupo y amigos conectados) para que un asistente de IA planifique contigo los próximos pasos. Nunca juega por ti: solo lee lo que cualquier addon puede leer y te muestra información."
  L["Ask an AI about your character"] =
    "Preguntarle a una IA por tu personaje"
  L["/scout opens a box with a summary of your character. Press Ctrl+C and paste it into any AI chat with your question. /scout <question> puts the question inside the summary. /reload writes the full snapshot to disk for the offline tools; the game only saves addon data on reload or logout."] =
    "/scout abre una caja con un resumen de tu personaje. Presiona Ctrl+C y pégalo en cualquier chat de IA con tu pregunta. /scout <pregunta> mete la pregunta dentro del resumen. /reload escribe la foto completa al disco para las herramientas offline; el juego solo guarda datos de addons al recargar o salir."
  L["Find NPCs, objects and party members"] =
    "Encontrar NPCs, objetos y miembros del grupo"
  L["/whereis <name> finds the nearest NPC or world object with that name: how far it is, an arrow to it and a [Show on map] link. /whereis <party member> follows them. /whereis alone uses your target, /whereis map opens the map again and /whereis off removes the arrow. Needs Questie; TomTom adds the arrow."] =
    "/whereis <nombre> encuentra el NPC u objeto del mundo más cercano con ese nombre: a qué distancia está, una flecha y un link [Ver en mapa]. /whereis <miembro del grupo> lo sigue. /whereis solo usa tu objetivo, /whereis map vuelve a abrir el mapa y /whereis off saca la flecha. Necesita Questie; TomTom agrega la flecha."
  L["Routes"] =
    "Rutas"
  L["/scout route walks a route stop by stop with waypoints. At a quest stop it tells you that you arrived and waits: type /scout route next when you are done. /scout route <number> jumps to a stop and /scout route clear removes it. A reload resumes where you were. To get a route, press \"Plan a route for me\" on the Start page, ask your AI chat and paste the TSR1 line it answers with; the offline tools can make one too. Needs TomTom, and Questie to place quest stops."] =
    "/scout route recorre una ruta parada por parada con puntos en el mapa. En una parada de misión te avisa que llegaste y espera: escribe /scout route next cuando termines. /scout route <número> salta a una parada y /scout route clear la borra. Al recargar retoma donde estabas. Para conseguir una ruta, presiona \"Ármame una ruta\" en la página Inicio, pregúntale a tu chat de IA y pega la línea TSR1 que te conteste; las herramientas offline también pueden armar una. Necesita TomTom, y Questie para ubicar las paradas de misión."
  L["Loot advice"] =
    "Consejo de botín"
  L["When a loot roll starts, chat says NEED or GREED for you, and every gear tooltip gets a line with how much better or worse the item is than what you wear. /scout <shift-clicked item> checks any item. It works from stat weights: hunters have them built in, every other class sets its own below or with /scout weights."] =
    "Cuando empieza una tirada de botín, el chat te dice NECESIDAD o CODICIA, y cada tooltip de equipo suma una línea con cuánto mejor o peor es el item que lo que tienes puesto. /scout <item con shift-clic> revisa cualquier item. Funciona con pesos de estadísticas: los cazadores los traen de fábrica y las demás clases cargan los suyos aquí abajo o con /scout weights."
  L["Reminders"] =
    "Avisos"
  L["A warning on screen and a sound when your bags are almost full, your gear is about to break or you have a talent point to spend. Hunters also get low ammo and a dead, missing or unhappy pet. Each reminder repeats every five minutes while it lasts and can be switched off on the Settings page."] =
    "Un aviso en pantalla y un sonido cuando tus bolsas están casi llenas, tu equipo está por romperse o tienes un punto de talento para gastar. Los cazadores también reciben poca munición y mascota muerta, ausente o descontenta. Cada aviso se repite cada cinco minutos mientras dure y se puede apagar en la página de Ajustes."
  L["What is saved, and privacy"] =
    "Qué se guarda, y privacidad"
  L["The snapshot also keeps your XP pace, deaths, dungeon runs, known flight paths, recipes and where you accepted each quest. It includes the names of your party members, friends, guild and communities. Everything stays on your computer until you paste or share it: the addon cannot use the internet."] =
    "La foto también guarda tu ritmo de XP, muertes, mazmorras, rutas de vuelo conocidas, recetas y dónde aceptaste cada misión. Incluye los nombres de los miembros de tu grupo, amigos, hermandad y comunidades. Todo queda en tu computadora hasta que lo pegues o compartas: el addon no puede usar internet."
  L["Other addons"] =
    "Otros addons"
  L["Questie and TomTom are optional and only used by /whereis and /scout route. /scout addons lists addons you have that do the same job twice. The offline tools can also read Syndicator (bank and mail) and Auctionator (prices)."] =
    "Questie y TomTom son opcionales y solo los usan /whereis y /scout route. /scout addons lista los addons que tienes que hacen el mismo trabajo dos veces. Las herramientas offline también pueden leer Syndicator (banco y correo) y Auctionator (precios)."
  -- Help and welcome
  L["loaded"] = "cargado"
  L["not installed or disabled"] = "no instalado o desactivado"
  L["Optional addons, only needed for /whereis: Questie %s, TomTom %s."] = "Addons opcionales, solo necesarios para /whereis: Questie %s, TomTom %s."
  L["loaded. Type /scout help to see what it does."] = "cargado. Escribe /scout help para ver qué hace."
  L["TrailScout saves a snapshot of your character (quests, gear, bags, talents, friends) that an AI assistant or the offline tools can read to plan your next steps."] =
    "TrailScout guarda una foto de tu personaje (misiones, equipo, bolsas, talentos, amigos) que un asistente de IA o las herramientas offline pueden leer para planificar tus próximos pasos."
  L["/scout [question]: build the snapshot and open a box to copy a summary into an AI chat."] =
    "/scout [pregunta]: arma la foto y abre una caja para copiar un resumen a un chat de IA."
  L["/reload: writes the full snapshot to disk (the game only saves addon data on reload or logout)."] =
    "/reload: escribe la foto completa al disco (el juego solo guarda datos de addons al recargar o salir)."
  L["/whereis <npc | object | party member>: finds it, with an arrow (TomTom) and a link to see it on the map. /whereis map opens the map again, /whereis off clears the arrow. Needs Questie."] =
    "/whereis <npc | objeto | miembro del grupo>: lo encuentra, con flecha (TomTom) y un link para verlo en el mapa. /whereis map vuelve a abrir el mapa, /whereis off borra la flecha. Necesita Questie."
  L["/scout <shift-clicked item>: NEED or GREED verdict against what you wear."] =
    "/scout <item con shift-clic>: veredicto de NECESIDAD o CODICIA contra lo que tienes puesto."
  L["/scout weights: show or set the stat weights used for loot advice and tooltips."] =
    "/scout weights: muestra o cambia los pesos de estadísticas del consejo de botín y los tooltips."
  L["/scout alerts [on|off]: warnings for bags, durability, talent points, and ammo and pet for hunters."] =
    "/scout alerts [on|off]: avisos de bolsas, durabilidad, puntos de talento, y munición y mascota para cazadores."
  L["/scout route [next|<n>|clear]: walk the loaded route, one TomTom waypoint per stop. /scout import <TSR1 line>: load the route an AI chat gave you."] =
    "/scout route [next|<n>|clear]: recorre la ruta cargada, un punto de TomTom por parada. /scout import <línea TSR1>: carga la ruta que te dio un chat de IA."
  L["route finished."] = "ruta terminada."
  L["route cleared."] = "ruta borrada."
  L["next stop: %s (%d of %d)"] = "próxima parada: %s (%d de %d)"
  L["you reached %s. Type /scout route next when you are done here."] = "llegaste a %s. Escribe /scout route next cuando termines aquí."
  L["no route loaded. Press \"Plan a route for me\" in the TrailScout window, ask your AI chat and paste the line it gives you there. The offline tools can write one too (tools/map_route.py --addon)."] =
    "no hay ruta cargada. Presiona \"Ármame una ruta\" en la ventana de TrailScout, pregúntale a tu chat de IA y pega ahí la línea que te dé. Las herramientas offline también pueden escribir una (tools/map_route.py --addon)."
  L["Plan a route for me"] = "Ármame una ruta"
  L["Plan a route for my quests: the order to do them and where to turn each one in. Explain it briefly, then end with ONE line I can paste into the game, in this exact form: TSR1; route name; q123; t123; find Npc Name; at 1424 63.8 35.6 Place name. q123 = go do quest 123 and t123 = turn it in (123 is the number after Q in my summary; [OK] quests only need the turn-in), find = an NPC or object by its exact name, at = a place by the map number in my summary and its coordinates. Prefer q and t: the game finds those places itself."] =
    "Arma una ruta para mis misiones: el orden para hacerlas y dónde entregar cada una. Explícala brevemente en español y termina con UNA línea que pueda pegar en el juego, exactamente con esta forma: TSR1; nombre de la ruta; q123; t123; find Nombre del PNJ; at 1424 63.8 35.6 Nombre del lugar. q123 = ir a hacer la misión 123 y t123 = entregarla (123 es el número después de la Q en mi resumen; las misiones [OK] solo necesitan la entrega), find = un PNJ u objeto por su nombre exacto, at = un lugar por el número de mapa de mi resumen y sus coordenadas. Prefiere q y t: el juego encuentra esos lugares solo."
  L["Paste a route from your AI chat"] = "Pega una ruta de tu chat de IA"
  L["Start this route"] = "Empezar esta ruta"
  L["Paste the line that starts with TSR1 (Ctrl+V) and press the button. Quest stops need Questie; the arrow needs TomTom."] =
    "Pega la línea que empieza con TSR1 (Ctrl+V) y presiona el botón. Las paradas de misión necesitan Questie; la flecha necesita TomTom."
  L["that is not a route line: it has to start with TSR1. Get one with the \"Plan a route for me\" question."] =
    "eso no es una línea de ruta: tiene que empezar con TSR1. Consigue una con la pregunta \"Ármame una ruta\"."
  L["Route from the AI"] = "Ruta de la IA"
  L["route imported: %s (%d stops)."] = "ruta importada: %s (%d paradas)."
  L["no stop of that route could be placed on the map."] = "no se pudo ubicar en el mapa ninguna parada de esa ruta."
  L["%d stops left out: %s"] = "%d paradas quedaron afuera: %s"
  L["Questie is needed"] = "hace falta Questie"
  L["name not found"] = "nombre no encontrado"
  L["no known place"] = "sin lugar conocido"
  L["no place known for this quest"] = "sin lugar conocido para esta misión"
  L["not understood"] = "no se entendió"
  L["Turn in"] = "Entregar"
  L["Quest"] = "Misión"
  L["go there"] = "ir al lugar"
  L["(where you accepted it; the turn-in may be elsewhere)"] = "(donde la aceptaste; la entrega puede ser en otro lado)"
  L["route \"%s\": %d stops."] = "ruta \"%s\": %d paradas."
  L["new route loaded: %s (%d stops). Type /scout route to start."] = "ruta nueva cargada: %s (%d paradas). Escribe /scout route para empezar."
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

-- Per-character switches, changed from the settings window ("/scout config"). Stored in
-- TrailScoutHistory.settings; a feature is on unless its key was explicitly set to false.
--   tooltip, lootAdvice, minimap, floating, alert_ammo, alert_pet, alert_bags, alert_durability,
--   alert_talents
local function setting(key)
  local h = TrailScoutHistory
  local s = h and h.settings
  return not (type(s) == "table" and s[key] == false)
end

local function setSetting(key, value)
  TrailScoutHistory = TrailScoutHistory or {}
  local h = TrailScoutHistory
  h.settings = h.settings or {}
  h.settings[key] = value and true or false
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
  if not hasWeights() or not setting("tooltip") then return end
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

-- What the client itself knows about a logged quest, for quests the quest database has no
-- data for (most of Forever's new ones): the XP it will pay at the current level, where the
-- game's own waypoint points next (the turn-in once the quest is complete) and who gave it.
local function questExtras(quest)
  local id = quest.id
  if not id then return quest end
  pcall(function()
    local xp = GetQuestLogRewardXP and GetQuestLogRewardXP(id)
    if type(xp) == "number" and xp > 0 then quest.xp = xp end
  end)
  pcall(function()
    if not (C_QuestLog and C_QuestLog.GetNextWaypoint) then return end
    local mapID, x, y = C_QuestLog.GetNextWaypoint(id)
    if type(mapID) == "number" and type(x) == "number" and type(y) == "number" then
      quest.waypoint = { mapID = mapID, x = math.floor(x * 10000 + 0.5) / 100, y = math.floor(y * 10000 + 0.5) / 100 }
    end
  end)
  local givers = TrailScoutHistory and TrailScoutHistory.questGivers
  if givers and givers[id] then quest.giver = givers[id] end
  return quest
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
          quests[#quests + 1] = questExtras({
            id = id, title = info.title, level = info.level, group = info.suggestedGroup,
            zoneHeader = header, complete = ready and 1 or nil,
            failed = try(C_QuestLog.IsFailed, id) or nil,
            objectives = questObjectives(id),
          })
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
        quests[#quests + 1] = questExtras(q)
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
-- Who gave each quest and where the character stood when taking it. The quest database
-- has no start point for many of Forever's new quests; this records the player's own.
-- The giver is the unit of the open quest window; quests started by an item have none.
local function onQuestAccepted(first, second)
  -- The event carries (questID) on this client and (logIndex, questID) on Classic-era ones.
  local questID = (type(second) == "number" and second > 0) and second or first
  if type(questID) ~= "number" or questID <= 0 then return end
  local h = history()
  h.questGivers = h.questGivers or {}
  local entry = { at = date("%Y-%m-%d %H:%M") }
  for _, unit in ipairs({ "questnpc", "npc" }) do
    if UnitExists(unit) and not UnitIsPlayer(unit) then
      entry.name = plain(UnitName(unit))
      local guid = plain(UnitGUID and UnitGUID(unit))
      if type(guid) == "string" then
        local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
        entry.kind, entry.id = kind, tonumber(id)
      end
      break
    end
  end
  local pos = unitMapPos("player")
  entry.mapID, entry.x, entry.y = pos.mapID, pos.x, pos.y
  h.questGivers[questID] = entry
end

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

-- Size of every zone map in yards, so the offline tools can turn map percent into walking
-- time. The client converts map positions to world positions for any map, so all zones are
-- measured once per session without visiting them. Map IDs are probed in a range because
-- Forever adds zones whose IDs are not listed anywhere.
local MAP_ID_PROBE = 2600
local function getMapSizes()
  if not (C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapInfo and CreateVector2D) then return nil end
  local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
  local topLeft, bottomRight = CreateVector2D(0, 0), CreateVector2D(1, 1)
  local sizes = {}
  for mapID = 1, MAP_ID_PROBE do
    local info = try(C_Map.GetMapInfo, mapID)
    if info and info.mapType == zoneType then
      pcall(function()
        local _, a = C_Map.GetWorldPosFromMapPos(mapID, topLeft)
        local _, b = C_Map.GetWorldPosFromMapPos(mapID, bottomRight)
        local top, left = a:GetXY()
        local bottom, right = b:GetXY()
        local width, height = math.abs(left - right), math.abs(top - bottom)
        if width > 0 and height > 0 then
          sizes[mapID] = { w = math.floor(width + 0.5), h = math.floor(height + 0.5) }
        end
      end)
    end
  end
  return sizes
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
  heavySection("mapSizes", getMapSizes)  -- zone sizes never change within a session
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
pcall(frame.RegisterEvent, frame, "QUEST_ACCEPTED")
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
      C_Timer.After(2, function() pcall(setupUi) end)
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
    if link and hasWeights() and setting("lootAdvice") then adviseItem(link) end
  elseif event == "QUEST_ACCEPTED" then
    pcall(onQuestAccepted, arg1, arg2)
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
  add(string.format("FX1 %s | level %s %s/%s XP rested %s | %s copper | %s - %s %.1f,%.1f map %s",
    tostring(snap.savedAt), tostring(snap.level), tostring(snap.xp), tostring(snap.xpMax),
    tostring(snap.rested), tostring(snap.money), tostring(loc.zone), tostring(loc.subZone),
    tonumber(loc.x) or 0, tonumber(loc.y) or 0, tostring(loc.mapID)))
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

-- /scout route: walks a route. It comes from "tools/map_route.py --addon" (Route.lua, the
-- global TrailScoutRoute, read again on every /reload) or from a line pasted from an AI
-- chat (see importRoute below); the newer of the two is used. Every remaining stop becomes a
-- TomTom waypoint and the arrow points at the current one. Waypoint stops ("poi") advance on
-- arrival; quest stops wait for "/scout route next", since killing or looting takes a while.
-- The current stop is saved, so a /reload resumes the same route where it was.
local ROUTE_ARRIVE = 1.5  -- map percent around a stop that counts as being there
local NO_ROUTE_HELP = "no route loaded. Press \"Plan a route for me\" in the TrailScout window, ask your AI chat and paste the line it gives you there. The offline tools can write one too (tools/map_route.py --addon)."
local routeUids, routeIndex, routeTicker, routeArrived = {}, nil, nil, nil

local function routeData()
  local best
  local function consider(route)
    if type(route) == "table" and type(route.points) == "table" and #route.points > 0
        and (not best or tostring(route.createdAt) > tostring(best.createdAt)) then
      best = route
    end
  end
  consider(TrailScoutRoute)
  consider(history().importedRoute)
  return best
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
    say(T(NO_ROUTE_HELP))
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

-- Importing a route from an AI chat. The "Plan a route for me" question asks the assistant
-- to end its answer with one line the player pastes back:
--   TSR1; route name; q514; t514; find Apothecary Lydon; at 1424 63.8 35.6 Tarren Mill
--   q<ID>                 where the unfinished objectives of quest ID are
--   t<ID>                 where quest ID is turned in
--   find <name>           an NPC or object by name, as /whereis finds it
--   at <map> <x> <y> [label]   a place by uiMapID and map coordinates
-- Quest and name stops are placed here from Questie's database, so the assistant does not
-- have to know any coordinates. Stops that cannot be placed are reported and left out.
local ROUTE_TAG = "TSR1"

-- The line cut into its parts; nil when the text has no route tag. Tolerates code fences,
-- line breaks and text before the tag.
local function routeParts(text)
  text = (text:gsub("[`\r]", "")):gsub("\n", ";")
  local from = text:upper():find(ROUTE_TAG, 1, true)
  if not from then return nil end
  local parts = {}
  for part in (text:sub(from + #ROUTE_TAG) .. ";"):gmatch("(.-);") do
    part = part:match("^[%s:]*(.-)[%s%.]*$")
    if part ~= "" then parts[#parts + 1] = part end
  end
  return parts
end

local function routeStopSpec(part)
  local lower = part:lower()
  local id = lower:match("^q%s*[:#]?%s*(%d+)$")
  if id then return { type = "q", id = tonumber(id) } end
  id = lower:match("^t%s*[:#]?%s*(%d+)$")
  if id then return { type = "t", id = tonumber(id) } end
  if lower:match("^find[%s:]+%S") then
    return { type = "find", name = part:sub(5):match("^[%s:]*(.-)%s*$") }
  end
  local map, x, y, label = part:match("^[Aa][Tt]%s+(%d+)[%s,]+([%d%.]+)[%s,]+([%d%.]+)%s*(.*)$")
  if map and tonumber(x) and tonumber(y) then
    return { type = "at", map = tonumber(map), x = tonumber(x), y = tonumber(y), label = label }
  end
  return nil
end

-- Questie NPC or object as an entry nearestSpawn() takes.
local function questieEntry(db, kind, id)
  local query = kind == "object" and db.QueryObjectSingle or db.QueryNPCSingle
  local name = query and try(query, id, "name")
  return { id = id, kind = kind, name = type(name) == "string" and name or (kind .. " " .. tostring(id)) }
end

-- Nearest spawn of the entries as a route point (name = what is there), or nil.
local function spawnPoint(entries)
  if not entries or #entries == 0 then return nil end
  local best = nearestSpawn(entries)
  local zoneDB = questieModule("ZoneDB")
  local mapID = best and zoneDB and try(zoneDB.GetUiMapIdByAreaId, zoneDB, best.zone)
  if not mapID then return nil end
  return { m = mapID, x = best.x, y = best.y, name = best.entry.name }
end

-- The quest's title as the log shows it, else Questie's, else its number.
local function questTitle(db, questID)
  for _, q in ipairs((TrailScoutDB or {}).quests or {}) do
    if q.id == questID and q.title then return q.title end
  end
  local name = db and db.QueryQuestSingle and try(db.QueryQuestSingle, questID, "name")
  return type(name) == "string" and name or (T("Quest") .. " " .. questID)
end

-- NPCs and objects behind the objectives of a quest that are still open, one list per
-- objective: a creature to kill, an object to use, or whatever drops or sells an item to
-- collect. An objective the log shows as finished is matched by name and left out.
local function questTargets(db, questID)
  local groups, done = {}, {}
  for _, o in ipairs(questObjectives(questID)) do
    if o.done and type(o.text) == "string" then done[#done + 1] = fold(o.text) end
  end
  local function finished(name)
    if type(name) ~= "string" or name == "" then return false end
    local key = fold(name)
    for _, text in ipairs(done) do
      if text:find(key, 1, true) then return true end
    end
    return false
  end
  local function ids(list)  -- Questie lists hold ids or { id, text } pairs
    local out, keys = {}, {}
    if type(list) ~= "table" then return out end
    for key in pairs(list) do
      if type(key) == "number" then keys[#keys + 1] = key end
    end
    table.sort(keys)  -- keep the database's order, even through holes
    for _, key in ipairs(keys) do
      local value = list[key]
      local id = type(value) == "table" and value[1] or value
      if type(id) == "number" then out[#out + 1] = id end
    end
    return out
  end
  local objectives = db.QueryQuestSingle and try(db.QueryQuestSingle, questID, "objectives")
  if type(objectives) ~= "table" then return groups end
  -- Creatures and objects are their own objective.
  for index, kind in ipairs({ "npc", "object" }) do
    for _, id in ipairs(ids(objectives[index])) do
      local entry = questieEntry(db, kind, id)
      if not finished(entry.name) then groups[#groups + 1] = { entry } end
    end
  end
  -- An item is one objective with every source it has; the stop is named after the item.
  for _, itemID in ipairs(ids(objectives[3])) do
    local name = db.QueryItemSingle and try(db.QueryItemSingle, itemID, "name")
    if not finished(name) then
      local group = { item = type(name) == "string" and name or nil }
      for field, kind in pairs({ npcDrops = "npc", objectDrops = "object", vendors = "npc" }) do
        for _, id in ipairs(ids(db.QueryItemSingle and try(db.QueryItemSingle, itemID, field))) do
          group[#group + 1] = questieEntry(db, kind, id)
        end
      end
      if #group > 0 then groups[#groups + 1] = group end
    end
  end
  return groups
end

-- A quest's open objectives as route points. Objectives close to each other (the same camp
-- or field) share a stop, so a quest gets one stop per place it sends the player to.
local QUEST_CLUSTER = 6  -- map percent
local function questPoints(db, questID)
  local points = {}
  for _, group in ipairs(questTargets(db, questID)) do
    local point = spawnPoint(group)
    if point then
      local what = group.item or point.name
      local near
      for _, other in ipairs(points) do
        if other.m == point.m and math.abs(other.x - point.x) <= QUEST_CLUSTER
            and math.abs(other.y - point.y) <= QUEST_CLUSTER then
          near = other
          break
        end
      end
      if near then
        near.names[#near.names + 1] = what
      else
        point.names = { what }
        points[#points + 1] = point
      end
    end
  end
  return points
end

-- Turns one stop of the line into its route points (a quest can have several places), or
-- nil and the reason.
local function resolveStop(spec, db)
  if spec.type == "at" then
    local label = spec.label ~= "" and spec.label or string.format("%.1f, %.1f", spec.x, spec.y)
    return { { m = spec.map, x = spec.x, y = spec.y, label = label, kind = "poi" } }
  end
  if not db then return nil, T("Questie is needed") end
  local point
  if spec.type == "find" then
    local found = findNpcs(spec.name)
    if not found or #found == 0 then return nil, T("name not found") end
    point = spawnPoint(found)
    if not point then return nil, T("no known place") end
    point.label, point.kind = point.name, "poi"
  elseif spec.type == "q" then
    local points = questPoints(db, spec.id)
    if #points > 0 then
      local title = questTitle(db, spec.id)
      for _, p in ipairs(points) do
        local names = p.names
        -- Name the first two things to do there, count the rest.
        p.label = title .. ": " .. names[1] .. (names[2] and (" + " .. names[2]) or "")
          .. (#names > 2 and string.format(" (+%d)", #names - 2) or "")
        p.kind, p.name, p.names = "quest", nil, nil
      end
      return points
    end
    if not point then
      -- "Go to this place" quests have no NPC or object, only a spot: { text, { [zone] = { { x, y } } } }.
      local trigger = db.QueryQuestSingle and try(db.QueryQuestSingle, spec.id, "triggerEnd")
      local zoneDB = questieModule("ZoneDB")
      for zone, spots in pairs(type(trigger) == "table" and type(trigger[2]) == "table" and trigger[2] or {}) do
        local mapID = zoneDB and try(zoneDB.GetUiMapIdByAreaId, zoneDB, zone)
        local spot = type(spots) == "table" and spots[1]
        if mapID and type(spot) == "table" and tonumber(spot[1]) and tonumber(spot[2]) then
          point = { m = mapID, x = spot[1], y = spot[2], name = type(trigger[1]) == "string" and trigger[1] or T("go there") }
          break
        end
      end
    end
    if not point then return nil, T("no place known for this quest") end
    point.label, point.kind = questTitle(db, spec.id) .. ": " .. point.name, "quest"
  else
    local enders = db.QueryQuestSingle and try(db.QueryQuestSingle, spec.id, "finishedBy")
    local entries = {}
    if type(enders) == "table" then
      for _, id in pairs(type(enders[1]) == "table" and enders[1] or {}) do entries[#entries + 1] = questieEntry(db, "npc", id) end
      for _, id in pairs(type(enders[2]) == "table" and enders[2] or {}) do entries[#entries + 1] = questieEntry(db, "object", id) end
    end
    local title = T("Turn in") .. " " .. questTitle(db, spec.id)
    point = spawnPoint(entries)
    if point then
      point.label = title .. ": " .. point.name
    else
      -- Quests the database does not know: fall back to where the player accepted it.
      local giver = (history().questGivers or {})[spec.id]
      if not (giver and giver.mapID and giver.x and giver.y) then return nil, T("no place known for this quest") end
      point = { m = giver.mapID, x = giver.x, y = giver.y,
                label = title .. " " .. T("(where you accepted it; the turn-in may be elsewhere)") }
    end
    point.kind = "turnin"
  end
  point.name = nil
  return { point }
end

-- Reads a pasted route line, saves the route and starts it. Returns true when it loaded.
local function importRoute(text)
  local parts = routeParts(text or "")
  if not parts then
    say(T("that is not a route line: it has to start with TSR1. Get one with the \"Plan a route for me\" question."))
    return false
  end
  local db = questieModule("QuestieDB")
  local points, problems, title = {}, {}, nil
  for i, part in ipairs(parts) do
    local spec = routeStopSpec(part)
    if spec then
      local found, reason = resolveStop(spec, db)
      if found then
        for _, point in ipairs(found) do points[#points + 1] = point end
      else
        problems[#problems + 1] = part .. " (" .. reason .. ")"
      end
    elseif i == 1 then
      title = part
    else
      problems[#problems + 1] = part .. " (" .. T("not understood") .. ")"
    end
  end
  if #points == 0 then
    say(T("no stop of that route could be placed on the map."))
  else
    -- Stops in a row at the same place (several turn-ins at one town) become one stop.
    local merged = {}
    for _, point in ipairs(points) do
      local last = merged[#merged]
      if last and last.m == point.m and math.abs(last.x - point.x) <= ROUTE_ARRIVE
          and math.abs(last.y - point.y) <= ROUTE_ARRIVE then
        last.more = (last.more or 0) + 1
        if last.kind == "poi" then last.kind = point.kind end  -- wait there if any of them is work
      else
        merged[#merged + 1] = point
      end
    end
    points = merged
    for i, point in ipairs(points) do
      point.label = i .. ". " .. point.label .. (point.more and string.format(" (+%d)", point.more) or "")
      point.more = nil
    end
    local route = { title = title or T("Route from the AI"), createdAt = date("%Y-%m-%d %H:%M:%S"),
                    loop = false, imported = true, points = points }
    local h = history()
    h.importedRoute, h.routeSeen = route, route.createdAt
    say(string.format(T("route imported: %s (%d stops)."), route.title, #points))
  end
  if #problems > 0 then
    say(string.format(T("%d stops left out: %s"), #problems, table.concat(problems, "; ")))
  end
  if #points == 0 then return false end
  routeStart(1, true)
  return true
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

-- Which settings switch each alert belongs to.
local ALERT_SETTING = {
  ammo = "alert_ammo", petDead = "alert_pet", petUnhappy = "alert_pet", petContent = "alert_pet",
  petMissing = "alert_pet", bags = "alert_bags", durability = "alert_durability", talents = "alert_talents",
}

local function alert(key, active, text)
  if ALERT_SETTING[key] and not setting(ALERT_SETTING[key]) then active = false end
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
    say("|cffffd100" .. T(o.label) .. "|r: " .. table.concat(o.addons, ", "))
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
  "/scout route [next|<n>|clear]: walk the loaded route, one TomTom waypoint per stop. /scout import <TSR1 line>: load the route an AI chat gave you.",
  "/scout addons: loaded addons that do the same job.",
  "/scout config: a window with every switch and the full help (also on the minimap button).",
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

-- Settings and help window ("/scout config", or the minimap button). Everything the addon
-- does is explained on the Help page, and every switch is on the Settings page.
local command  -- defined below; the window's buttons call it
local optionsFrame, minimapButton
local updateMinimapButton, updateFloatButton

-- Settings page switches, top to bottom. "alerts" is the master switch kept by
-- "/scout alerts on|off"; the others are setting() keys.
local OPTION_CHECKS = {
  { key = "alerts", label = "Reminders (master switch)" },
  { key = "alert_bags", label = "Bags almost full", indent = true },
  { key = "alert_durability", label = "Gear about to break", indent = true },
  { key = "alert_talents", label = "Unspent talent points", indent = true },
  { key = "alert_ammo", label = "Low ammo (hunters)", indent = true },
  { key = "alert_pet", label = "Pet dead, missing or unhappy (hunters)", indent = true },
  { key = "lootAdvice", label = "NEED / GREED advice in chat when a loot roll starts" },
  { key = "tooltip", label = "Score line on gear tooltips" },
  { key = "minimap", label = "Minimap button" },
  { key = "floating", label = "Floating button (drag it anywhere on screen)" },
}

-- Help page: one entry per feature, title then explanation.
local HELP_TOPICS = {
  { "What TrailScout is for",
    "It takes a snapshot of your character (quests with progress, gear, bags, talents, professions, party and friends online) so an AI assistant can plan your next steps with you. It never plays for you: it only reads what any addon can read and shows you information." },
  { "Ask an AI about your character",
    "/scout opens a box with a summary of your character. Press Ctrl+C and paste it into any AI chat with your question. /scout <question> puts the question inside the summary. /reload writes the full snapshot to disk for the offline tools; the game only saves addon data on reload or logout." },
  { "Find NPCs, objects and party members",
    "/whereis <name> finds the nearest NPC or world object with that name: how far it is, an arrow to it and a [Show on map] link. /whereis <party member> follows them. /whereis alone uses your target, /whereis map opens the map again and /whereis off removes the arrow. Needs Questie; TomTom adds the arrow." },
  { "Routes",
    "/scout route walks a route stop by stop with waypoints. At a quest stop it tells you that you arrived and waits: type /scout route next when you are done. /scout route <number> jumps to a stop and /scout route clear removes it. A reload resumes where you were. To get a route, press \"Plan a route for me\" on the Start page, ask your AI chat and paste the TSR1 line it answers with; the offline tools can make one too. Needs TomTom, and Questie to place quest stops." },
  { "Loot advice",
    "When a loot roll starts, chat says NEED or GREED for you, and every gear tooltip gets a line with how much better or worse the item is than what you wear. /scout <shift-clicked item> checks any item. It works from stat weights: hunters have them built in, every other class sets its own below or with /scout weights." },
  { "Reminders",
    "A warning on screen and a sound when your bags are almost full, your gear is about to break or you have a talent point to spend. Hunters also get low ammo and a dead, missing or unhappy pet. Each reminder repeats every five minutes while it lasts and can be switched off on the Settings page." },
  { "What is saved, and privacy",
    "The snapshot also keeps your XP pace, deaths, dungeon runs, known flight paths, recipes and where you accepted each quest. It includes the names of your party members, friends, guild and communities. Everything stays on your computer until you paste or share it: the addon cannot use the internet." },
  { "Other addons",
    "Questie and TomTom are optional and only used by /whereis and /scout route. /scout addons lists addons you have that do the same job twice. The offline tools can also read Syndicator (bank and mail) and Auctionator (prices)." },
}

-- Create a frame from a template when the client has it, plain otherwise.
local function make(frameType, name, parent, template)
  if template then
    local ok, created = pcall(CreateFrame, frameType, name, parent, template)
    if ok and created then return created end
  end
  return CreateFrame(frameType, name, parent)
end

local function optionValue(key)
  if key == "alerts" then return alertSettings().enabled and true or false end
  return setting(key)
end

local function setOption(key, value)
  if key == "alerts" then
    alertSettings().enabled = value and true or false
  else
    setSetting(key, value)
  end
  -- A reminder switched back on should be able to fire right away.
  for k in pairs(alertState) do alertState[k] = nil end
  if key == "minimap" and updateMinimapButton then updateMinimapButton() end
  if key == "floating" and updateFloatButton then updateFloatButton() end
  if value then scheduleAlerts() end
end

local function weightsText()
  local weights = activeWeights()
  local parts = {}
  for _, stat in ipairs(WEIGHT_STATS) do
    if weights and weights[stat] then parts[#parts + 1] = stat .. "=" .. weights[stat] end
  end
  return table.concat(parts, " ")
end

local function helpText()
  local parts = {}
  for _, topic in ipairs(HELP_TOPICS) do
    parts[#parts + 1] = "|cffffd100" .. T(topic[1]) .. "|r\n" .. T(topic[2])
  end
  return table.concat(parts, "\n\n")
end

local function showOptionsPage(name)
  for pageName, page in pairs(optionsFrame.pages) do page:SetShown(pageName == name) end
  optionsFrame.page = name
end

-- Start page: the questions most players ask an AI, ready to copy. `label` is the button,
-- `question` what goes into the summary. Both are translated, so the AI is asked in the
-- player's language and answers in it.
local AI_QUESTIONS = {
  { label = "What should I do next?",
    question = "What should I do next? Give me the next steps in order." },
  { label = "Which quests do I do or skip?",
    question = "Which of my quests should I do now, and which should I skip or abandon? Say why." },
  { label = "Where do my talent points go?",
    question = "Where should I put my next talent points for my class and the way I am playing?" },
  { label = "What do I sell or keep?",
    question = "Looking at my bags, what should I sell and what should I keep?" },
  { label = "Is anything in my bags better?",
    question = "Is any gear in my bags better than what I am wearing?" },
  { label = "Plan a route for me",
    question = "Plan a route for my quests: the order to do them and where to turn each one in. Explain it briefly, then end with ONE line I can paste into the game, in this exact form: TSR1; route name; q123; t123; find Npc Name; at 1424 63.8 35.6 Place name. q123 = go do quest 123 and t123 = turn it in (123 is the number after Q in my summary; [OK] quests only need the turn-in), find = an NPC or object by its exact name, at = a place by the map number in my summary and its coordinates. Prefer q and t: the game finds those places itself." },
  { label = "Stat weights for my class",
    question = "What stat weights should I use for my class and role while leveling? Answer with a single line I can type in game, in this exact form: /scout weights int=1 spi=0.8 sta=0.5" },
}
local AI_STEPS = "1. Press one of the questions below, or write your own.\n2. A box opens with the text already selected: press Ctrl+C.\n3. Open your AI chat (ChatGPT, Claude, Gemini or any other) and paste with Ctrl+V.\n4. Read the answer. Ask again whenever your character changes."

local function refreshOptions()
  -- Say which of the two helper addons the search can count on right now.
  local function status(loaded) return loaded and T("loaded") or T("not installed or disabled") end
  optionsFrame.findHelp:SetText(string.format(
    T("Type part of the name; the answer appears in chat. Questie (%s) is needed to find things, TomTom (%s) adds the arrow."),
    status(QuestieLoader ~= nil), status(TomTom ~= nil)))
  for key, check in pairs(optionsFrame.checks) do check:SetChecked(optionValue(key)) end
  optionsFrame.weights:SetText(weightsText())
  optionsFrame.weights:SetCursorPosition(0)  -- show the start of the line, not its end
  local _, source = activeWeights()
  optionsFrame.weightsSource:SetText(string.format(T("Stat weights (%s). Stats: %s"), T(source), table.concat(WEIGHT_STATS, " ")))
end

local function buildOptions()
  local frame = make("Frame", "TrailScoutOptionsFrame", UIParent, "BackdropTemplate")
  frame:SetSize(600, 560)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0.05, 0.08, 0.10, 0.96)
  end
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TrailScoutOptionsFrame") end  -- Esc closes it

  local version = (C_AddOns and try(C_AddOns.GetAddOnMetadata, "TrailScout", "Version")) or try(GetAddOnMetadata, "TrailScout", "Version")
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 18, -16)
  title:SetText("TrailScout" .. (version and (" " .. version) or ""))

  local close = make("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)
  close:SetScript("OnClick", function() frame:Hide() end)

  local function button(parent, text, width, onClick)
    local b = make("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
  end

  frame.pages = { start = CreateFrame("Frame", nil, frame), settings = CreateFrame("Frame", nil, frame),
                  help = CreateFrame("Frame", nil, frame) }
  for _, page in pairs(frame.pages) do
    page:SetPoint("TOPLEFT", 16, -76)
    page:SetPoint("BOTTOMRIGHT", -16, 16)
  end
  local startTab = button(frame, T("Start"), 110, function() showOptionsPage("start") end)
  startTab:SetPoint("TOPLEFT", 16, -44)
  local settingsTab = button(frame, T("Settings"), 110, function() showOptionsPage("settings") end)
  settingsTab:SetPoint("LEFT", startTab, "RIGHT", 6, 0)
  local helpTab = button(frame, T("Help"), 110, function() showOptionsPage("help") end)
  helpTab:SetPoint("LEFT", settingsTab, "RIGHT", 6, 0)
  frame.tabs = { start = startTab, settings = settingsTab, help = helpTab }

  -- Start page: ask an AI without typing a command, and find things by name.
  local start = frame.pages.start
  local function heading(text, y)
    local h = start:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", 0, y)
    h:SetText(text)
    return h
  end
  -- Copy the summary with a question in it. The window steps aside for the copy box.
  local function ask(question)
    frame:Hide()
    session.question = question ~= "" and question or nil
    buildSnapshot()
    showCopyBox(compactText(TrailScoutDB or {}))
  end
  heading(T("Ask an AI about your character"), 0)
  frame.steps = start:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.steps:SetPoint("TOPLEFT", 0, -22)
  frame.steps:SetWidth(560)
  frame.steps:SetJustifyH("LEFT")
  frame.steps:SetText(T(AI_STEPS))
  frame.questions = {}
  for i, entry in ipairs(AI_QUESTIONS) do
    local question = entry.question
    local b = button(start, T(entry.label), 276, function() ask(T(question)) end)
    b:SetPoint("TOPLEFT", ((i - 1) % 2) * 284, -104 - math.floor((i - 1) / 2) * 30)
    frame.questions[i] = b
  end
  frame.ownQuestion = make("EditBox", nil, start, "InputBoxTemplate")
  frame.ownQuestion:SetSize(380, 24)
  frame.ownQuestion:SetPoint("TOPLEFT", 6, -232)
  frame.ownQuestion:SetAutoFocus(false)
  frame.ownQuestion:SetMaxLetters(0)
  frame.ownQuestion:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  local function askOwn() ask(frame.ownQuestion:GetText() or "") end
  frame.ownQuestion:SetScript("OnEnterPressed", askOwn)
  frame.askOwn = button(start, T("Copy with my question"), 172, askOwn)
  frame.askOwn:SetPoint("LEFT", frame.ownQuestion, "RIGHT", 8, 0)

  heading(T("Find an NPC, an object or a party member"), -274)
  frame.findBox = make("EditBox", nil, start, "InputBoxTemplate")
  frame.findBox:SetSize(250, 24)
  frame.findBox:SetPoint("TOPLEFT", 6, -296)
  frame.findBox:SetAutoFocus(false)
  frame.findBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  local function find()
    local name = (frame.findBox:GetText() or ""):match("^%s*(.-)%s*$")
    if name ~= "" then where(name) end
    frame.findBox:ClearFocus()
  end
  frame.findBox:SetScript("OnEnterPressed", find)
  frame.find = button(start, T("Find"), 90, find)
  frame.find:SetPoint("LEFT", frame.findBox, "RIGHT", 8, 0)
  frame.findMap = button(start, T("Show on map"), 100, function() where("map") end)
  frame.findMap:SetPoint("LEFT", frame.find, "RIGHT", 6, 0)
  frame.findClear = button(start, T("Clear arrow"), 100, function() where("off") end)
  frame.findClear:SetPoint("LEFT", frame.findMap, "RIGHT", 6, 0)
  frame.findHelp = start:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.findHelp:SetPoint("TOPLEFT", 0, -326)
  frame.findHelp:SetWidth(560)
  frame.findHelp:SetJustifyH("LEFT")

  -- The way back from the AI chat: paste the route line it answered with.
  heading(T("Paste a route from your AI chat"), -368)
  frame.routeBox = make("EditBox", nil, start, "InputBoxTemplate")
  frame.routeBox:SetSize(274, 24)
  frame.routeBox:SetPoint("TOPLEFT", 6, -390)
  frame.routeBox:SetAutoFocus(false)
  frame.routeBox:SetMaxLetters(0)
  frame.routeBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  local function startRoute()
    local line = frame.routeBox:GetText() or ""
    frame.routeBox:ClearFocus()
    if line:match("%S") and importRoute(line) then
      frame.routeBox:SetText("")
      frame:Hide()
    end
  end
  frame.routeBox:SetScript("OnEnterPressed", startRoute)
  frame.routeStart = button(start, T("Start this route"), 172, startRoute)
  frame.routeStart:SetPoint("LEFT", frame.routeBox, "RIGHT", 8, 0)
  frame.routeClear = button(start, T("Clear route"), 100, function() routeCommand("clear") end)
  frame.routeClear:SetPoint("LEFT", frame.routeStart, "RIGHT", 6, 0)
  frame.routeHelp = start:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.routeHelp:SetPoint("TOPLEFT", 0, -420)
  frame.routeHelp:SetWidth(560)
  frame.routeHelp:SetJustifyH("LEFT")
  frame.routeHelp:SetText(T("Paste the line that starts with TSR1 (Ctrl+V) and press the button. Quest stops need Questie; the arrow needs TomTom."))

  -- Settings page: one switch per feature.
  local page = frame.pages.settings
  frame.checks = {}
  local y = 0
  for _, option in ipairs(OPTION_CHECKS) do
    local check = make("CheckButton", nil, page, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", option.indent and 24 or 0, y)
    local label = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    label:SetText(T(option.label))
    check.label = label
    local key = option.key
    check:SetScript("OnClick", function(self) setOption(key, self:GetChecked() and true or false) end)
    frame.checks[key] = check
    y = y - 26
  end

  -- Stat weights: the line "/scout weights" takes, editable in place.
  frame.weightsSource = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.weightsSource:SetPoint("TOPLEFT", 0, y - 12)
  frame.weightsSource:SetWidth(560)
  frame.weightsSource:SetJustifyH("LEFT")
  frame.weights = make("EditBox", nil, page, "InputBoxTemplate")
  frame.weights:SetSize(552, 24)
  frame.weights:SetPoint("TOPLEFT", 6, y - 46)
  frame.weights:SetAutoFocus(false)
  frame.weights:SetMaxLetters(0)
  frame.weights:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  local function applyWeights()
    weightsCommand((frame.weights:GetText() or ""):lower())
    frame.weights:ClearFocus()
    refreshOptions()
  end
  frame.weights:SetScript("OnEnterPressed", applyWeights)
  frame.applyWeights = button(page, T("Apply"), 80, applyWeights)
  frame.applyWeights:SetPoint("TOPLEFT", 0, y - 76)
  frame.resetWeights = button(page, T("Reset"), 80, function()
    weightsCommand("reset")
    refreshOptions()
  end)
  frame.resetWeights:SetPoint("LEFT", frame.applyWeights, "RIGHT", 6, 0)

  -- The things you would otherwise type.
  local actions = {
    { "Copy summary", function() frame:Hide(); command("") end },
    { "Start route", function() routeCommand("") end },
    { "Clear route", function() routeCommand("clear") end },
    { "Check my addons", function() addonsCommand() end },
  }
  frame.actions = {}
  local previous
  for i, action in ipairs(actions) do
    local b = button(page, T(action[1]), 137, action[2])
    if previous then b:SetPoint("LEFT", previous, "RIGHT", 6, 0) else b:SetPoint("BOTTOMLEFT", 0, 4) end
    previous = b
    frame.actions[i] = b
  end

  -- Help page: every feature explained, scrollable.
  local help = frame.pages.help
  local scroll = make("ScrollFrame", "TrailScoutOptionsScroll", help, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", -26, 0)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(530, 10)
  frame.helpText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.helpText:SetPoint("TOPLEFT", 0, 0)
  frame.helpText:SetWidth(530)
  frame.helpText:SetJustifyH("LEFT")
  frame.helpText:SetText(helpText())
  content:SetHeight((frame.helpText.GetStringHeight and frame.helpText:GetStringHeight() or 0) + 20)
  if scroll.SetScrollChild then scroll:SetScrollChild(content) end

  frame:Hide()
  return frame
end

-- Open the window on a page ("start", "settings" or "help"), or close it when it already
-- shows that one.
local function toggleOptions(page)
  if not optionsFrame then
    -- The window uses the client's own widget templates; if this client lacks one, say so
    -- and fall back to the help in chat instead of raising an error.
    local ok, built = pcall(buildOptions)
    if not ok or not built then
      say(T("the settings window could not be built on this client; here is the help instead.") .. " (" .. tostring(built) .. ")")
      helpCommand()
      return
    end
    optionsFrame = built
  end
  page = page or "start"
  if optionsFrame:IsShown() and optionsFrame.page == page then
    optionsFrame:Hide()
    return
  end
  refreshOptions()
  showOptionsPage(page)
  optionsFrame:Show()
end

-- Minimap button: left-click opens the window, right-click copies the summary, drag moves
-- it around the minimap.
local MINIMAP_RADIUS = 80
updateMinimapButton = function()
  if not minimapButton then return end
  local h = history()
  local angle = math.rad(h.minimapAngle or 215)
  minimapButton:ClearAllPoints()
  minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * MINIMAP_RADIUS, math.sin(angle) * MINIMAP_RADIUS)
  minimapButton:SetShown(setting("minimap"))
end

-- What both launcher buttons (minimap and floating) do: left-click opens the window,
-- right-click copies the summary, and the tooltip says so.
local function wireLauncher(b, anchor)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then command("") else toggleOptions("start") end
  end)
  b:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, anchor)
    GameTooltip:AddLine("TrailScout")
    GameTooltip:AddLine(T("Left-click: ask an AI, find things, settings and help"), 1, 1, 1)
    GameTooltip:AddLine(T("Right-click: copy the summary for an AI"), 1, 1, 1)
    GameTooltip:AddLine(T("Drag: move this button"), 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- Floating button: the same launcher as a free-standing icon that can be dragged anywhere
-- on screen, for players who hide or crowd their minimap. Its place is saved per character.
local FLOAT_DEFAULT = { "LEFT", "LEFT", 24, 140 }
local floatButton
updateFloatButton = function()
  if not floatButton then return end
  local pos = history().floatPos or FLOAT_DEFAULT
  floatButton:ClearAllPoints()
  floatButton:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  floatButton:SetShown(setting("floating"))
end

local function buildFloatButton()
  local b = CreateFrame("Button", "TrailScoutFloatButton", UIParent)
  b:SetSize(36, 36)
  b:SetFrameStrata("MEDIUM")
  b:SetMovable(true)
  b:SetClampedToScreen(true)
  b:RegisterForDrag("LeftButton")
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
  icon:SetAllPoints(b)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  wireLauncher(b, "ANCHOR_RIGHT")
  b:SetScript("OnDragStart", b.StartMoving)
  b:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint()
    if point and x and y then
      history().floatPos = { point, relativePoint or point, math.floor(x + 0.5), math.floor(y + 0.5) }
    end
  end)
  return b
end

local function buildMinimapButton()
  if not Minimap then return nil end
  local b = CreateFrame("Button", "TrailScoutMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForDrag("LeftButton")
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", 0, 0)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT", 0, 0)
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  wireLauncher(b, "ANCHOR_LEFT")
  local atan2 = math.atan2 or math.atan
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      if not (mx and my and cx and cy and scale) then return end
      history().minimapAngle = math.deg(atan2(cy / scale - my, cx / scale - mx))
      updateMinimapButton()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  return b
end

setupUi = function()
  if not minimapButton then minimapButton = buildMinimapButton() end
  updateMinimapButton()
  if not floatButton then floatButton = buildFloatButton() end
  updateFloatButton()
  -- First login of a character: open the window on its Start page, so a new player sees
  -- what the addon does without having to find a command.
  local h = history()
  if not h.introduced then
    h.introduced = true
    toggleOptions("start")
  end
end

-- Addon compartment entry on clients that have one (the TOC names this function).
function TrailScout_OnAddonCompartmentClick()
  toggleOptions("start")
end

command = function(msg)
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
  if lower == "config" or lower == "options" or lower == "settings" or lower == "ui" or lower == "opciones" then
    toggleOptions("settings")
    return
  end
  if lower == "guide" or lower == "guia" then
    toggleOptions("help")
    return
  end
  if lower == "addons" then
    addonsCommand()
    return
  end
  local routeLine = msg:match("^[Ii]mport%a*%s+(.+)$") or (msg:upper():find("^TSR1") and msg)
  if routeLine then
    importRoute(routeLine)
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
