//
//  PlanScreens.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Pantallas del plan semanal: vista por días con aviso de semana caducada y editor de una comida del plan (cambiar comida, raciones y bloqueo).
//

import SwiftUI

// MARK: - Plan semanal

/// Pestaña "Plan": un bloque por día con sus comidas, calorías y macronutrientes frente al objetivo, y acciones para editar cada comida.
struct PlanTabView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(Navigator.self) private var navigator

    var body: some View {
        NavigationStack {
            ScrollView {
                if let plan = viewModel.plan {
                    LazyVStack(spacing: 16) {
                        if !plan.isCurrent() { staleBanner }
                        shoppingShortcut
                        ForEach(plan.days()) { day in
                            dayCard(day)
                        }
                        Text("Pulsa ••• en una comida para cambiarla, ajustar las raciones o bloquearla al regenerar el menú.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                } else {
                    EmptyCard(
                        systemImage: "calendar.badge.plus",
                        title: "Sin menú",
                        message: "Genera un menú semanal desde la pestaña Comidas."
                    )
                }
            }
            .background(AppBackground())
            .navigationTitle("Plan semanal")
            .toolbar {
                if viewModel.plan != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button { viewModel.generatePlan() } label: {
                            Label("Regenerar menú", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                }
            }
        }
    }

    /// Aviso de que el menú guardado pertenece a otra semana.
    private var staleBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Este menú es de otra semana", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Genera uno nuevo para esta semana. Las comidas bloqueadas solo se conservan dentro de la misma semana.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button { viewModel.generatePlan() } label: {
                Text("Generar menú de esta semana").font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .card()
    }

    /// Acceso directo a la lista de la compra.
    private var shoppingShortcut: some View {
        Button { navigator.selectedTab = .shopping } label: {
            HStack(spacing: 14) {
                IconBadge(systemName: "cart.fill", color: Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lista de la compra").font(.headline)
                    Text("Ingredientes de toda la semana").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
    }

    /// Tarjeta de un día. Las calorías se marcan en verde si están dentro de la tolerancia del objetivo y en naranja si no.
    /// - Parameter day: Día del plan.
    /// - Returns: La tarjeta del día.
    private func dayCard(_ day: PlanDay) -> some View {
        let total = viewModel.calories(on: day)
        let onTarget = abs(total - viewModel.goal) <= MenuGenerator.defaultTolerance
        let macros = viewModel.nutrition(on: day)
        let color: Color = onTarget ? Theme.accent : .orange

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(day.date.formatted(.dateTime.weekday(.wide)).capitalized).font(.title3.weight(.bold))
                    Text(day.date.formatted(.dateTime.day().month(.wide))).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(total) kcal")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(color.opacity(0.15), in: Capsule())
            }
            if macros != Nutrition() {
                Text("P \(format(macros.protein)) g · C \(format(macros.carbohydrates)) g · G \(format(macros.fat)) g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(day.meals.enumerated()), id: \.element.id) { index, planned in
                    row(planned)
                    if index < day.meals.count - 1 { Divider().padding(.leading, 48) }
                }
            }
        }
        .card()
    }

    /// Fila de una comida del plan con acceso al detalle y menú de acciones.
    /// - Parameter planned: Comida planificada.
    /// - Returns: La fila, o una vista vacía si la comida ya no existe.
    @ViewBuilder
    private func row(_ planned: PlannedMeal) -> some View {
        if let meal = viewModel.meal(withID: planned.mealID) {
            HStack(spacing: 4) {
                NavigationLink {
                    MealDetailView(mealID: meal.id)
                } label: {
                    HStack(spacing: 12) {
                        IconBadge(systemName: planned.slot.icon, color: planned.slot.color, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(planned.slot.title).font(.caption).foregroundStyle(.secondary)
                                if planned.isLocked {
                                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.orange)
                                }
                            }
                            Text(meal.name)
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.leading)
                            let chosen = meal.chosenOptions(for: planned.choices)
                            if !chosen.isEmpty {
                                Text(chosen.map(\.name).joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(Theme.accent)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(viewModel.calories(of: planned)) kcal").font(.caption).foregroundStyle(.secondary)
                            if planned.servings != 1 {
                                Text("\(format(planned.servings)) raciones").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Button { navigator.plannedMealEditor = PlannedMealRef(id: planned.id) } label: {
                        Label("Cambiar comida o raciones", systemImage: "slider.horizontal.3")
                    }
                    Button { viewModel.toggleLock(planned: planned.id) } label: {
                        Label(planned.isLocked ? "Desbloquear" : "Mantener al regenerar", systemImage: planned.isLocked ? "lock.open" : "lock")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 44)
                }
                .accessibilityLabel("Opciones de \(meal.name)")
            }
        }
    }

    /// Formatea un número con un máximo de un decimal.
    /// - Parameter value: Número a formatear.
    /// - Returns: El número como texto.
    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

// MARK: - Editor de una comida del plan

/// Hoja para cambiar la comida de una franja del plan, ajustar las raciones y bloquearla.
struct PlannedMealEditorView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    let plannedID: String

    var body: some View {
        NavigationStack {
            if let planned = viewModel.plannedMeal(withID: plannedID), let meal = viewModel.meal(withID: planned.mealID) {
                Form {
                    Section("Comida de \(planned.slot.title.lowercased())") {
                        NavigationLink {
                            SearchableSelectionList(
                                items: candidates(for: planned.slot),
                                title: planned.slot.title,
                                prompt: "Buscar comida",
                                searchText: \.name,
                                isSelected: { $0.id == planned.mealID },
                                onSelect: { viewModel.replaceMeal(planned: plannedID, with: $0.id) }
                            ) { candidate in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.name)
                                    Text("\(candidate.caloriesPerServing) kcal/ración").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } label: {
                            LabeledContent("Comida", value: meal.name)
                        }
                    }
                    Section {
                        Stepper(
                            "\(planned.servings.formatted(.number.precision(.fractionLength(0...1)))) \(planned.servings == 1 ? "ración" : "raciones")",
                            value: Binding(
                                get: { planned.servings },
                                set: { viewModel.setServings($0, forPlanned: plannedID) }
                            ),
                            in: 0.5...6,
                            step: 0.5
                        )
                        LabeledContent("Calorías", value: "\(viewModel.calories(of: planned)) kcal")
                    } header: {
                        Text("Raciones")
                    } footer: {
                        Text("La lista de la compra se ajusta a las raciones que indiques.")
                    }
                    ForEach(meal.optionGroups) { group in
                        Section {
                            Picker(group.name, selection: Binding<UUID?>(
                                get: { planned.choices.first { $0.groupID == group.id }?.optionID },
                                set: { optionID in
                                    if let optionID {
                                        viewModel.setChoice(planned: plannedID, group: group.id, option: optionID)
                                    }
                                }
                            )) {
                                ForEach(group.options) { option in
                                    Text("\(option.name) · \(option.calories) kcal").tag(UUID?.some(option.id))
                                }
                            }
                        } header: {
                            Text(group.name)
                        } footer: {
                            Text("Cambia la opción de este día; se actualizan las calorías y la lista de la compra.")
                        }
                    }
                    Section {
                        Toggle("Mantener al regenerar el menú", isOn: Binding(
                            get: { planned.isLocked },
                            set: { _ in viewModel.toggleLock(planned: plannedID) }
                        ))
                    }
                }
                .navigationTitle("Editar comida")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Listo") { dismiss() }
                    }
                }
            } else {
                ContentUnavailableView("Comida no disponible", systemImage: "questionmark.folder")
            }
        }
    }

    /// Comidas que se pueden usar en una franja, ordenadas por nombre.
    /// - Parameter slot: Franja del día.
    /// - Returns: Las comidas compatibles con la franja.
    private func candidates(for slot: MealSlot) -> [Meal] {
        viewModel.meals
            .filter { $0.mealSlots.contains(slot) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
