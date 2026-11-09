//
//  IngredientScreens.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Pantallas del catálogo de ingredientes: listado con búsqueda, selector y formulario de alta/edición con macronutrientes, peso por unidad y sección.
//

import SwiftUI

// MARK: - Listado

/// Pestaña "Ingredientes": catálogo con búsqueda por nombre y acciones de editar y eliminar.
struct IngredientsTabView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(Navigator.self) private var navigator

    @State private var query = ""

    /// Ingredientes que coinciden con la búsqueda, ordenados por nombre.
    private var filtered: [CatalogIngredient] {
        let key = query.searchKey
        return viewModel.catalog
            .filter { key.isEmpty || $0.name.searchKey.contains(key) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { ingredient in
                    HStack(spacing: 14) {
                        IconBadge(systemName: (ingredient.category ?? .other).icon, color: .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ingredient.name).font(.headline)
                            Text(subtitle(for: ingredient)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .card(padding: 14)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .swipeActions {
                        Button { navigator.catalogEditor = .edit(ingredient) } label: { Label("Editar", systemImage: "pencil") }
                            .tint(Theme.accent)
                        Button(role: .destructive) { viewModel.deleteCatalogIngredient(ingredient) } label: {
                            Label("Eliminar", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .overlay {
                if !viewModel.catalog.isEmpty && filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else if viewModel.catalog.isEmpty {
                    EmptyCard(
                        systemImage: "carrot",
                        title: "Sin ingredientes",
                        message: "Añade ingredientes para reutilizarlos al crear comidas."
                    )
                }
            }
            .navigationTitle("Ingredientes")
            .searchable(text: $query, prompt: "Buscar ingrediente")
            .toolbar {
                Button { navigator.catalogEditor = .new } label: {
                    Label("Nuevo ingrediente", systemImage: "plus")
                }
            }
        }
    }

    /// Texto secundario de un ingrediente: calorías, sección y peso por unidad si los tiene.
    /// - Parameter ingredient: Ingrediente del catálogo.
    /// - Returns: El texto descriptivo.
    private func subtitle(for ingredient: CatalogIngredient) -> String {
        var parts = ["\(ingredient.calories.formatted()) kcal \(ingredient.calorieUnit.title.lowercased())"]
        if let category = ingredient.category { parts.append(category.title) }
        if let weight = ingredient.unitWeightGrams { parts.append("1 ud ≈ \(weight.formatted()) g") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Selector

/// Selector de ingredientes del catálogo con búsqueda por nombre.
struct IngredientPickerView: View {
    @Environment(AppViewModel.self) private var viewModel

    let selectedID: UUID?
    let onSelect: (CatalogIngredient) -> Void

    var body: some View {
        SearchableSelectionList(
            items: viewModel.catalog.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            title: "Ingrediente",
            prompt: "Buscar ingrediente",
            searchText: \.name,
            isSelected: { $0.id == selectedID },
            onSelect: onSelect
        ) { ingredient in
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.name)
                Text("\(ingredient.calories.formatted()) kcal \(ingredient.calorieUnit.title.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Formulario

/// Formulario para crear o editar un ingrediente del catálogo.
struct CatalogIngredientEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CatalogIngredient
    @State private var errorMessage: String?
    private let isNew: Bool
    let onSave: (CatalogIngredient) throws -> Void

    /// Crea el formulario.
    /// - Parameters:
    ///   - ingredient: Ingrediente a editar, o `nil` para crear uno nuevo.
    ///   - onSave: Acción que guarda el ingrediente.
    init(ingredient: CatalogIngredient?, onSave: @escaping (CatalogIngredient) throws -> Void) {
        self.onSave = onSave
        isNew = ingredient == nil
        _draft = State(initialValue: ingredient ?? CatalogIngredient(name: "", calories: 0))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Datos básicos") {
                    TextField("Nombre", text: $draft.name)
                    TextField("Calorías", value: $draft.calories, format: .number)
                        .keyboardType(.decimalPad)
                    Picker("Unidad de las calorías", selection: $draft.calorieUnit) {
                        ForEach(CalorieUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    Picker("Sección del supermercado", selection: $draft.category) {
                        Text("Sin sección").tag(IngredientCategory?.none)
                        ForEach(IngredientCategory.allCases) { category in
                            Text(category.title).tag(IngredientCategory?.some(category))
                        }
                    }
                }
                Section {
                    TextField("Proteínas (g)", value: $draft.protein, format: .number).keyboardType(.decimalPad)
                    TextField("Carbohidratos (g)", value: $draft.carbohydrates, format: .number).keyboardType(.decimalPad)
                    TextField("Grasas (g)", value: $draft.fat, format: .number).keyboardType(.decimalPad)
                } header: {
                    Text("Macronutrientes por 100 g (opcional)")
                } footer: {
                    Text("Si todos los ingredientes de una comida los tienen, sus valores nutricionales se calculan solos.")
                }
                Section {
                    TextField("Peso de una unidad (g)", value: $draft.unitWeightGrams, format: .number)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Unidades (opcional)")
                } footer: {
                    Text("Para ingredientes que se cuentan por piezas (un huevo ≈ 60 g). La lista de la compra mostrará unidades en vez de gramos.")
                }
            }
            .navigationTitle(isNew ? "Nuevo ingrediente" : "Editar ingrediente")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { save() } }
            }
            .alert("No se puede guardar", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Aceptar") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    /// Valida el formulario, guarda el ingrediente y cierra la hoja; si algo falla, muestra el motivo.
    private func save() {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = CatalogIngredientValidator.validate(draft) {
            errorMessage = problem
            return
        }
        do {
            try onSave(draft)
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar el ingrediente: \(error.localizedDescription)"
        }
    }
}
