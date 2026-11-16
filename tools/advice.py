"""Class and profession pointers built from the snapshot: where talent and perk points can go
(with the game's own descriptions) and what each profession needs next.

Pure functions that return lines of text, used by analyze.py. Everything comes from what the
client reported; rules taken from Classic are labelled as such.
"""

# Recipe difficulty as the client reports it (relativeDifficulty), best skill-up first.
DIFFICULTY = {"0": "orange", "1": "yellow", "2": "green", "3": "gray",
              "optimal": "orange", "medium": "yellow", "easy": "green", "trivial": "gray"}
SKILL_UP = ("orange", "yellow")
# Skinning in the client languages the tools know (the snapshot stores localized names).
SKINNING_NAMES = {"skinning", "desuello"}
# Gathering skills level by gathering, not by recipes: their recipe list is ignored (the
# client can report another profession's list for them).
GATHERING_NAMES = SKINNING_NAMES | {"fishing", "pesca", "herbalism", "herboristería", "herboristeria"}
# Points from the cap at which the next rank should already be planned.
NEAR_CAP = 15
MAX_DESC = 150
# Trait systems and trees seen on the Forever client (the client gives them no name). The
# Legacy trees were identified by their perks: cooking and gathering perks, Well Rested and
# Talented, reputation and honour perks.
SYSTEM_NAMES = {45: "Legacy"}
TREE_NAMES = {1187: "Professions", 1188: "Adventure", 1189: "Resourcefulness"}


def _short(text, limit=MAX_DESC):
    text = " ".join(str(text or "").split())
    return text if len(text) <= limit else text[:limit - 1] + "…"


def _points(trees):
    """(spent, available, max) over a set of trees. Trees of one system share a currency, so
    each currency ID is counted once."""
    seen = {}
    for tree in trees:
        for cur in tree.get("currencies") or []:
            seen[cur.get("id")] = cur
    spent = sum(c.get("spent") or 0 for c in seen.values())
    available = sum(c.get("available") or 0 for c in seen.values())
    cap = sum(c.get("max") or 0 for c in seen.values())
    return spent, available, cap


def _buyable(tree):
    """Nodes a point can go into right now, top row first."""
    nodes = sorted(tree.get("nodes") or [], key=lambda n: (n.get("y") or 0, n.get("x") or 0))
    return [n for n in nodes if n.get("canBuy") and (n.get("rank") or 0) < (n.get("max") or 0)]


def _node_line(node, tree_name=None):
    line = f"    - {node.get('name')} {node.get('rank') or 0}/{node.get('max')}"
    if tree_name:
        line += f" [{tree_name}]"
    if node.get("desc"):
        line += f": {_short(node['desc'])}"
    return line


def tree_lines(title, trees, earned_label=False):
    """Lines for one set of trait trees (class talents, or one perk system). With
    `earned_label` the currency maximum is what the account has earned, not a level cap."""
    spent, available, cap = _points(trees)
    head = f"{title}: {spent} spent"
    if cap:
        head += f" of {cap} earned" if earned_label else f" of {cap}"
    if not available:
        return [head + ", no points to spend"]
    lines = [head + f" — !! {available} unspent"]
    options = [(n, TREE_NAMES.get(tree.get("treeID"))) for tree in trees for n in _buyable(tree)]
    if options:
        lines.append("  a point can go into:")
        lines += [_node_line(n, name) for n, name in options]
    else:
        lines.append("  the addon did not report which talents accept a point")
    return lines


def talent_lines(snap):
    lines = []
    talents = snap.get("talents") or {}
    if talents.get("trees"):
        lines += tree_lines("Class talents", talents["trees"])
    systems = snap.get("traitSystems")
    readable = [sy for sy in systems or [] if any(t.get("nodes") for t in sy.get("trees") or [])]
    for system in readable:
        sid = system.get("systemID")
        name = system.get("name") or SYSTEM_NAMES.get(sid) or f"Perk system {sid}"
        lines += tree_lines(f"{name} points", system.get("trees") or [], earned_label=True)
    if "traitSystems" not in snap:
        lines.append("Other perk trees (legacy points): not captured, the addon is older than this tool: /reload")
    elif not readable:
        lines.append("Other perk trees (legacy points): the client reported none through the trait API "
                     "(see traitApi in the snapshot); ask the player for their legacy points")
    return lines


def skinning_max_level(skill):
    """Highest mob level a skinning skill can skin, by the Classic rule."""
    return skill // 5 if skill >= 100 else skill // 10 + 10


def profession_lines(snap, level=None):
    lines = []
    recipes = snap.get("recipes") or {}
    for skill in sorted(snap.get("skills") or [], key=lambda s: -(s.get("rank") or 0)):
        name, rank, cap = skill.get("name"), skill.get("rank") or 0, skill.get("max") or 0
        line = f"{name} {rank}/{cap}"
        if cap and rank >= cap:
            line += " — !! at the cap: train the next rank before skilling further"
        elif cap and cap - rank <= NEAR_CAP:
            line += f" — {cap - rank} from the cap: train the next rank soon"
        if str(name).lower() in SKINNING_NAMES:
            reach = skinning_max_level(rank)
            line += f" — skins mobs up to level {reach} (Classic rule)"
            if level and reach < level:
                line += f" !! below your level {level}: mobs of your level will not be skinnable"
        lines.append(line)
        if str(name).lower() in GATHERING_NAMES:
            continue
        known = recipes.get(name) or {}
        by_colour = {}
        for recipe in known.get("list") or []:
            colour = DIFFICULTY.get(str(recipe.get("color")).lower())
            if colour in SKILL_UP:
                by_colour.setdefault(colour, []).append(str(recipe.get("name")))
        if by_colour:
            parts = [f"{colour}: {', '.join(by_colour[colour])}" for colour in SKILL_UP if colour in by_colour]
            lines.append(f"    skill-up recipes as of {known.get('at')}: " + "; ".join(parts))
        elif known.get("list"):
            lines.append(f"    no orange or yellow recipe known as of {known.get('at')}: "
                         "new recipes needed to keep skilling (trainer or vendor)")
        elif rank:
            lines.append("    recipes not captured yet: open the profession window once, then /reload")
    return lines
