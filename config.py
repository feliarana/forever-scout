"""Paths and constants for the WoW Forever tooling.

Every path is derived from WOW_DIR. Environment overrides:
  WOW_DIR            game folder (the one holding Interface/ and WTF/)
  WOW_ACCOUNT        WTF/Account/<name>; auto-detected when there is only one (else newest)
  WOW_CHAR           main character, as its WTF folder name ("Caza-Peques") or name ("Caza");
                     default: the highest-level character with a TrailScout snapshot
  TRAILSCOUT_SNAPSHOT  explicit snapshot file (overrides WOW_CHAR)
  WOW_AUCTION_REALM  Auctionator price database key (default: all keys)
Every tool also accepts `--char NAME`. Characters are discovered from WTF, so any number of
characters (mains, alts, bank alts) on any realm folder is supported.
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
ADDONS_DIR = WOW_DIR / "Interface" / "AddOns"
ACCOUNTS_DIR = WOW_DIR / "WTF" / "Account"


def _detect_account():
    if os.environ.get("WOW_ACCOUNT"):
        return os.environ["WOW_ACCOUNT"]
    if not ACCOUNTS_DIR.is_dir():
        return ""
    accounts = [d for d in ACCOUNTS_DIR.iterdir() if d.is_dir() and d.name != "SavedVariables"]
    if not accounts:
        return ""
    return max(accounts, key=lambda d: d.stat().st_mtime).name


ACCOUNT = _detect_account()
ACCOUNT_DIR = ACCOUNTS_DIR / ACCOUNT
ACCOUNT_SV_DIR = ACCOUNT_DIR / "SavedVariables"
CHARACTER = os.environ.get("WOW_CHAR", "")
# FOREVERSCOUT_SNAPSHOT and FELIEXPORT_SNAPSHOT are the names used before the addon was renamed.
SNAPSHOT_OVERRIDE = (os.environ.get("TRAILSCOUT_SNAPSHOT") or os.environ.get("FOREVERSCOUT_SNAPSHOT")
                     or os.environ.get("FELIEXPORT_SNAPSHOT", ""))


def character_dirs():
    """Every WTF/Account/<account>/<realm>/<character> folder that has SavedVariables."""
    found = []
    if not ACCOUNT_DIR.is_dir():
        return found
    for realm in sorted(ACCOUNT_DIR.iterdir()):
        if not realm.is_dir() or realm.name == "SavedVariables":
            continue
        for char in sorted(realm.iterdir()):
            if (char / "SavedVariables").is_dir():
                found.append(char)
    return found


def char_sv(char_dir, addon):
    """Per-character SavedVariables file of an addon."""
    return Path(char_dir) / "SavedVariables" / f"{addon}.lua"


QUESTIE_CONFIG = ACCOUNT_SV_DIR / "Questie.lua"
SYNDICATOR_SV = ACCOUNT_SV_DIR / "Syndicator.lua"     # bags/bank/mail of every character
AUCTIONATOR_SV = ACCOUNT_SV_DIR / "Auctionator.lua"   # AH price database + vendor price cache
# Auctionator price database realm key; empty = use every key found.
AUCTION_REALM_KEY = os.environ.get("WOW_AUCTION_REALM", "")

QUESTIEDB_DIR = ADDONS_DIR / "QuestieDB"
QUESTIEDB_TOC = QUESTIEDB_DIR / "QuestieDB_Forever.toc"
QUESTIEDB_SUPPORT = QUESTIEDB_DIR / "support" / "Forever"
XP_TRACES = QUESTIEDB_SUPPORT / "QuestXP" / "xpDB-traces.lua"
XP_CLASSIC = QUESTIEDB_SUPPORT / "QuestXP" / "xpDB-classic.lua"
UIMAP_TO_AREA = QUESTIEDB_SUPPORT / "Zones" / "uiMapIdToAreaId.lua"
ITEM_DROPS = QUESTIEDB_SUPPORT / "DropTables" / "classicItemDrops.lua"
ZONES_ENUM = QUESTIEDB_DIR / "src" / "corrections" / "enum" / "zones.lua"

# Quest race/class masks (QuestieDB). Keys are the non-localized client tokens.
RACE_BITS = {
    "Human": 1, "Orc": 2, "Dwarf": 4, "NightElf": 8, "Scourge": 16, "Undead": 16,
    "Tauren": 32, "Gnome": 64, "Troll": 128,
}
CLASS_BITS = {
    "WARRIOR": 1, "PALADIN": 2, "HUNTER": 4, "ROGUE": 8, "PRIEST": 16, "SHAMAN": 64,
    "MAGE": 128, "WARLOCK": 256, "DRUID": 1024,
}
HORDE_RACES = {"Orc", "Scourge", "Undead", "Tauren", "Troll"}

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

# Stat weights per class token (RestedXP, hunter 20-29). "dps" applies only to ranged weapons.
# Classes without weights skip the bag-upgrade check.
STAT_WEIGHTS = {
    "HUNTER": {
        "dps": 14.0, "agi": 2.33, "spi": 1.12, "rap": 0.80, "sta": 0.75,
        "int": 0.55, "str": 0.20, "armor": 0.035,
    },
}

# Items inventory.py always recommends keeping, with the reason (professions: Skinning +
# Leatherworking; First Aid, Cooking, Fishing). Edit as professions level up.
KEEP_ITEMS = {
    # Leatherworking
    2318: "LW: Light Leather", 2319: "LW: Medium Leather", 783: "LW: Light Hide",
    4232: "LW: Medium Hide", 4231: "LW: Cured Light Hide", 2320: "LW: Coarse Thread",
    2321: "LW: Fine Thread", 4293: "LW pattern (learn at 100)", 6476: "LW pattern",
    6470: "LW: Deviate Scale", 6471: "LW: Perfect Deviate Scale", 249427: "LW: check tooltip",
    # First Aid
    2592: "First Aid: wool bandages (103 -> 150)", 4306: "First Aid: silk bandages at 150",
    3530: "Bandage (use)", 2581: "Bandage (use)",
    # Cooking
    5467: "Cooking", 5469: "Cooking", 6289: "Cooking", 6291: "Cooking (skill-up now)",
    6303: "Cooking (skill-up now)", 6308: "Cooking",
    # Tools and camp buffs
    6256: "Fishing", 7005: "Skinning", 6948: "Hearthstone", 279978: "Camp buff",
    279981: "Camp buff", 279968: "First Aid kit", 3030: "Current ammo",
    250187: "Bound recipe: learn",
    # Food: eat or feed the boar (boars eat every food type)
    117: "Food / pet food", 159: "Drink", 1179: "Drink", 1205: "Drink", 9451: "Drink",
    2287: "Food / pet food", 2679: "Food / pet food", 3448: "Food / pet food",
    4536: "Food / pet food", 4537: "Food / pet food", 4542: "Food / pet food",
    4604: "Food / pet food", 11584: "Food / pet food",
    # Scrolls: use before hard pulls
    954: "Scroll (use)", 955: "Scroll (use)", 1180: "Scroll (use)", 1181: "Scroll (use)",
}

# Items assembled in game from other items: {result: [parts]}. QuestieDB does not record
# these, so the parts of a quest objective would look like junk to sell. Classic data, not
# verified on Forever: Shredder Operating Manual chapters are made of four pages each.
ITEM_PARTS = {
    16642: [16645, 16646, 16647, 16648],   # Chapter 1 <- Pages 1-4
    16643: [16649, 16650, 16651, 16652],   # Chapter 2 <- Pages 5-8
    16644: [16653, 16654, 16655, 16656],   # Chapter 3 <- Pages 9-12
}

# Mail is returned or deleted when it expires: warn this many days before.
MAIL_EXPIRY_WARN_DAYS = 5

# Auction house cut in Classic (deducted from the sale price).
AH_CUT = 0.05
