#!/usr/bin/env python3
"""Importe les 331 créatures du SRD 2024 (SRD 5.2) depuis l'API Open5e V2
et les convertit vers notre format de bloc de monstre.

Source : https://api.open5e.com/v2/creatures/?document__key__in=srd-2024
Licence des données : CC-BY-4.0 (SRD 5.2, Wizards of the Coast).
"""
import json, re, subprocess, sys

API = "https://api.open5e.com/v2/creatures/"
DOC = "srd-2024"

ABIL = {  # noms Open5e -> nos codes
    "strength": "FOR", "dexterity": "DEX", "constitution": "CON",
    "intelligence": "INT", "wisdom": "SAG", "charisma": "CHA",
}
NUMWORDS = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
            "seven": 7, "eight": 8, "nine": 9, "ten": 10}

ATK_RE   = re.compile(r"(Melee|Ranged)\s+Attack Roll:\s*([+\-]\d+)")
REACH_RE = re.compile(r"reach\s+(\d+)\s*ft", re.I)
RANGE_RE = re.compile(r"range\s+(\d+)(?:/(\d+))?\s*ft", re.I)
SAVE_RE  = re.compile(r"(Strength|Dexterity|Constitution|Intelligence|Wisdom|Charisma)\s+Saving Throw:\s*DC\s*(\d+)")
DMG_RE   = re.compile(r"(\d+)\s*(?:\(([0-9dD+\-\s]+)\)\s*)?([A-Za-z]+)\s+damage")
HALF_RE  = re.compile(r"Success:\s*Half", re.I)
COND_RE  = re.compile(r"(If [^.]*\bcondition\b[^.]*\.)")
# --- Multiattaque -------------------------------------------------------
# Familles gérées :
#   A. « makes N attacks, using X or Y in any combination » / « makes N X or Y attacks »
#      -> une option par arme (volée homogène : N× X, N× Y…).
#   B. séquence fixe « one X attack and two Y attacks » -> une option [1×X, 2×Y].
#   C. spéciaux : Hydra (« as many … as it has heads » -> 5), Tarrasque (préfixe fixe + reste libre).
# Les clauses « It can replace … » / « and it uses … » sont ignorées (l'attaque reste dispo en bouton simple).

def _count(tok):
    tok = tok.lower()
    return NUMWORDS.get(tok, int(tok) if tok.isdigit() else 1)


def _match_attack(fragment, names):
    """Apparie un fragment de texte à une attaque connue (exact, puis par inclusion)."""
    f = fragment.strip().strip(".").lower()
    if not f:
        return None
    for n in names:
        if n.strip().lower() == f:
            return n
    for n in names:
        nl = n.strip().lower()
        if f in nl or nl in f:
            return n
    return None


def _fixed_sequence(text, names):
    """Séquence fixe « N X attack(s) [and N Y attack(s)] » -> liste d'étapes (vide si rien)."""
    seq = []
    for m in re.finditer(r"\b(one|two|three|four|five|six|seven|eight|nine|ten|\d+)\s+"
                         r"([A-Za-z][\w' ]*?)\s+attacks?\b", text, re.I):
        nm = _match_attack(m.group(2), names)
        if nm:
            seq.append({"attack": nm, "count": _count(m.group(1))})
    return seq


