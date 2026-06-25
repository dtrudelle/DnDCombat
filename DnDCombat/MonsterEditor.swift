import SwiftUI

// Listes de référence (états et types de dégâts en anglais, comme le SRD).
private let dndConditions = [
    "Blinded", "Charmed", "Deafened", "Exhaustion", "Frightened", "Grappled",
    "Incapacitated", "Invisible", "Paralyzed", "Petrified", "Poisoned", "Prone",
    "Restrained", "Stunned", "Unconscious"
]
private let dndDamageTypes = [
    "acid", "bludgeoning", "cold", "fire", "force", "lightning", "necrotic",
    "piercing", "poison", "psychic", "radiant", "slashing", "thunder"
]
// Types proposés dans les menus de défense : les 13 du SRD + deux raccourcis.
// "physical" = contondant + perforant + tranchant ; "nonmagical" = dégâts d'armes non magiques.
private let dndDamageTypesAll = dndDamageTypes + ["physical", "nonmagical"]
// Immunités aux états : mêmes états que la liste, en minuscules comme le SRD.
private let dndConditionImmunities = dndConditions.map { $0.lowercased() }

/// Menu déroulant à choix multiple : coche/décoche des termes, stockés dans un [String]?.
private struct MultiSelectMenu: View {
    let title: String
    let options: [String]
    @Binding var values: [String]?

    var body: some View {
        LabeledContent(title) {
            Menu {
                ForEach(options, id: \.self) { opt in
                    Toggle(opt.capitalized, isOn: binding(for: opt))
                }
                if values?.isEmpty == false {
                    Divider()
                    Button("Tout effacer", role: .destructive) { values = nil }
                }
            } label: {
                Text(summary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var summary: String {
        let v = values ?? []
        return v.isEmpty ? "Aucune" : v.map { $0.capitalized }.joined(separator: ", ")
    }

    private func binding(for opt: String) -> Binding<Bool> {
        Binding(
            get: { (values ?? []).contains(opt) },
            set: { isOn in
                var arr = values ?? []
                if isOn { if !arr.contains(opt) { arr.append(opt) } }
                else { arr.removeAll { $0 == opt } }
                values = arr.isEmpty ? nil : arr
            }
        )
    }
}

private func actionLabel(_ e: ActionEconomy) -> String {
    switch e {
    case .action:    return "Action"
    case .bonus:     return "Action bonus"
    case .reaction:  return "Réaction"
    case .legendary: return "Action légendaire"
    }
}

// MARK: - Bibliothèque de monstres (duplication / édition / suppression / import)

struct MonsterLibrarySheet: View {
    @Environment(Library.self) private var library
    @Environment(Encounter.self) private var enc
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selected: Monster.ID?
    @State private var editing: Monster?
    @State private var showImport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bibliothèque de monstres").font(.headline)
            Text("Dupliquez un monstre pour créer une version « maison » éditable. Les blocs SRD restent intacts.")
                .font(.caption).foregroundStyle(.secondary)

            TextField("Rechercher…", text: $query).textFieldStyle(.roundedBorder)

            List(selection: $selected) {
                ForEach(library.search(query)) { m in
                    row(m).tag(m.id)
                }
            }
            .frame(minHeight: 320)

            HStack {
                Button { showImport = true } label: {
                    Label("Importer…", systemImage: "square.and.arrow.down")
                }
                Button {
                    if let id = selected, let m = library.monsters.first(where: { $0.id == id }) {
                        enc.reinforce(m, count: 1)
                    }
                } label: { Label("Ajouter à la rencontre", systemImage: "plus.circle") }
                .disabled(selected == nil)

                Spacer()
                Button("Fermer") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 580, height: 540)
        .sheet(item: $editing) { m in MonsterEditorSheet(monster: m) }
        .sheet(isPresented: $showImport) { ImportMonsterSheet() }
    }

    private func row(_ m: Monster) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(m.name)
                    if library.isCustom(m.id) {
                        Text("maison")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.20)))
                    }
                }
                Text("FP \(crLabel(m.cr)) · CA \(m.ac) · \(m.hp.average) PV")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { duplicate(m) } label: { Image(systemName: "plus.square.on.square") }
                .help("Dupliquer en version maison")
            if library.isCustom(m.id) {
                Button { editing = m } label: { Image(systemName: "pencil") }
                    .help("Éditer")
                Button(role: .destructive) {
                    if selected == m.id { selected = nil }
                    library.deleteCustom(m.id)
                } label: { Image(systemName: "trash") }
                    .help("Supprimer")
            }
        }
        .buttonStyle(.borderless)
    }

    private func duplicate(_ source: Monster) {
        let copy = library.duplicate(source)
        library.upsertCustom(copy)
        selected = copy.id
        editing = copy
    }
}

