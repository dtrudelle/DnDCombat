import SwiftUI

// MARK: - Groupe de monstres

struct GroupPanel: View {
    @Bindable var group: MonsterGroup
    @Environment(Encounter.self) private var enc

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(group.displayName).font(.headline)
                Spacer()
                Text("init \(group.initiative)").font(.caption).foregroundStyle(.secondary)
                Button(role: .destructive) { enc.removeGroup(group) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Retirer ce groupe de la rencontre")
            }
            ForEach(group.instances) { inst in
                InstancePanel(instance: inst, group: group)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }
}

// MARK: - Instance (une créature)

struct InstancePanel: View {
    @Bindable var instance: MonsterInstance
    let group: MonsterGroup
    @Environment(Encounter.self) private var enc

    @State private var expanded = true
    @State private var amount = 1
    @State private var showingSpells = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if expanded { detail }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
        .opacity(instance.isDefeated ? 0.5 : 1)
    }

    // En-tête : repli + nom + contrôles PV et Wounds (toujours visibles)
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.borderless)
                Text(instance.name).font(.subheadline.weight(.semibold))
                if group.instances.count > 1 {
                    Button(role: .destructive) { enc.removeInstance(instance, from: group) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Retirer cette créature")
                }
                Spacer()
                hpControls
            }
            HStack(spacing: 8) {
                acControls
                Spacer()
                woundControls
            }
        }
    }

    // CA sous le nom : grand caractère (comme les PV) ; la CA de base reste
    // visible quand on l'ajuste (ex. CA 17 → CA 19).
    private var acControls: some View {
        HStack(spacing: 6) {
            Image(systemName: "shield.fill").foregroundStyle(.secondary)
            if instance.acAdjustment != 0 {
                Text("CA \(instance.block.ac)")
                    .font(.title3).monospacedDigit().foregroundStyle(.secondary)
                Text("→").font(.title3).foregroundStyle(.secondary)
                Text("CA \(instance.effectiveAC)")
                    .font(.title.weight(.bold)).monospacedDigit()
            } else {
                Text("CA \(instance.block.ac)")
                    .font(.title.weight(.bold)).monospacedDigit()
            }
            Stepper("", value: $instance.acAdjustment, in: -20...20).labelsHidden()
        }
    }

    private var hpControls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Text("\(instance.currentHP)")
                    .font(.title.weight(.bold)).monospacedDigit()
                Text("/ \(instance.maxHP)")
                    .font(.title3).monospacedDigit().foregroundStyle(.secondary)
            }
            TextField("", value: $amount, format: .number)
                .frame(width: 56)
                .font(.title3)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .onSubmit { instance.applyDamage(amount) }
            Button { instance.applyDamage(amount) } label: { Text("−").font(.title2).frame(width: 28) }
            Button { instance.heal(amount) } label: { Text("+").font(.title2).frame(width: 28) }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    // Wounds : même champ quantité que les PV ; boutons −/+ identiques.
    private var woundControls: some View {
        HStack(spacing: 8) {
            Text("Wounds").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                Text("\(instance.currentWounds)")
                    .font(.title2.weight(.bold)).monospacedDigit()
                Text("/ \(instance.maxWounds)")
                    .font(.title3).monospacedDigit().foregroundStyle(.secondary)
            }
            Button { instance.applyWound(amount) } label: { Text("−").font(.title3).frame(width: 28) }
            Button { instance.healWound(amount) } label: { Text("+").font(.title3).frame(width: 28) }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    // Détail déplié
    private var detail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let walk = instance.block.speed["walk"] {
                Text("Vitesse \(walk)").foregroundStyle(.secondary)
            }

            savesRow
            attackControl

            if !resistanceLines(instance.block).isEmpty || !(instance.block.traits ?? []).isEmpty {
                DisclosureGroup("Traits · résistances · immunités") { reference }
                    .font(.callout)
            }
        }
    }

    private var savesRow: some View {
        HStack(spacing: 4) {
            ForEach(Ability.allCases, id: \.self) { ab in
                Button(ab.rawValue) { enc.rollSave(ab, on: instance) }
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder private var attackControl: some View {
        let options = instance.block.attackOptions
        let casts = instance.block.spellcasting != nil
        if options.isEmpty && !casts {
            Text("Aucune attaque").font(.caption).foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                        let cooling = isOnCooldown(opt)
                        Button(optionLabel(opt)) { enc.performAttack(on: instance, optionIndex: i) }
                            .disabled(cooling)
                            .tint(cooling ? .gray : .accentColor)
                    }
                    if casts {
                        Button { showingSpells = true } label: {
                            Label("Sorts", systemImage: "sparkles")
                        }
                        .tint(.purple)
                        .popover(isPresented: $showingSpells, arrowEdge: .bottom) {
                            SpellPopover(instance: instance)
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Vrai si l'option est une attaque à recharge actuellement dépensée (bouton grisé).
    private func isOnCooldown(_ o: AttackOption) -> Bool {
        guard o.type == .single, let name = o.attack,
              instance.block.attack(named: name)?.recharge != nil else { return false }
        return instance.spentRecharges.contains(name)
    }

    private func optionLabel(_ o: AttackOption) -> String {
        switch o.type {
        case .multiattack:
            let steps = o.steps
            let distinct = Set(steps.map { $0.attack })
            let multiCount = instance.block.attackOptions.filter { $0.type == .multiattack }.count
            // Plusieurs volées au choix (famille « X ou Y ») : on nomme l'arme pour distinguer
            // les boutons. Volée unique : libellé générique « Multiattaque ».
            if multiCount > 1, distinct.count == 1, let s = steps.first {
                return "\(s.count)× \(s.attack)"
            }
            return "Multiattaque"
        case .single:
            var label = o.attack ?? "Attaque"
            if let name = o.attack, let atk = instance.block.attack(named: name) {
                if atk.actionType == .bonus { label += " (BA)" }
                if let r = atk.rechargeLabel { label += " \(r)" }
            }
            return label
        }
    }

    private var reference: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(resistanceLines(instance.block), id: \.label) { line in
                (Text(line.label + " : ").bold() + Text(line.value))
                    .font(.caption)
            }
            ForEach(instance.block.traits ?? [], id: \.name) { t in
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.name).font(.caption.weight(.semibold))
                    Text(t.description).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Popover de sorts

/// Liste les sorts disponibles d'une instance avec leur compteur d'utilisations.
/// Un sort épuisé est grisé (désactivé). Cliquer un sort le lance via `Encounter.castSpell`,
/// ce qui met à jour le compteur en direct et journalise les sorts mécaniques.
struct SpellPopover: View {
    @Bindable var instance: MonsterInstance
    @Environment(Encounter.self) private var enc

    var body: some View {
        let sc = instance.block.spellcasting
        VStack(alignment: .leading, spacing: 8) {
            if let sc {
                Text(headerText(sc)).font(.headline)
                Divider()
                ForEach(sc.spells, id: \.name) { sp in
                    spellRow(sp)
                }
            } else {
                Text("Aucun sort").foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(minWidth: 260)
    }

    private func headerText(_ sc: SpellcastingBlock) -> String {
        var s = "Sorts — DD \(sc.dc) \(sc.ability.rawValue)"
        if let b = sc.attackBonus { s += ", +\(b) att." }
        return s
    }

    @ViewBuilder private func spellRow(_ sp: SpellEntry) -> some View {
        let available = instance.canCast(sp.name)
        Button { enc.castSpell(named: sp.name, on: instance) } label: {
            HStack(spacing: 8) {
                Text(sp.name)
                if !sp.mechanical {
                    Image(systemName: "wand.and.stars")
                        .font(.caption2).foregroundStyle(.secondary)
                        .help("Sort utilitaire : seul le compteur est suivi")
                }
                Spacer()
                Text(usesLabel(sp))
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.4)
    }

    private func usesLabel(_ sp: SpellEntry) -> String {
        guard let total = sp.usesPerDay else { return "à volonté" }
        let left = instance.remainingUses(of: sp.name) ?? total
        return "\(left)/\(total)"
    }
}