def parse_multiattack(desc, names):
    """Renvoie une liste d'options (chacune = liste d'étapes {attack, count}). [] si rien."""
    base = re.split(r"\bit can replace\b|\band it can use\b|\band it uses\b|\bif available\b",
                    desc, maxsplit=1, flags=re.I)[0]

    # 0. Attaques complètes alternatives : « séquence A, or it makes séquence B ».
    alts = re.split(r",?\s*\bor it makes\b", base, flags=re.I)
    if len(alts) > 1:
        opts = [s for s in (_fixed_sequence(seg, names) for seg in alts) if s]
        if len(opts) >= 2:
            return opts

    # C. Tarrasque : « one Bite attack and three other attacks, using Claw or Tail … »
    mt = re.search(r"makes\s+(\w+)\s+([A-Za-z][\w' ]*?)\s+attack\s+and\s+(\w+)\s+other\s+attacks?,?"
                   r"\s+using\s+(.+?)\s+in any combination", base, re.I)
    if mt:
        pref = _match_attack(mt.group(2), names)
        first = _match_attack(re.split(r"\bor\b|\band\b|,", mt.group(4))[0], names)
        if pref and first:
            return [[{"attack": pref, "count": _count(mt.group(1))},
                     {"attack": first, "count": _count(mt.group(3))}]]

    # C. Hydra : autant d'attaques que de têtes -> 5 par défaut.
    mh = re.search(r"as many\s+([A-Za-z][\w' ]*?)\s+attacks?\s+as it has heads", base, re.I)
    if mh:
        nm = _match_attack(mh.group(1), names)
        if nm:
            return [[{"attack": nm, "count": 5}]]

    # A. choix libre entre plusieurs armes.
    listing, n = None, None
    mA = re.search(r"makes\s+([a-z]+|\d+)\s+attacks?,?\s+using\s+(.+?)\s+in any combination", base, re.I)
    if mA:
        n, listing = _count(mA.group(1)), mA.group(2)
    else:
        mA2 = re.search(r"makes\s+([a-z]+|\d+)\s+(.+?)\s+attacks?\b", base, re.I)
        if mA2 and " or " in mA2.group(2).lower():
            n, listing = _count(mA2.group(1)), mA2.group(2)
    if listing is not None and n:
        opts = []
        for fr in re.split(r"\bor\b|\band\b|,", listing, flags=re.I):
            nm = _match_attack(fr, names)
            if nm and not any(o[0]["attack"] == nm for o in opts):
                opts.append([{"attack": nm, "count": n}])
        if opts:
            return opts

    # B. séquence fixe simple.
    seq = _fixed_sequence(base, names)
    if seq:
        return [seq]

    return []


# --- Spellcasting --------------------------------------------------------

SPELL_INDEX = {}   # nom de sort -> données Open5e (rempli dans main)

SC_ABILITY_RE = re.compile(r"using\s+(\w+)\s+as\s+(?:the\s+)?spellcasting ability", re.I)
SC_DC_RE      = re.compile(r"spell save DC\s*(\d+)", re.I)
SC_ATKB_RE    = re.compile(r"\+(\d+)\s+to hit with spell attacks", re.I)
# Paliers : "- **At Will:** a, b, c" et "- **2/Day Each:** a, b"
SC_ATWILL_RE  = re.compile(r"\*\*\s*At Will\s*:\s*\*\*\s*(.+)", re.I)
SC_PERDAY_RE  = re.compile(r"\*\*\s*(\d+)\s*/\s*Day(?:\s+Each)?\s*:\s*\*\*\s*(.+)", re.I)

SHAPE_FR = {"sphere": "sphère", "cone": "cône", "line": "ligne", "cube": "cube",
            "cylinder": "cylindre", "square": "carré", "circle": "cercle",
            "wall": "mur", "radius": "rayon", "emanation": "émanation"}


def spell_area(s):
    """Zone d'effet « forme taille ft » à partir de shape_type/shape_size (None si absent)."""
    shp, sz = s.get("shape_type"), s.get("shape_size")
    if shp and isinstance(sz, (int, float)) and sz > 0:
        return f"{SHAPE_FR.get(str(shp).lower(), shp)} {int(sz)} ft"
    return None


def clean_spell_names(raw):
    """Découpe « a, b, c » en noms propres, en retirant le markdown résiduel."""
    out = []
    for piece in raw.split(","):
        n = re.sub(r"[\*\[\]]", "", piece).strip().rstrip(".")
        if n:
            out.append(n)
    return out


def build_spell_attack(s, dc, attack_bonus):
    """Convertit un sort en Attack si mécanique (dégâts/sauvegarde), sinon None.
    DD et bonus au toucher sont figés (valeurs du bloc) : pas de dérivation par carac."""
    desc = s.get("desc") or ""
    name = s["name"]
    dmg_roll = (s.get("damage_roll") or "").replace(" ", "")
    dmg_types = s.get("damage_types") or []
    # Dégâts fiables seulement si dés ET type présents (filtre soins, durées, mishap d100…).
    damage = [{"dice": dmg_roll, "type": dmg_types[0].lower()}] if dmg_roll and dmg_types else []
    area = spell_area(s)

    if s.get("saving_throw_ability"):
        atk = {"name": name, "kind": "save",
               "save": {"ability": ABIL[s["saving_throw_ability"].lower()], "dc": dc}}
        if damage:
            atk["damage"] = damage
        if re.search(r"half as much", desc, re.I):
            atk["halfOnSave"] = True
        cond = extract_condition(desc)
        if cond:
            atk["condition"] = cond
        if area:
            atk["area"] = area
        return atk
    if s.get("attack_roll") and damage:
        atk = {"name": name, "kind": "tohit",
               "toHit": attack_bonus if attack_bonus is not None else dc - 8,
               "damage": damage}
        cond = extract_condition(desc)
        if cond:
            atk["condition"] = cond
        if area:
            atk["area"] = area
        return atk
    return None   # sort utilitaire : pas d'Attack