// MARK: - Éditeur d'un monstre maison

struct MonsterEditorSheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Monster
    @State private var traitRows: [TraitRow]
    @State private var speedRows: [SpeedRow]
    @State private var attackDrafts: [AttackDraft]
    @State private var optionDrafts: [OptionDraft]
    @State private var spellcastingDraft: SpellcastingDraft?
    @State private var error: String?

    init(monster: Monster) {
        _draft = State(initialValue: monster)
        _traitRows = State(initialValue: (monster.traits ?? []).map {
            TraitRow(name: $0.name, description: $0.description)
        })
        _speedRows = State(initialValue: monster.speed.map {
            SpeedRow(key: $0.key, value: $0.value)
        })
        _attackDrafts = State(initialValue: monster.attacks.map {
            AttackDraft(from: $0, monster: monster)
        })
        _optionDrafts = State(initialValue: monster.attackOptions.map {
            OptionDraft(from: $0)
        })
        _spellcastingDraft = State(initialValue: monster.spellcasting.map { SpellcastingDraft(from: $0) })
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("Éditer « \(draft.name) »").font(.headline)

            TabView {
                statsForm.tabItem { Label("Caractéristiques", systemImage: "list.bullet.rectangle") }
                attacksTab.tabItem { Label("Attaques", systemImage: "bolt.fill") }
                optionsTab.tabItem { Label("Bouton Attaque", systemImage: "hand.tap") }
                spellcastingTab.tabItem { Label("Sorts", systemImage: "sparkles") }
            }

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                Button("Enregistrer", action: save).buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 680, height: 700)
    }

    // MARK: Onglet caractéristiques

    private var statsForm: some View {
        Form {
            Section("Identité") {
                LabeledContent("Identifiant") {
                    Text(draft.id).foregroundStyle(.secondary).textSelection(.enabled)
                }
                TextField("Nom", text: $draft.name)
                TextField("Taille", text: $draft.size)
                TextField("Type", text: $draft.type)
                TextField("Facteur de puissance", value: $draft.cr, format: .number)
            }

            Section("Combat") {
                TextField("Classe d'armure", value: $draft.ac, format: .number)
                TextField("Bonus de maîtrise", value: $draft.proficiencyBonus, format: .number)
                TextField("PV moyens", value: $draft.hp.average, format: .number)
                TextField("Formule de PV (ex. 4d10+4)", text: $draft.hp.formula)
                TextField("Wounds (système maison, défaut 1)", value: woundsBinding, format: .number)
            }

            Section("Caractéristiques") {
                HStack(spacing: 10) {
                    AbilityField(label: "FOR", value: $draft.abilities.FOR)
                    AbilityField(label: "DEX", value: $draft.abilities.DEX)
                    AbilityField(label: "CON", value: $draft.abilities.CON)
                    AbilityField(label: "INT", value: $draft.abilities.INT)
                    AbilityField(label: "SAG", value: $draft.abilities.SAG)
                    AbilityField(label: "CHA", value: $draft.abilities.CHA)
                }
                HStack(spacing: 12) {
                    Text("Maîtrises de sauvegarde :").font(.caption).foregroundStyle(.secondary)
                    ForEach(Ability.allCases, id: \.self) { ab in
                        Toggle(ab.rawValue, isOn: saveProf(ab))
                            .toggleStyle(.button).controlSize(.small)
                    }
                }
            }

            Section("Vitesses") {
                ForEach($speedRows) { $row in
                    HStack {
                        TextField("clé (walk, fly, swim…)", text: $row.key)
                        TextField("valeur (30 ft)", text: $row.value)
                        Button(role: .destructive) {
                            speedRows.removeAll { $0.id == row.id }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
                Button { speedRows.append(SpeedRow(key: "", value: "")) } label: {
                    Label("Ajouter une vitesse", systemImage: "plus")
                }
                .controlSize(.small)
            }

            Section("Défenses") {
                MultiSelectMenu(title: "Résistances", options: dndDamageTypesAll,
                                values: $draft.damageResistances)
                MultiSelectMenu(title: "Immunités (dégâts)", options: dndDamageTypesAll,
                                values: $draft.damageImmunities)
                MultiSelectMenu(title: "Vulnérabilités", options: dndDamageTypesAll,
                                values: $draft.damageVulnerabilities)
                MultiSelectMenu(title: "Immunités (états)", options: dndConditionImmunities,
                                values: $draft.conditionImmunities)
            }

            Section("Traits") {
                ForEach($traitRows) { $row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Nom du trait", text: $row.name)
                            Button(role: .destructive) {
                                traitRows.removeAll { $0.id == row.id }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                        }
                        TextField("Description", text: $row.description, axis: .vertical)
                            .lineLimit(1...4)
                    }
                    .padding(.vertical, 2)
                }
                Button { traitRows.append(TraitRow(name: "", description: "")) } label: {
                    Label("Ajouter un trait", systemImage: "plus")
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Onglet attaques (structuré)

    private var attacksTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                if attackDrafts.isEmpty {
                    Text("Aucune attaque. Ajoutez-en une ci-dessous.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 20)
                }
                ForEach($attackDrafts) { $ad in
                    AttackCard(draft: $ad, monster: draft) {
                        attackDrafts.removeAll { $0.id == ad.id }
                    }
                }
                Button { attackDrafts.append(AttackDraft()) } label: {
                    Label("Ajouter une attaque", systemImage: "plus")
                }
                .padding(.top, 4)
            }
            .padding()
        }
    }

    // MARK: Onglet bouton Attaque (options)

    private var optionsTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Ce que propose le bouton Attaque du panneau de combat. « Multiattaque » joue une séquence d'un coup.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach($optionDrafts) { $opt in
                    OptionCard(draft: $opt, attackNames: attackDrafts.map { $0.name }) {
                        optionDrafts.removeAll { $0.id == opt.id }
                    }
                }
                Button { optionDrafts.append(OptionDraft()) } label: {
                    Label("Ajouter une option", systemImage: "plus")
                }
                .padding(.top, 4)
            }
            .padding()
        }
    }

    // MARK: Onglet sorts (spellcasting)

    private var spellcastingTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Le bouton « Sorts » du panneau de combat. Un sort « mécanique » doit porter le même nom qu'une attaque existante (onglet Attaques).")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let binding = Binding($spellcastingDraft) {
                    SpellcastingCard(draft: binding, attackNames: attackDrafts.map { $0.name }) {
                        spellcastingDraft = nil
                    }
                } else {
                    Text("Ce monstre ne lance pas de sorts.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 20)
                    Button { spellcastingDraft = SpellcastingDraft() } label: {
                        Label("Activer le spellcasting", systemImage: "sparkles")
                    }
                }
            }
            .padding()
        }
    }

    // MARK: Enregistrement

    private func save() {
        var m = draft

        var speed: [String: String] = [:]
        for r in speedRows {
            let key = r.key.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { speed[key] = r.value }
        }
        m.speed = speed

        let traits = traitRows
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { Trait(name: $0.name, description: $0.description) }
        m.traits = traits.isEmpty ? nil : traits

        m.attacks = attackDrafts.map { $0.toAttack() }
        m.attackOptions = optionDrafts.map { $0.toOption() }
        m.spellcasting = spellcastingDraft?.toBlock()

        if let msg = validationError(m) { error = msg; return }

        library.upsertCustom(m)
        dismiss()
    }

    private func validationError(_ m: Monster) -> String? {
        if m.attacks.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return "Une attaque n'a pas de nom."
        }
        let names = Set(m.attacks.map { $0.name })
        if names.count != m.attacks.count { return "Deux attaques portent le même nom." }
        for o in m.attackOptions {
            switch o.type {
            case .single:
                guard let a = o.attack, names.contains(a) else {
                    return "Une option « simple » ne pointe vers aucune attaque valide."
                }
            case .multiattack:
                for s in o.steps where !names.contains(s.attack) {
                    return "Multiattaque : l'attaque « \(s.attack) » n'existe pas."
                }
            }
        }
        if let sc = m.spellcasting {
            if sc.spells.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
                return "Un sort n'a pas de nom."
            }
            let spellNames = Set(sc.spells.map { $0.name })
            if spellNames.count != sc.spells.count { return "Deux sorts portent le même nom." }
            for sp in sc.spells where sp.mechanical {
                guard let an = sp.attackName, names.contains(an) else {
                    return "Le sort « \(sp.name) » est mécanique mais aucune attaque « \(sp.name) » n'existe (onglet Attaques)."
                }
            }
        }
        return nil
    }

    // MARK: Bindings & helpers du formulaire de stats



    private func saveProf(_ a: Ability) -> Binding<Bool> {
        Binding(
            get: { draft.saveProficiencies.contains(a) },
            set: { on in
                if on {
                    if !draft.saveProficiencies.contains(a) { draft.saveProficiencies.append(a) }
                } else {
                    draft.saveProficiencies.removeAll { $0 == a }
                }
            }
        )
    }

    /// Affiche le nombre de wounds (1 par défaut) et l'écrit dans le bloc (jamais < 1).
    private var woundsBinding: Binding<Int> {
        Binding(
            get: { max(1, draft.wounds ?? 1) },
            set: { draft.wounds = max(1, $0) }
        )
    }
}

