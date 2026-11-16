# CurseForge listing

Texts for the TrailScout project page. The logo is `assets/logo-400.png`
(`assets/make_logo.py` redraws it).

## Create-project form

| Field | Value |
|---|---|
| Project name | Trail Scout (slug `trail-scout`). Not ForeverScout: another project already has that name |
| Logo | `assets/logo-400.png` |
| Summary | Character snapshot for AI assistants, plus NPC arrows, route waypoints, upkeep alerts and loot advice. |
| Main category | Quests & Leveling |
| Additional categories | Map & Minimap, Data Export, Tooltip |
| Allow comments | yes |
| Unlisted | yes until friends have tested it, then listed |
| Social links | Source: https://github.com/feliarana/trail-scout-wow |

Optional dependencies to declare on the page: Questie and TomTom (only `/whereis` and
`/scout route` use them).

## Description

The page description is [curseforge-description.md](curseforge-description.md): paste the
whole file with the editor set to Markdown. It is kept one paragraph or bullet per line, with
no hard wraps, because some Markdown editors turn every line break into a visible one.

## Moderation policies that shaped this page

From CurseForge's moderation policies (read November 2026):

- **Name** in English, without the game name, a class or a version, and distinct from other
  projects. That is why it is Trail Scout and not ForeverScout.
- **Summary** is one sentence and does not copy the description.
- **Description** says concretely what the addon does.
- **Logo** is exactly 400x400, not WebP, not a solid colour, no copyrighted imagery.
- **No external download links for files.** The description links the source repository once,
  at the bottom, as source and issue tracker, not as a place to download the addon. Personal
  and cross-hosting links belong after the description.
- **Every file needs a changelog** describing what changed since the previous one.
- **Other languages** are allowed in the description, after the English text. CurseForge shows
  the same description to every visitor (it does not pick one by browser or game language),
  so the Spanish version is a second section below the English one. The project name and the
  summary stay in English.
- **Showcase images** that are AI-generated or edited in a way that could misrepresent the
  addon need a visible disclaimer: use real in-game screenshots in the gallery.

## Uploading a release

1. Bump `## Version:` in `addon/TrailScout/TrailScout.toc` and `version` in `package.json`.
   Add the version's section at the top of `CHANGELOG.md`.
2. Run the tests (`npm test` and the Python suite), then
   `.venv/bin/python tools/build_release.py`. It writes `dist/TrailScout-<version>.zip`.
3. On the project page: **Files → Upload file**, pick the zip.
   - Display name: `TrailScout <version>`.
   - Release type: Beta until other players have confirmed it works, then Release.
   - Game version: the World of Warcraft: Forever version the TOC targets (Interface 16001).
   - Changelog: the section of that version in `CHANGELOG.md` (Markdown).
4. License on the project settings: MIT, the same as `LICENSE` in the repository.
5. Relations: Questie and TomTom as optional dependencies.