def build_spellcasting(creature, abilities, prof, stats):
    """Cherche l'action de spellcasting et la convertit en (bloc, [attaques de sort], nom_action).
    Renvoie (None, [], None) si aucune action exploitable.
    `abilities`/`prof` servent à dériver un DD quand le bloc n'en indique pas."""
    action = None
    for a in (creature.get("actions") or []):
        nm = (a.get("name") or "")
        if nm in ("Spellcasting", "Hellfire Spellcasting") and a.get("action_type") == "ACTION":
            action = a
            break
    if not action:
        return None, [], None

    desc = action.get("desc") or ""
    am = SC_ABILITY_RE.search(desc)
    if not am:
        return None, [], None
    ability = ABIL.get(am.group(1).lower())
    if not ability:
        return None, [], None
    dm = SC_DC_RE.search(desc)
    # DD indiqué, sinon dérivé (8 + mod de la carac de lancement + maîtrise) — règle 5e.
    dc = int(dm.group(1)) if dm else 8 + amod(abilities[ability]) + prof
    bm = SC_ATKB_RE.search(desc)
    attack_bonus = int(bm.group(1)) if bm else None

    # Paliers ligne à ligne.
    tiers = []   # (uses_per_day|None, [noms])
    for line in desc.split("\n"):
        line = line.strip()
        m = SC_ATWILL_RE.search(line)
        if m:
            tiers.append((None, clean_spell_names(m.group(1))))
            continue
        m = SC_PERDAY_RE.search(line)
        if m:
            tiers.append((int(m.group(1)), clean_spell_names(m.group(2))))

    spells, spell_attacks = [], []
    seen = set()
    for uses, names in tiers:
        for n in names:
            if n in seen:
                continue
            seen.add(n)
            sdata = SPELL_INDEX.get(n)
            if not sdata:
                stats["spell_unmatched"].append(f"{creature['name']}: {n}")
                # On garde l'entrée (compteur) même sans données : utilitaire.
                spells.append({"name": n, "usesPerDay": uses, "mechanical": False})
                continue
            atk = build_spell_attack(sdata, dc, attack_bonus)
            entry = {"name": n, "usesPerDay": uses, "mechanical": atk is not None}
            if atk is not None:
                entry["attackName"] = n
                spell_attacks.append(atk)
                stats["spell_mechanical"] += 1
            else:
                stats["spell_narrative"] += 1
            spells.append(entry)

    if not spells:
        return None, [], None   # ex. Pit Fiend (format inline) : on laisse l'action en référence.

    block = {"ability": ability, "dc": dc, "spells": spells}
    if attack_bonus is not None:
        block["attackBonus"] = attack_bonus
    stats["spell_casters"] += 1
    return block, spell_attacks, action.get("name")



def prof_from_cr(cr):
    for hi, p in [(4, 2), (8, 3), (12, 4), (16, 5), (20, 6), (24, 7), (28, 8), (30, 9)]:
        if cr <= hi:
            return p
    return 9


# --- Dérivation : carac régissante + dés sans modificateur (schéma dérivé) ---

AB_ORDER = ["FOR", "DEX", "CON", "INT", "SAG", "CHA"]
MENTAL = ["INT", "CHA", "SAG"]
STRIP_MOD = re.compile(r"\s*[+-]\s*\d+\s*$")


def amod(score):
    return (score - 10) // 2   # // floore vers -∞ comme la règle 5e


def _strip_dice_mods(dmg):
    for c in dmg or []:
        c["dice"] = STRIP_MOD.sub("", c["dice"])