// MARK: - Carte d'édition d'une attaque

private struct AttackCard: View {
    @Binding var draft: AttackDraft
    let monster: Monster
    let onDelete: () -> Void

    private var abilityMod: Int { monster.abilities.modifier(draft.ability) }
    private var toHit: Int { abilityMod + monster.proficiencyBonus }
    private var dc: Int { 8 + abilityMod + monster.proficiencyBonus }
    private var dmgBonus: Int { draft.addAbilityToDamage ? abilityMod : 0 }
    private var condSaveDC: Int { 8 + monster.abilities.modifier(draft.conditionDCAbility) + monster.proficiencyBonus }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Nom de l'attaque", text: $draft.name)
                    .font(.headline).textFieldStyle(.roundedBorder)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }

            HStack {
                Picker("Action", selection: $draft.actionType) {
                    ForEach(ActionEconomy.allCases, id: \.self) { Text(actionLabel($0)).tag($0) }
                }
                .frame(maxWidth: 190)
                Picker("Résolution", selection: $draft.kind) {
                    Text("Jet au toucher").tag(AttackKind.tohit)
                    Text("Jet de sauvegarde").tag(AttackKind.save)
                }
                .frame(maxWidth: 210)
            }

            // Préréglages + carac régissante
            HStack(spacing: 8) {
                Text("Type :").foregroundStyle(.secondary)
                Button("Mêlée")    { draft.ability = .FOR; draft.addAbilityToDamage = true }
                Button("Distance") { draft.ability = .DEX; draft.addAbilityToDamage = true }
                Button("Sort")     { draft.ability = .INT; draft.addAbilityToDamage = false }
                Picker("Carac", selection: $draft.ability) {
                    ForEach(Ability.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().frame(maxWidth: 90)
            }
            .controlSize(.small)

            // Valeur dérivée (toucher ou DC)
            if draft.kind == .tohit {
                Text("Toucher dérivé : \(signedString(toHit))  (\(draft.ability.rawValue) \(signedString(abilityMod)) + maîtrise \(signedString(monster.proficiencyBonus)))")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Text("DC dérivé : \(dc)").font(.callout).foregroundStyle(.secondary)
                    Text("Save cible :").font(.caption).foregroundStyle(.secondary)
                    Picker("Save cible", selection: $draft.saveAbility) {
                        ForEach(Ability.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().frame(maxWidth: 90).controlSize(.small)
                    Toggle("Demi si réussite", isOn: $draft.halfOnSave).controlSize(.small)
                }
            }

            // Portée / zone / recharge
            HStack {
                if draft.kind == .tohit {
                    TextField("Allonge (5 ft)", text: $draft.reach)
                    TextField("Distance (80/320 ft)", text: $draft.range)
                } else {
                    TextField("Zone (cône de 30 ft)", text: $draft.area)
                }
                TextField("Recharge (5-6)", text: $draft.recharge).frame(maxWidth: 130)
            }
            .textFieldStyle(.roundedBorder)

            // Dégâts
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Dégâts").font(.subheadline.weight(.semibold))
                    Spacer()
                    Toggle("Ajouter le mod de carac (\(signedString(abilityMod)))", isOn: $draft.addAbilityToDamage)
                        .controlSize(.small)
                }
                ForEach($draft.damage) { $row in
                    HStack {
                        TextField("dés (2d6)", text: $row.dice)
                            .frame(maxWidth: 90).textFieldStyle(.roundedBorder)
                        Picker("type", selection: $row.type) {
                            Text("—").tag("")
                            ForEach(dndDamageTypes, id: \.self) { Text($0).tag($0) }
                            if !row.type.isEmpty && !dndDamageTypes.contains(row.type) {
                                Text(row.type).tag(row.type)
                            }
                        }
                        .labelsHidden().frame(maxWidth: 150)
                        if draft.damage.first?.id == row.id && dmgBonus != 0 {
                            Text(signedString(dmgBonus)).font(.caption).foregroundStyle(.secondary)
                        }
                        Button(role: .destructive) {
                            draft.damage.removeAll { $0.id == row.id }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
                Button { draft.damage.append(DamageRow(dice: "1d6", type: "bludgeoning")) } label: {
                    Label("Ajouter une composante", systemImage: "plus")
                }
                .controlSize(.small)
            }

            // Condition + jet de sauvegarde de la condition + effet
            HStack {
                Text("Condition infligée :").foregroundStyle(.secondary)
                Picker("Condition", selection: $draft.condition) {
                    Text("Aucune").tag("")
                    ForEach(dndConditions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(maxWidth: 200)
                Spacer()
            }
            .font(.callout)

            if !draft.condition.isEmpty {
                if draft.kind == .tohit {
                    Toggle("Jet de sauvegarde contre la condition", isOn: $draft.conditionSaveEnabled)
                        .controlSize(.small)
                    if draft.conditionSaveEnabled {
                        HStack(spacing: 8) {
                            Text("DC (carac) :").foregroundStyle(.secondary)
                            Picker("DC", selection: $draft.conditionDCAbility) {
                                ForEach(Ability.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden().frame(maxWidth: 80)
                            Text("→ DD \(condSaveDC)").foregroundStyle(.secondary)
                            Text("· Jet de la cible :").foregroundStyle(.secondary)
                            Picker("Jet", selection: $draft.conditionSaveAbility) {
                                ForEach(Ability.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden().frame(maxWidth: 80)
                        }
                        .font(.callout).controlSize(.small)
                    }
                } else {
                    Text("La condition est annulée par la sauvegarde de l'attaque ci-dessus (DD \(dc), jet \(draft.saveAbility.rawValue)).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            TextField("Effet (durée, save répété, DC d'évasion…)", text: $draft.effect, axis: .vertical)
                .lineLimit(1...3).textFieldStyle(.roundedBorder)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }
}

// MARK: - Carte d'édition d'une option d'attaque

private struct OptionCard: View {
    @Binding var draft: OptionDraft
    let attackNames: [String]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Type", selection: $draft.type) {
                    Text("Attaque simple").tag(AttackOptionType.single)
                    Text("Multiattaque").tag(AttackOptionType.multiattack)
                }
                .frame(maxWidth: 220)
                Spacer()
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }

            if draft.type == .single {
                Picker("Attaque", selection: $draft.attack) {
                    Text("—").tag("")
                    ForEach(attackNames, id: \.self) { Text($0).tag($0) }
                    if !draft.attack.isEmpty && !attackNames.contains(draft.attack) {
                        Text(draft.attack).tag(draft.attack)
                    }
                }
            } else {
                TextField("Description (ex. Deux griffes ardentes)", text: $draft.description)
                    .textFieldStyle(.roundedBorder)
                ForEach($draft.sequence) { $step in
                    HStack {
                        Picker("étape", selection: $step.attack) {
                            Text("—").tag("")
                            ForEach(attackNames, id: \.self) { Text($0).tag($0) }
                            if !step.attack.isEmpty && !attackNames.contains(step.attack) {
                                Text(step.attack).tag(step.attack)
                            }
                        }
                        .labelsHidden().frame(maxWidth: 220)
                        Stepper("× \(step.count)", value: $step.count, in: 1...10).fixedSize()
                        Button(role: .destructive) {
                            draft.sequence.removeAll { $0.id == step.id }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
                Button { draft.sequence.append(StepRow(attack: attackNames.first ?? "", count: 1)) } label: {
                    Label("Ajouter une étape", systemImage: "plus")
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }
}

// MARK: - Carte d'édition du spellcasting

private struct SpellcastingCard: View {
    @Binding var draft: SpellcastingDraft
    let attackNames: [String]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Spellcasting").font(.headline)
                Spacer()
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Retirer le spellcasting de ce monstre")
            }

            HStack(spacing: 10) {
                Text("Carac de lancement :").foregroundStyle(.secondary)
                Picker("Carac", selection: $draft.ability) {
                    ForEach(Ability.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().frame(maxWidth: 90)
                Text("DD :").foregroundStyle(.secondary)
                TextField("DD", value: $draft.dc, format: .number)
                    .frame(width: 50).textFieldStyle(.roundedBorder)
                Toggle("Bonus au toucher (sorts)", isOn: $draft.attackBonusEnabled)
                if draft.attackBonusEnabled {
                    TextField("+N", value: $draft.attackBonus, format: .number)
                        .frame(width: 50).textFieldStyle(.roundedBorder)
                }
            }
            .controlSize(.small)

            Text("Les sorts « mécaniques » réutilisent une attaque du même nom (dégâts/sauvegarde, déjà créée dans l'onglet Attaques) ; ils sont résolus et journalisés. Les sorts non mécaniques ne suivent qu'un compteur d'usage.")
                .font(.caption).foregroundStyle(.secondary)

            ForEach($draft.spells) { $sp in
                spellRow($sp)
            }
            Button { draft.spells.append(SpellDraft()) } label: {
                Label("Ajouter un sort", systemImage: "plus")
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }

    @ViewBuilder private func spellRow(_ sp: Binding<SpellDraft>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Nom du sort", text: sp.name).textFieldStyle(.roundedBorder)
                Toggle("À volonté", isOn: sp.unlimited).controlSize(.small)
                if !sp.wrappedValue.unlimited {
                    Stepper("\(sp.wrappedValue.usesPerDay)/jour", value: sp.usesPerDay, in: 1...10)
                        .fixedSize()
                }
                Button(role: .destructive) {
                    draft.spells.removeAll { $0.id == sp.wrappedValue.id }
                } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
            }
            HStack(spacing: 8) {
                Toggle("Mécanique (lié à une attaque du même nom)", isOn: sp.mechanical)
                    .controlSize(.small)
                if sp.wrappedValue.mechanical {
                    let name = sp.wrappedValue.name.trimmingCharacters(in: .whitespaces)
                    if name.isEmpty {
                        Text("→ nommez le sort").font(.caption).foregroundStyle(.orange)
                    } else if attackNames.contains(name) {
                        Text("→ attaque « \(name) » trouvée").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("→ aucune attaque « \(name) » : créez-la dans l'onglet Attaques")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Modèles éditables (drafts)

private struct TraitRow: Identifiable {
    let id = UUID()
    var name: String
    var description: String
}

private struct SpeedRow: Identifiable {
    let id = UUID()
    var key: String
    var value: String
}

private struct DamageRow: Identifiable {
    let id = UUID()
    var dice: String
    var type: String
}

private struct StepRow: Identifiable {
    let id = UUID()
    var attack: String
    var count: Int
}

private struct AttackDraft: Identifiable {
    let id = UUID()
    var name: String
    var kind: AttackKind
    var ability: Ability
    var addAbilityToDamage: Bool
    var actionType: ActionEconomy
    var saveAbility: Ability       // sauvegarde du défenseur (si kind == save)
    var halfOnSave: Bool
    var area: String
    var reach: String
    var range: String
    var recharge: String
    var condition: String          // "" = aucune
    var effect: String
    var conditionSaveEnabled: Bool          // jet de sauvegarde contre la condition (toucher)
    var conditionDCAbility: Ability         // carac de l'attaquant (DC)
    var conditionSaveAbility: Ability       // carac du jet de la cible
    var damage: [DamageRow]

    /// Nouvelle attaque vierge.
    init() {
        name = "Nouvelle attaque"
        kind = .tohit
        ability = .FOR
        addAbilityToDamage = true
        actionType = .action
        saveAbility = .DEX
        halfOnSave = false
        area = ""; reach = "5 ft"; range = ""; recharge = ""
        condition = ""; effect = ""
        conditionSaveEnabled = false
        conditionDCAbility = .CON
        conditionSaveAbility = .CON
        damage = [DamageRow(dice: "1d6", type: "bludgeoning")]
    }

    /// Depuis une attaque existante. Si l'attaque est en ancien format (sans `ability`),
    /// on infère la carac régissante et on retire le modificateur cuit dans les dés.
    init(from a: Attack, monster: Monster) {
        name = a.name
        kind = a.kind
        actionType = a.actionType ?? .action
        saveAbility = a.save?.ability ?? .DEX
        halfOnSave = a.halfOnSave ?? false
        area = a.area ?? ""
        reach = a.reach ?? ""
        range = a.range ?? ""
        recharge = a.recharge ?? ""
        condition = a.condition ?? ""
        effect = a.effect ?? ""
        if let cs = a.conditionSave {
            conditionSaveEnabled = true
            conditionDCAbility = cs.dcAbility
            conditionSaveAbility = cs.saveAbility
        } else {
            conditionSaveEnabled = false
            conditionDCAbility = .CON
            conditionSaveAbility = .CON
        }

        if let ab = a.ability {
            ability = ab
            addAbilityToDamage = a.addAbilityToDamage ?? false
            damage = a.damageComponents.map { DamageRow(dice: $0.dice, type: $0.type) }
        } else {
            ability = AttackDraft.inferAbility(a, monster: monster)
            var comps = a.damageComponents
            if a.kind == .tohit, !comps.isEmpty {
                let z = DiceFormula.parse(comps[0].dice)?.modifier ?? 0
                addAbilityToDamage = (z != 0)
                comps[0].dice = AttackDraft.stripModifier(comps[0].dice)
            } else {
                addAbilityToDamage = false
                comps = comps.map { DamageComponent(dice: AttackDraft.stripModifier($0.dice), type: $0.type) }
            }
            damage = comps.map { DamageRow(dice: $0.dice, type: $0.type) }
        }
    }

    func toAttack() -> Attack {
        let comps = damage
            .map { DamageComponent(dice: $0.dice.replacingOccurrences(of: " ", with: ""),
                                   type: $0.type.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.dice.isEmpty }
        return Attack(
            name: name,
            kind: kind,
            ability: ability,
            addAbilityToDamage: addAbilityToDamage ? true : nil,
            actionType: actionType,
            toHit: nil,
            reach: (kind == .tohit && !reach.isEmpty) ? reach : nil,
            range: (kind == .tohit && !range.isEmpty) ? range : nil,
            save: kind == .save ? SaveSpec(ability: saveAbility, dc: nil) : nil,
            area: (kind == .save && !area.isEmpty) ? area : nil,
            damage: comps.isEmpty ? nil : comps,
            halfOnSave: (kind == .save && halfOnSave) ? true : nil,
            condition: condition.isEmpty ? nil : condition,
            conditionSave: (kind == .tohit && !condition.isEmpty && conditionSaveEnabled)
                ? ConditionSave(dcAbility: conditionDCAbility, saveAbility: conditionSaveAbility) : nil,
            effect: effect.isEmpty ? nil : effect,
            recharge: recharge.isEmpty ? nil : recharge
        )
    }

    /// Retire un éventuel modificateur cuit ("2d6+4" -> "2d6") ; conserve une valeur fixe.
    static func stripModifier(_ s: String) -> String {
        guard let f = DiceFormula.parse(s) else { return s }
        if f.count == 0 { return String(f.modifier) }
        return "\(f.count)d\(f.sides)"
    }

    /// Infère la carac qui reproduit la valeur stockée (toHit ou DC), selon la formule 5e.
    static func inferAbility(_ a: Attack, monster m: Monster) -> Ability {
        let pb = m.proficiencyBonus
        if a.kind == .tohit {
            let target = a.toHit ?? 0
            var order: [Ability] = [.FOR, .DEX, .INT, .SAG, .CHA]
            if a.range != nil && a.reach == nil { order = [.DEX, .FOR, .INT, .SAG, .CHA] }
            for ab in order where m.abilities.modifier(ab) + pb == target { return ab }
            return .FOR
        } else {
            let target = a.save?.dc ?? 0
            for ab in [Ability.CON, .INT, .SAG, .CHA, .DEX, .FOR]
            where 8 + m.abilities.modifier(ab) + pb == target { return ab }
            return .CON
        }
    }
}

private struct OptionDraft: Identifiable {
    let id = UUID()
    var type: AttackOptionType
    var attack: String          // pour single
    var description: String     // pour multiattack
    var sequence: [StepRow]     // pour multiattack

    init() {
        type = .single
        attack = ""
        description = ""
        sequence = []
    }

    init(from o: AttackOption) {
        type = o.type
        attack = o.attack ?? ""
        description = o.description ?? ""
        sequence = o.steps.map { StepRow(attack: $0.attack, count: $0.count) }
    }

    func toOption() -> AttackOption {
        switch type {
        case .single:
            return AttackOption(type: .single,
                                attack: attack.isEmpty ? nil : attack,
                                description: nil, sequence: nil)
        case .multiattack:
            let steps = sequence
                .filter { !$0.attack.isEmpty }
                .map { MultiattackEntry(attack: $0.attack, count: max(1, $0.count)) }
            return AttackOption(type: .multiattack, attack: nil,
                                description: description.isEmpty ? nil : description,
                                sequence: steps)
        }
    }
}

// MARK: - Modèle éditable du spellcasting

/// Un sort de la liste. `mechanical` lie le sort à une attaque existante (même nom) :
/// dégâts/sauvegarde résolus via le pipeline normal et journalisés ; sinon, compteur seul.
private struct SpellDraft: Identifiable {
    let id = UUID()
    var name: String
    var unlimited: Bool      // à volonté
    var usesPerDay: Int       // ignoré si unlimited
    var mechanical: Bool      // référence une attaque du même nom

    init() {
        name = ""
        unlimited = true
        usesPerDay = 1
        mechanical = false
    }

    init(from e: SpellEntry) {
        name = e.name
        if let n = e.usesPerDay { unlimited = false; usesPerDay = n }
        else { unlimited = true; usesPerDay = 1 }
        mechanical = e.mechanical
    }

    func toEntry() -> SpellEntry {
        SpellEntry(name: name,
                  usesPerDay: unlimited ? nil : max(1, usesPerDay),
                  mechanical: mechanical,
                  attackName: mechanical ? name : nil)   // même nom (option A)
    }
}

/// Bloc de spellcasting du monstre. `nil` côté éditeur (pas de draft instancié) = monstre non-lanceur.
private struct SpellcastingDraft {
    var ability: Ability
    var dc: Int
    var attackBonusEnabled: Bool
    var attackBonus: Int
    var spells: [SpellDraft]

    init() {
        ability = .INT
        dc = 13
        attackBonusEnabled = false
        attackBonus = 5
        spells = []
    }

    init(from b: SpellcastingBlock) {
        ability = b.ability
        dc = b.dc
        if let bonus = b.attackBonus { attackBonusEnabled = true; attackBonus = bonus }
        else { attackBonusEnabled = false; attackBonus = 5 }
        spells = b.spells.map { SpellDraft(from: $0) }
    }

    func toBlock() -> SpellcastingBlock {
        SpellcastingBlock(ability: ability, dc: dc,
                          attackBonus: attackBonusEnabled ? attackBonus : nil,
                          spells: spells.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                              .map { $0.toEntry() })
    }
}

private struct AbilityField: View {
    let label: String
    @Binding var value: Int
    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("", value: $value, format: .number)
                .frame(width: 52)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
        }
    }
}
