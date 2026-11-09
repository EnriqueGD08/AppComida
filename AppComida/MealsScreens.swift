//
//  MealsScreens.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Pantallas de comidas: listado por franjas con búsqueda y favoritas, tarjeta del objetivo diario y detalle de una comida.
//

import SwiftUI

// MARK: - Listado

/// Pestaña "Comidas": tarjeta del objetivo diario, botón para generar el menú y listado de comidas por franja con búsqueda y filtro de favoritas.
struct MealsTabView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(Navigator.self) private var navigator

    @State private var query = ""
    @State private var onlyFavorites = false

    private var isFiltering: Bool { !query.searchKey.isEmpty || onlyFavorites }

    /// Comidas que cumplen la búsqueda y el filtro de favoritas, con las favoritas primero.
    private var visibleMeals: [Meal] {
        let key = query.searchKey
        return viewModel.meals
            .filter { (key.isEmpty || $0.name.searchKey.contains(key)) && (!onlyFavorites || $0.isFavorite) }
            .sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 28) {
                    if isFiltering {
                        if visibleMeals.isEmpty { ContentUnavailableView.search(text: query) }
                    } else {
                        goalCard
                    }
                    ForEach(MealSlot.allCases) { slot in
                        slotSection(slot)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(AppBackground())
            .navigationTitle("Mis comidas")
            .searchable(text: $query, prompt: "Buscar comida")
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    Toggle(isOn: $onlyFavorites) {
                        Label("Solo favoritas", systemImage: onlyFavorites ? "star.fill" : "star")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { navigator.mealEditor = .new } label: {
                        Label("Nueva comida", systemImage: "plus")
                    }
                }
            }
        }
    }

    /// Tarjeta con el objetivo calórico (editable con − / +) y el botón de generar el menú semanal.
    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Objetivo diario", systemImage: "flame.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(viewModel.goal)")
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("kcal").font(.title3.weight(.medium)).opacity(0.85)
                    }
                    .foregroundStyle(.white)
                }
                Spacer()
                HStack(spacing: 10) {
                    stepButton("minus", label: "Bajar objetivo") { viewModel.setGoal(viewModel.goal - 50) }
                    stepButton("plus", label: "Subir objetivo") { viewModel.setGoal(viewModel.goal + 50) }
                }
            }
            Button {
                if viewModel.generatePlan() { navigator.selectedTab = .plan }
            } label: {
                Label("Generar menú semanal", systemImage: "wand.and.stars")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Theme.accent.opacity(0.35), radius: 16, y: 8)
        .animation(.snappy, value: viewModel.goal)
    }

    /// Botón circular para subir o bajar el objetivo calórico.
    /// - Parameters:
    ///   - systemName: Nombre del símbolo SF.
    ///   - label: Texto de accesibilidad.
    ///   - action: Acción al pulsarlo.
    /// - Returns: El botón.
    private func stepButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.22), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Sección con las comidas de una franja; se omite si hay filtro y ninguna coincide.
    /// - Parameter slot: Franja a mostrar.
    /// - Returns: La sección completa.
    @ViewBuilder
    private func slotSection(_ slot: MealSlot) -> some View {
        let slotMeals = visibleMeals.filter { $0.mealSlots.contains(slot) }
        if !(isFiltering && slotMeals.isEmpty) {
            VStack(spacing: 12) {
                SectionTitle(title: slot.title, systemImage: slot.icon, color: slot.color, trailing: "\(slotMeals.count)")
                if slotMeals.isEmpty {
                    Text("Aún no hay comidas para esta franja.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .card()
                }
                ForEach(slotMeals) { meal in
                    NavigationLink {
                        MealDetailView(mealID: meal.id)
                    } label: {
                        MealRow(meal: meal, slot: slot)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { navigator.mealEditor = .edit(meal) } label: { Label("Editar", systemImage: "pencil") }
                        Button { viewModel.toggleFavorite(meal.id) } label: {
                            Label(meal.isFavorite ? "Quitar de favoritas" : "Marcar como favorita", systemImage: meal.isFavorite ? "star.slash" : "star")
                        }
                        Button { viewModel.duplicateMeal(meal.id) } label: { Label("Duplicar", systemImage: "plus.square.on.square") }
                        Button(role: .destructive) { navigator.mealToDelete = meal } label: { Label("Eliminar", systemImage: "trash") }
                    }
                }
            }
        }
    }
}