def _first_mod(dmg):
    """Modificateur cuit de la 1ʳᵉ composante de dégâts (0 si absente)."""
    if not dmg:
        return 0
    m = re.search(r"([+-]\d+)\s*$", dmg[0]["dice"])
    return int(m.group(1)) if m else 0


# États standard 5e (anglais) pour le champ compact `condition`.
CONDITIONS = ["Blinded", "Charmed", "Deafened", "Exhaustion", "Frightened", "Grappled",
              "Incapacitated", "Invisible", "Paralyzed", "Petrified", "Poisoned", "Prone",
              "Restrained", "Stunned", "Unconscious"]


def extract_condition(text):
    """Premier état standard mentionné dans le texte (par position), sinon None."""
    if not text:
        return None
    best, bestpos = None, 10 ** 9
    for c in CONDITIONS:
        m = re.search(r"\b" + c + r"\b", text)
        if m and m.start() < bestpos:
            bestpos, best = m.start(), c
    return best


def derive_attack(atk, abilities, prof):
    """Convertit une attaque (toHit/dc figés) vers le schéma dérivé :
    pose `ability`, `addAbilityToDamage`, retire les modificateurs des dés et les valeurs figées."""
    mods = {a: amod(abilities[a]) for a in AB_ORDER}
    if atk["kind"] == "tohit" and atk.get("toHit") is not None:
        th = atk["toHit"]
        cand = [a for a in AB_ORDER if mods[a] + prof == th] or \
               [min(AB_ORDER, key=lambda a: abs(mods[a] + prof - th))]
        ab = None
        if atk.get("range") and "DEX" in cand:
            ab = "DEX"
        if ab is None and atk.get("reach"):
            ab = next((a for a in ("FOR", "DEX") if a in cand), None)
        if ab is None:
            ab = next((a for a in MENTAL if a in cand), None)
        if ab is None:
            ab = next((a for a in ("FOR", "DEX") if a in cand), None)
        if ab is None:
            ab = cand[0]
        atk["ability"] = ab
        if _first_mod(atk.get("damage")) != 0:
            atk["addAbilityToDamage"] = True
        _strip_dice_mods(atk.get("damage"))
        atk.pop("toHit", None)
    elif atk["kind"] == "save" and atk.get("save"):
        dc = atk["save"].get("dc")
        if dc is not None:
            cand = [a for a in AB_ORDER if 8 + mods[a] + prof == dc] or \
                   [min(AB_ORDER, key=lambda a: abs(8 + mods[a] + prof - dc))]
            n = atk["name"].lower()
            ab = None
            if "breath" in n and "CON" in cand:
                ab = "CON"
            if ab is None:
                ab = next((a for a in MENTAL if a in cand), None)
            if ab is None and "CON" in cand:
                ab = "CON"
            if ab is None:
                ab = next((a for a in ("FOR", "DEX") if a in cand), None)
            if ab is None:
                ab = cand[0]
            atk["ability"] = ab
            atk["save"].pop("dc", None)
        if _first_mod(atk.get("damage")) != 0:
            atk["addAbilityToDamage"] = True
        _strip_dice_mods(atk.get("damage"))
    return atk


def parse_damage(text):
    comps = []
    for m in DMG_RE.finditer(text):
        dice = m.group(2).replace(" ", "") if m.group(2) else m.group(1)
        comps.append({"dice": dice, "type": m.group(3).lower()})
    return comps


def recharge_from(usage):
    if usage and usage.get("type") == "RECHARGE_ON_ROLL":
        p = usage.get("param", 6)
        return f"{p}-6" if p < 6 else "6"
    return None


def save_effect(desc):
    m = re.search(r"Failure:\s*(.*?)(?:Success:|Failure or Success:|$)", desc, re.S)
    if not m:
        return None
    eff = DMG_RE.sub("", m.group(1)).strip(" .\n")
    eff = re.sub(r"\s+", " ", eff)
    return eff if len(eff) > 3 else None


