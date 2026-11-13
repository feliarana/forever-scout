"""Paths and constants for the WoW Forever tooling.

Every path is derived from WOW_DIR and can be overridden with environment variables:
  WOW_DIR, WOW_ACCOUNT, WOW_REALM_DIR, WOW_CHAR, WOW_CHAR_LEVEL_HINT (unused).
Nothing here copies game data into the repo: all tools read the live files.
"""
import os
from pathlib import Path

REPO_DIR = Path(__file__).resolve().parent
DATA_DIR = REPO_DIR / "data"
Q_PKL = DATA_DIR / "Q.pkl"

WOW_DIR = Path(os.environ.get(
    "WOW_DIR",
    "/mnt/datosKingston/Lutris/drive_c/Program Files (x86)/World of Warcraft/_forever_",
))
ACCOUNT = os.environ.get("WOW_ACCOUNT", "80775418#1")
REALM_DIR = os.environ.get("WOW_REALM_DIR", "91")
CHARACTER = os.environ.get("WOW_CHAR", "Caza-Peques")

ADDONS_DIR = WOW_DIR / "Interface" / "AddOns"
ACCOUNT_DIR = WOW_DIR / "WTF" / "Account" / ACCOUNT
CHAR_SV_DIR = ACCOUNT_DIR / REALM_DIR / CHARACTER / "SavedVariables"

SNAPSHOT = Path(os.environ.get("FELIEXPORT_SNAPSHOT", CHAR_SV_DIR / "FeliExport.lua"))
SHORTESTPATH_SV = CHAR_SV_DIR / "ShortestPathForever.lua"
QUESTIE_CONFIG = ACCOUNT_DIR / "SavedVariables" / "Questie.lua"

QUESTIEDB_DIR = ADDONS_DIR / "QuestieDB"
QUESTIEDB_TOC = QUESTIEDB_DIR / "QuestieDB_Forever.toc"
QUESTIEDB_SUPPORT = QUESTIEDB_DIR / "support" / "Forever"
XP_TRACES = QUESTIEDB_SUPPORT / "QuestXP" / "xpDB-traces.lua"
XP_CLASSIC = QUESTIEDB_SUPPORT / "QuestXP" / "xpDB-classic.lua"
UIMAP_TO_AREA = QUESTIEDB_SUPPORT / "Zones" / "uiMapIdToAreaId.lua"
ITEM_DROPS = QUESTIEDB_SUPPORT / "DropTables" / "classicItemDrops.lua"
ZONES_ENUM = QUESTIEDB_DIR / "src" / "corrections" / "enum" / "zones.lua"

# Character identity used for quest filtering.
RACE_BIT = 128   # Troll
CLASS_BIT = 4    # Hunter

# Snapshot older than this (minutes) is considered stale.
STALE_MINUTES = 30

# Zone names in esMX (client locale), shown next to the English name from QuestieDB.
ZONE_NAMES_ES = {  # game data: esMX client names
    17: "Los Baldíos", 406: "Sierra Espolón", 331: "Vallefresno", 400: "Mil Agujas",
    267: "Laderas de Trabalomas", 130: "Bosque de Argénteos", 1497: "Entrañas",
    1637: "Orgrimmar", 1638: "Cima del Trueno", 14: "Durotar", 215: "Mulgore",
    85: "Claros de Tirisfal", 16611: "Ruinas de Lordaeron", 405: "Desolace",
    15: "Marjal Revolcafango", 40: "Páramos de Poniente", 36: "Montañas de Alterac",
    45: "Tierras Altas de Arathi", 33: "Vega de Tuercespina",
}

# Game uiMapID -> QuestieDB zone (area) ID. QuestieDB's uiMapIdToAreaId.lua fills the rest.
MAPID_TO_ZONE = {
    1413: 17, 1442: 406, 1440: 331, 1441: 400, 1424: 267, 1421: 130, 1454: 1637,
}

# Zone adjacency for "nearby" quest searches (symmetric; built below).
_NEIGHBOR_PAIRS = [
    (14, 1637), (14, 17), (17, 215), (215, 1638), (17, 406), (17, 331), (17, 400),
    (17, 15), (406, 331), (406, 405), (405, 357), (400, 357), (400, 440), (331, 16),
    (331, 361), (331, 148), (85, 130), (85, 1497), (85, 16611), (85, 28), (1497, 16611),
    (130, 267), (267, 36), (267, 45), (267, 47), (45, 11), (45, 47), (33, 10), (33, 40),
    (10, 40), (15, 440),
]
NEIGHBORS = {}
for _a, _b in _NEIGHBOR_PAIRS:
    NEIGHBORS.setdefault(_a, set()).add(_b)
    NEIGHBORS.setdefault(_b, set()).add(_a)

# Stat weights (RestedXP, hunter 20-29). "dps" applies only to ranged weapons.
STAT_WEIGHTS = {
    "dps": 14.0, "agi": 2.33, "spi": 1.12, "rap": 0.80, "sta": 0.75,
    "int": 0.55, "str": 0.20, "armor": 0.035,
}