/// Fila de una comida: icono de franja, nombre, ingredientes, raciones y calorías por ración.
private struct MealRow: View {
    let meal: Meal
    let slot: MealSlot

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(systemName: slot.icon, color: slot.color)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(meal.name).font(.headline).multilineTextAlignment(.leading)
                    if meal.isFavorite {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                    }
                }
                Text("\(meal.ingredients.count) ingredientes · \(meal.servings) \(meal.servings == 1 ? "ración" : "raciones")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(meal.caloriesPerServing)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text("kcal").font(.caption2).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card(padding: 14)
    }
}

// MARK: - Detalle

/// Detalle de una comida: cabecera, macronutrientes por ración, ingredientes y pasos de preparación.
struct MealDetailView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(Navigator.self) private var navigator

    let mealID: UUID

    var body: some View {
        if let meal = viewModel.meal(withID: mealID) {
            ScrollView {
                VStack(spacing: 20) {
                    hero(meal)
                    macros(meal)
                    ingredients(meal)
                    if !meal.steps.isEmpty { steps(meal) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(AppBackground())
            .navigationTitle(meal.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { viewModel.toggleFavorite(meal.id) } label: {
                        Label("Favorita", systemImage: meal.isFavorite ? "star.fill" : "star")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Editar") { navigator.mealEditor = .edit(meal) }
                }
            }
        } else {
            ContentUnavailableView("Comida no disponible", systemImage: "questionmark.folder")
        }
    }

    /// Cabecera con las franjas, el nombre y las calorías por ración.
    /// - Parameter meal: Comida a mostrar.
    /// - Returns: La tarjeta de cabecera.
    private func hero(_ meal: Meal) -> some View {
        let color = meal.suggestedSlot.color
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(meal.mealSlots) { slot in
                    Label(slot.title, systemImage: slot.icon)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.22), in: Capsule())
                }
            }
            Text(meal.name).font(.title.weight(.bold))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(meal.caloriesPerServing)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("kcal por ración").font(.subheadline).opacity(0.9)
            }
            Text("Receta completa: \(meal.calories) kcal · \(meal.servings) \(meal.servings == 1 ? "ración" : "raciones")")
                .font(.footnote)
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .shadow(color: color.opacity(0.35), radius: 14, y: 8)
    }

    /// Macronutrientes de una ración.
    /// - Parameter meal: Comida a mostrar.
    /// - Returns: Tres casillas con proteínas, hidratos y grasas.
    private func macros(_ meal: Meal) -> some View {
        let perServing = meal.nutritionPerServing
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                macro("Proteínas", perServing.protein, .red)
                macro("Carbohidratos", perServing.carbohydrates, .orange)
                macro("Grasas", perServing.fat, .blue)
            }
            Text("Valores por ración").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }

    /// Casilla con el valor de un macronutriente.
    /// - Parameters:
    ///   - title: Nombre del nutriente.
    ///   - value: Gramos.
    ///   - color: Color del valor.
    /// - Returns: La casilla.
    private func macro(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value.formatted(.number.precision(.fractionLength(0...1)))) g")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Lista de ingredientes con su cantidad.
    /// - Parameter meal: Comida a mostrar.
    /// - Returns: La sección de ingredientes.
    private func ingredients(_ meal: Meal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Ingredientes", systemImage: "carrot.fill", color: .orange)
            VStack(spacing: 0) {
                ForEach(Array(meal.ingredients.enumerated()), id: \.element.id) { index, ingredient in
                    HStack {
                        Text(ingredient.name)
                        Spacer()
                        Text(ingredient.quantity).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    if index < meal.ingredients.count - 1 { Divider() }
                }
            }
            .card(padding: 16)
        }
    }

    /// Pasos de preparación numerados.
    /// - Parameter meal: Comida a mostrar.
    /// - Returns: La sección de pasos.
    private func steps(_ meal: Meal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Preparación", systemImage: "list.number", color: .indigo)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(meal.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Theme.accent, in: Circle())
                        Text(step)
                    }
                }
            }
            .card(padding: 16)
        }
    }
}