def build_attack(action, warnings):
    name, desc = action["name"], action["desc"]
    am = ATK_RE.search(desc)
    if am:
        atk = {"name": name, "kind": "tohit", "toHit": int(am.group(2)),
               "damage": parse_damage(desc)}
        rm = REACH_RE.search(desc)
        rg = RANGE_RE.search(desc)
        if rm:
            atk["reach"] = f"{rm.group(1)} ft"
        if rg:
            atk["range"] = f"{rg.group(1)}/{rg.group(2)} ft" if rg.group(2) else f"{rg.group(1)} ft"
        cm = COND_RE.search(desc)
        if cm:
            atk["effect"] = re.sub(r"\s+", " ", cm.group(1)).strip()
        cond = extract_condition(atk.get("effect"))
        if cond:
            atk["condition"] = cond
        if not atk["damage"] and not atk.get("effect"):
            warnings.append(f"toucher sans dégâts ni effet: {name}")
        return atk
    sm = SAVE_RE.search(desc)
    if sm:
        atk = {"name": name, "kind": "save",
               "save": {"ability": ABIL[sm.group(1).lower()], "dc": int(sm.group(2))},
               "damage": parse_damage(desc)}
        if HALF_RE.search(desc):
            atk["halfOnSave"] = True
        eff = save_effect(desc)
        if eff:
            atk["effect"] = eff
        cond = extract_condition(atk.get("effect"))
        if cond:
            atk["condition"] = cond
        rc = recharge_from(action.get("usage_limits"))
        if rc:
            atk["recharge"] = rc
        return atk
    return None  # pas une attaque parsable


def map_creature(c, stats):
    cr = c["challenge_rating"]
    prof = prof_from_cr(cr)

    # vitesse (clés anglaises, valeurs en pieds)
    sp = c.get("speed_all") or {}
    speed = {}
    for k in ("walk", "fly", "swim", "climb", "burrow"):
        v = sp.get(k)
        if isinstance(v, (int, float)) and v > 0:
            speed[k] = f"{int(v)} ft"
    if not speed and isinstance(sp.get("walk"), (int, float)):
        speed["walk"] = f"{int(sp['walk'])} ft"

    abil_src = c.get("ability_scores") or {}
    abilities = {ABIL[k]: abil_src.get(k, 10) for k in ABIL}

    sv = c.get("saving_throws") or {}
    mods = c.get("modifiers") or {}
    save_profs = [ABIL[k] for k in ABIL if k in sv and sv.get(k) != mods.get(k)]

    ri = c.get("resistances_and_immunities") or {}

    def disp(field):
        s = ri.get(field) or ""
        return [s] if s.strip() else None

    # actions -> attaques / multiattaque / références
    attacks, single_opts, trait_refs, multi_desc = [], [], [], None
    warnings = []
    # Économies d'action dont on extrait une vraie attaque (bouton). ACTION reste implicite (actionType absent).
    PARSEABLE = {"ACTION": None, "BONUS_ACTION": "bonus"}
    for a in c.get("actions") or []:
        name, atype = a["name"], a["action_type"]
        if name.lower() == "multiattack" and atype == "ACTION":
            multi_desc = a["desc"]
            continue
        if atype in PARSEABLE and (ATK_RE.search(a["desc"]) or SAVE_RE.search(a["desc"])):
            atk = build_attack(a, warnings)
            if atk:
                econ = PARSEABLE[atype]
                if econ:
                    atk["actionType"] = econ          # ex. "bonus" -> bouton « … (BA) »
                derive_attack(atk, abilities, prof)
                attacks.append(atk)
                single_opts.append(atk["name"])
                stats["tohit" if atk["kind"] == "tohit" else "save"] += 1
                if econ == "bonus":
                    stats["bonus_attacks"] += 1
                continue
        label = {"LEGENDARY_ACTION": "Action légendaire — ", "REACTION": "Réaction — ",
                 "BONUS_ACTION": "Action bonus — "}.get(atype, "")
        trait_refs.append({"name": label + name, "description": a["desc"]})

    options = []
    if multi_desc:
        seqs = parse_multiattack(multi_desc, single_opts)
        if seqs:
            for seq in seqs:
                options.append({"type": "multiattack", "description": multi_desc, "sequence": seq})
            stats["multi_parsed"] += 1
        else:
            trait_refs.append({"name": "Multiattaque", "description": multi_desc})
            stats["multi_text"] += 1
    for n in single_opts:
        options.append({"type": "single", "attack": n})

    # Spellcasting : bloc de sorts + attaques mécaniques associées.
    spellcasting, spell_attacks, sc_action_name = build_spellcasting(c, abilities, prof, stats)
    attacks += spell_attacks   # les attaques de sort vivent dans `attacks` mais PAS dans attackOptions
    if sc_action_name:
        # L'action convertie en bouton Sorts ne doit pas rester aussi en trait/référence.
        trait_refs = [t for t in trait_refs if t["name"] != sc_action_name]

    traits = [{"name": t["name"], "description": t.get("desc", "")} for t in (c.get("traits") or [])]
    traits += trait_refs

    if attacks:
        stats["with_attacks"] += 1
    stats["attacks_total"] += len(attacks)
    if warnings:
        stats["warnings"].extend([f"{c['name']}: {w}" for w in warnings])

    m = {
        "id": c["key"],
        "name": c["name"],
        "size": (c.get("size") or {}).get("name", ""),
        "type": (c.get("type") or {}).get("name", ""),
        "cr": cr,
        "proficiencyBonus": prof,
        "ac": c.get("armor_class", 10),
        "hp": {"average": c.get("hit_points", 0), "formula": c.get("hit_dice") or ""},
        "speed": speed,
        "abilities": abilities,
        "saveProficiencies": save_profs,
    }
    for key, field in [("damageResistances", "damage_resistances_display"),
                       ("damageImmunities", "damage_immunities_display"),
                       ("damageVulnerabilities", "damage_vulnerabilities_display"),
                       ("conditionImmunities", "condition_immunities_display")]:
        d = disp(field)
        if d:
            m[key] = d
    m["traits"] = traits
    m["attacks"] = attacks
    m["attackOptions"] = options
    if spellcasting:
        m["spellcasting"] = spellcasting
    return m


