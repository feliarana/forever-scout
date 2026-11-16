**TrailScout** takes a snapshot of your character so an AI assistant can plan your next steps with you: quests with objectives, gear, bags, talents, professions, party and online friends. It works for every class and faction on **World of Warcraft: Forever**.

## What you get in game

- **Minimap button** — opens a window with ready-made questions to copy into an AI chat (*What should I do next?*, *Where do my talent points go?*), a search box for NPCs and objects, a switch for every feature and a Help page. It opens by itself the first time: no command has to be typed.
- **`/scout`** — a summary of your character in a copy box. Press Ctrl+C and paste it into any AI chat together with your question.
- **`/whereis <name>`** — finds an NPC or an object in the world: how far it is, an arrow to it and a **[Show on map]** link. It also follows a party member.
- **`/scout route`** — walks a route stop by stop with waypoints, objectives first and turn-ins last (routes come from the offline tools).
- **Reminders** — nearly full bags, low durability, unspent talent points. Hunters also get low ammo and a dead, missing or unhappy pet.
- **Loot advice** — NEED or GREED on every roll, and a score line on gear tooltips against what you wear. Hunters have built-in stat weights; every other class sets its own with `/scout weights`.
- **`/scout help`** — every command, in English or Spanish to match your client.

## Quick start

1. Install the addon and log in. Chat shows `TrailScout: loaded. Type /scout help`.
2. Type `/scout`, press Ctrl+C in the box that opens, and paste the line into your AI chat with a question like *"what should I do next?"*.

## Going further

`/reload` writes the full snapshot to disk. Free companion tools (in the source repository linked at the bottom of this page) read it together with your installed Questie database and tell an AI assistant where every quest objective and turn-in is, what is on your way, what to sell, where your talent and legacy points can go and which route to take. That part needs Python and is optional.

## Good to know

- **Questie and TomTom are optional.** `/whereis` needs Questie, and TomTom adds the arrow. `/scout route` needs TomTom. Everything else works without them.
- **Privacy:** the snapshot and the copy box include the names of party members, friends, guild and communities. Nothing leaves your computer unless you paste or share it.
- **It does not play for you.** It only reads what any addon can read and shows you information.
- The game only saves addon data on `/reload` or logout, so the full snapshot needs a `/reload`.
- **English and Spanish:** the whole addon follows your game client, Spanish on esMX / esES and English everywhere else. *Descripción en español más abajo.*

---

## En español

**TrailScout** saca una foto de tu personaje para que un asistente de IA planifique contigo los próximos pasos: misiones con sus objetivos, equipo, bolsas, talentos, profesiones, grupo y amigos conectados. Funciona con cualquier clase y facción en **World of Warcraft: Forever**. Si tu juego está en español (esMX o esES), todo el addon aparece en español; en cualquier otro idioma, en inglés.

### Qué obtienes dentro del juego

- **Botón en el minimapa** — abre una ventana con preguntas listas para copiarle a una IA (*¿Qué hago ahora?*, *¿Dónde pongo mis talentos?*), un buscador de NPCs y objetos, un interruptor para cada función y una página de ayuda. La primera vez se abre sola: no hace falta escribir ningún comando.
- **`/scout`** — un resumen de tu personaje en una caja para copiar. Presiona Ctrl+C y pégalo en cualquier chat de IA junto con tu pregunta.
- **`/whereis <nombre>`** — encuentra un NPC o un objeto del mundo: a qué distancia está, una flecha y un enlace **[Ver en mapa]**. También sigue a un miembro del grupo.
- **`/scout route`** — recorre una ruta parada por parada con puntos en el mapa, primero los objetivos y al final las entregas (las rutas salen de las herramientas complementarias).
- **Avisos** — bolsas casi llenas, equipo a punto de romperse, puntos de talento sin gastar. Los cazadores también reciben poca munición y mascota muerta, ausente o descontenta. Cada aviso se puede apagar por separado.
- **Consejo de botín** — NECESIDAD o CODICIA en cada tirada, y una línea de puntaje en los tooltips de equipo contra lo que llevas puesto. Los cazadores traen pesos de estadísticas de fábrica; las demás clases cargan los suyos con `/scout weights`.

### Para empezar

1. Instala el addon y entra al juego. El chat muestra `TrailScout: cargado. Escribe /scout help`.
2. Escribe `/scout`, presiona Ctrl+C en la caja que se abre y pega la línea en tu chat de IA con una pregunta como *"¿qué me conviene hacer ahora?"*.

### Para ir más lejos

`/reload` escribe la foto completa al disco. Las herramientas complementarias gratuitas (en el repositorio de código enlazado al final de esta página) la leen junto con tu base de datos de Questie y le dicen a un asistente de IA dónde está cada objetivo y cada entrega, qué te queda de camino, qué vender, dónde pueden ir tus puntos de talento y de legado, y qué ruta tomar. Esa parte necesita Python y es opcional.

### Bueno saber

- **Questie y TomTom son opcionales.** `/whereis` necesita Questie, y TomTom agrega la flecha. `/scout route` necesita TomTom. Todo lo demás funciona sin ellos.
- **Privacidad:** la foto y la caja de copiar incluyen los nombres de los miembros de tu grupo, amigos, hermandad y comunidades. Nada sale de tu computadora a menos que lo pegues o lo compartas.
- **No juega por ti.** Solo lee lo que cualquier addon puede leer y te muestra información.
- El juego solo guarda los datos de los addons al hacer `/reload` o al salir, por eso la foto completa necesita un `/reload`.

---

Source code, issue tracker and the optional companion tools · Código fuente, reporte de problemas y herramientas complementarias: [github.com/feliarana/trail-scout-wow](https://github.com/feliarana/trail-scout-wow). MIT license.