def fetch_page(page, limit=100, endpoint=None):
    base = endpoint or API
    url = f"{base}?document__key__in={DOC}&limit={limit}&page={page}"
    r = subprocess.run(["curl", "-s", "-m", "60", url], capture_output=True, text=True)
    return json.loads(r.stdout)


def fetch_all(endpoint):
    first = fetch_page(1, endpoint=endpoint)
    count = first["count"]
    items = list(first["results"])
    page = 2
    while len(items) < count:
        d = fetch_page(page, endpoint=endpoint)
        res = d.get("results") or []
        if not res:
            break
        items += res
        page += 1
    return items, count


def main():
    # Index des sorts SRD 2024 (pour le spellcasting des monstres).
    spells, scount = fetch_all("https://api.open5e.com/v2/spells/")
    for s in spells:
        SPELL_INDEX[s["name"]] = s
    print(f"Récupéré {len(spells)}/{scount} sorts srd-2024.")

    creatures, count = fetch_all(API)
    print(f"Récupéré {len(creatures)}/{count} créatures srd-2024.")

    stats = {"with_attacks": 0, "attacks_total": 0, "tohit": 0, "save": 0,
             "bonus_attacks": 0, "multi_parsed": 0, "multi_text": 0, "warnings": [],
             "spell_casters": 0, "spell_mechanical": 0, "spell_narrative": 0,
             "spell_unmatched": []}
    monsters = [map_creature(c, stats) for c in creatures]
    monsters.sort(key=lambda m: m["name"])

    with open("srd-2024-monsters.json", "w", encoding="utf-8") as f:
        json.dump(monsters, f, ensure_ascii=False, indent=1)

    print(f"Monstres mappés       : {len(monsters)}")
    print(f"  avec attaques       : {stats['with_attacks']}")
    print(f"  attaques au total   : {stats['attacks_total']} (toucher {stats['tohit']}, sauvegarde {stats['save']})")
    print(f"  dont actions bonus  : {stats['bonus_attacks']}")
    print(f"  multiattaques OK     : {stats['multi_parsed']}  | laissées en texte : {stats['multi_text']}")
    print(f"  lanceurs de sorts    : {stats['spell_casters']} "
          f"(sorts mécaniques {stats['spell_mechanical']}, utilitaires {stats['spell_narrative']})")
    if stats["spell_unmatched"]:
        print(f"  sorts non appariés   : {len(stats['spell_unmatched'])}")
        for w in stats["spell_unmatched"][:8]:
            print("    -", w)
    print(f"  avertissements      : {len(stats['warnings'])}")
    for w in stats["warnings"][:8]:
        print("    -", w)


if __name__ == "__main__":
    main()
