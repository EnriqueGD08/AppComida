//
//  MealEditorView.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Formulario para crear o editar una comida: datos básicos, ingredientes con buscador, información nutricional (automática si el catálogo tiene macronutrientes) y pasos.
//

import SwiftUI

/// Formulario para crear o editar una comida.
struct MealEditorView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Meal
    @State private var errorMessage: String?
    @State private var isPickingIngredient = false
    @State private var isCreatingIngredient = false
    @State private var isPickingOption = false
    @State private var optionTargetGroup: UUID?
    private let isNew: Bool

    /// Crea el editor.
    /// - Parameter meal: Comida a editar, o `nil` para crear una nueva.
    init(meal: Meal?) {
        isNew = meal == nil
        _draft = State(initialValue: meal ?? Meal(name: "", suggestedSlot: .breakfast, calories: 0))
    }

    /// Macronutrientes calculados con el catálogo, o `nil` si no se pueden calcular.
    private var automaticNutrition: Nutrition? {
        RecipeCalculator.nutrition(of: draft.ingredients, catalog: viewModel.catalog)
    }

    var body: some View {
        NavigationStack {
            Form {
                basicsSection
                ingredientsSection
                optionGroupsSections
                nutritionSection
                stepsSection
            }
            .navigationTitle(isNew ? "Nueva comida" : "Editar comida")
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
            .sheet(isPresented: $isPickingIngredient) {
                NavigationStack {
                    IngredientPickerView(selectedID: nil) { selected in
                        draft.ingredients.append(Ingredient(name: selected.name, quantity: "0 g", catalogID: selected.id, grams: 0))
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { isPickingIngredient = false } }
                    }
                }
            }
            .sheet(isPresented: $isPickingOption) {
                NavigationStack {
                    IngredientPickerView(selectedID: nil) { selected in
                        guard let index = draft.optionGroups.firstIndex(where: { $0.id == optionTargetGroup }) else { return }
                        draft.optionGroups[index].options.append(MealOption(
                            ingredient: Ingredient(name: selected.name, quantity: "0 g", catalogID: selected.id, grams: 0)
                        ))
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { isPickingOption = false } }
                    }
                }
            }
            .sheet(isPresented: $isCreatingIngredient) {
                CatalogIngredientEditorView(ingredient: nil) { newIngredient in
                    try viewModel.saveCatalogIngredient(newIngredient)
                    draft.ingredients.append(Ingredient(name: newIngredient.name, quantity: "0 g", catalogID: newIngredient.id, grams: 0))
                }
            }
        }
    }

    // MARK: Secciones

    /// Nombre, franjas, favorita, calorías y raciones.
    private var basicsSection: some View {
        Section {
            TextField("Nombre", text: $draft.name)
            VStack(alignment: .leading, spacing: 8) {
                Text("Tipos de comida")
                ForEach(MealSlot.allCases) { slot in
                    Toggle(slot.title, isOn: Binding(
                        get: { draft.mealSlots.contains(slot) },
                        set: { isSelected in
                            if isSelected {
                                if !draft.mealSlots.contains(slot) { draft.mealSlots.append(slot) }
                            } else {
                                draft.mealSlots.removeAll { $0 == slot }
                            }
                        }
                    ))
                }
            }
            Toggle("Favorita", isOn: $draft.isFavorite)
            LabeledContent(
                "Calorías de la receta",
                value: RecipeCalculator.calories(of: draft.ingredients, catalog: viewModel.catalog).formatted() + " kcal"
            )
            TextField("Raciones de la receta", value: $draft.servings, format: .number)
                .keyboardType(.numberPad)
            Stepper(value: $draft.plannedServings, in: 0.5...6, step: 0.5) {
                LabeledContent(
                    "Raciones por toma",
                    value: draft.plannedServings.formatted(.number.precision(.fractionLength(0...1)))
                )
            }
        } header: {
            Text("Datos básicos")
        } footer: {
            Text("\"Raciones de la receta\" es lo que da la receta entera. \"Raciones por toma\" es cuántas se añaden al menú cada vez que sale esta comida.")
        }
    }

    /// Un bloque por ingrediente variable (nombre y opciones) y el botón para añadir otro.
    ///
    /// Al generar el menú se elige una opción de cada grupo para cada día, repartidas a lo largo de la semana.
    @ViewBuilder
    private var optionGroupsSections: some View {
        ForEach($draft.optionGroups) { $group in
            Section {
                TextField("Nombre (por ejemplo, Untado)", text: $group.name)
                ForEach($group.options) { $option in
                    VStack(alignment: .leading, spacing: 4) {
                        NavigationLink {
                            IngredientPickerView(selectedID: option.ingredient.catalogID) { selected in
                                option.ingredient.catalogID = selected.id
                                option.ingredient.name = selected.name
                            }
                        } label: {
                            LabeledContent("Opción", value: option.ingredient.name)
                        }
                        TextField("Gramos", value: gramsBinding(for: $option.ingredient), format: .number)
                            .keyboardType(.decimalPad)
                        Text("\(optionCalories(option)) kcal").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onDelete { group.options.remove(atOffsets: $0) }
                Button {
                    optionTargetGroup = group.id
                    isPickingOption = true
                } label: {
                    Label("Añadir opción", systemImage: "plus")
                }
                .disabled(viewModel.catalog.isEmpty)
            } header: {
                HStack {
                    Text("Ingrediente variable")
                    Spacer()
                    Button(role: .destructive) {
                        draft.optionGroups.removeAll { $0.id == group.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Quitar ingrediente variable")
                }
            }
        }
        Section {
            Button {
                draft.optionGroups.append(MealOptionGroup(name: ""))
            } label: {
                Label("Añadir ingrediente variable", systemImage: "shuffle")
            }
        } header: {
            if draft.optionGroups.isEmpty { Text("Ingredientes variables (opcional)") }
        } footer: {
            Text("Por ejemplo, unas tortitas con un untado a elegir entre chocolate, mermelada, queso de untar o jamón. Al generar el menú se elige una opción distinta cada día y las calorías y la compra cuentan la elegida.")
        }
    }

    /// Lista de ingredientes con cantidades en gramos y botones para añadir o registrar nuevos.
    private var ingredientsSection: some View {
        Section("Ingredientes") {
            ForEach($draft.ingredients) { $ingredient in
                VStack(alignment: .leading, spacing: 4) {
                    NavigationLink {
                        IngredientPickerView(selectedID: ingredient.catalogID) { selected in
                            ingredient.catalogID = selected.id
                            ingredient.name = selected.name
                        }
                    } label: {
                        LabeledContent("Ingrediente", value: ingredient.name)
                    }
                    TextField("Gramos", value: gramsBinding(for: $ingredient), format: .number)
                        .keyboardType(.decimalPad)
                    if let hint = unitsHint(for: ingredient) {
                        Text(hint).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { draft.ingredients.remove(atOffsets: $0) }
            Button { isPickingIngredient = true } label: {
                Label("Añadir ingrediente", systemImage: "plus")
            }
            .disabled(viewModel.catalog.isEmpty)
            Button { isCreatingIngredient = true } label: {
                Label("Registrar ingrediente nuevo", systemImage: "plus.circle")
            }
            if viewModel.catalog.isEmpty {
                Text("Registra un ingrediente nuevo para poder añadirlo a esta comida.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Información nutricional: de solo lectura si se calcula sola, o editable a mano si no.
    @ViewBuilder
    private var nutritionSection: some View {
        if let automatic = automaticNutrition {
            Section {
                LabeledContent("Proteínas", value: "\(automatic.protein.formatted(.number.precision(.fractionLength(0...1)))) g")
                LabeledContent("Carbohidratos", value: "\(automatic.carbohydrates.formatted(.number.precision(.fractionLength(0...1)))) g")
                LabeledContent("Grasas", value: "\(automatic.fat.formatted(.number.precision(.fractionLength(0...1)))) g")
            } header: {
                Text("Información nutricional de la receta")
            } footer: {
                Text("Calculada automáticamente con los macronutrientes de los ingredientes.")
            }
        } else {
            Section {
                TextField("Proteínas (g)", value: $draft.nutrition.protein, format: .number)
                TextField("Carbohidratos (g)", value: $draft.nutrition.carbohydrates, format: .number)
                TextField("Grasas (g)", value: $draft.nutrition.fat, format: .number)
            } header: {
                Text("Información nutricional de la receta (opcional)")
            } footer: {
                Text("Se calcula sola cuando todos los ingredientes tienen macronutrientes en el catálogo.")
            }
        }
    }

    /// Pasos de preparación.
    private var stepsSection: some View {
        Section("Preparación (opcional)") {
            ForEach($draft.steps.indices, id: \.self) { index in
                TextField("Paso \(index + 1)", text: $draft.steps[index])
            }
            .onDelete { draft.steps.remove(atOffsets: $0) }
            Button { draft.steps.append("") } label: {
                Label("Añadir paso", systemImage: "plus")
            }
        }
    }

    // MARK: Acciones

    /// Valida el formulario, calcula calorías y nutrición, guarda la comida y cierra la hoja; si algo falla, muestra el motivo.
    private func save() {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.ingredients = draft.ingredients.map { ingredient in
            var cleaned = ingredient
            cleaned.name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let grams = ingredient.grams {
                cleaned.quantity = "\(grams.formatted(.number.precision(.fractionLength(0...1)))) g"
            }
            return cleaned
        }
        draft.steps = draft.steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        draft.optionGroups = draft.optionGroups.map { group in
            var cleaned = group
            cleaned.name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.options = group.options.map { option in
                var updated = option
                if let grams = option.ingredient.grams {
                    updated.ingredient.quantity = "\(grams.formatted(.number.precision(.fractionLength(0...1)))) g"
                }
                return updated
            }
            return cleaned
        }

        if let problem = MealValidator.validate(draft, catalog: viewModel.catalog) {
            errorMessage = problem
            return
        }
        draft = RecipeCalculator.recalculated(draft, catalog: viewModel.catalog)
        do {
            try viewModel.saveMeal(draft)
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar la comida: \(error.localizedDescription)"
        }
    }

    /// Calorías de una opción con la cantidad indicada, según el catálogo.
    /// - Parameter option: Opción de un ingrediente variable.
    /// - Returns: Las calorías, o 0 si todavía no se puede calcular.
    private func optionCalories(_ option: MealOption) -> Int {
        RecipeCalculator.values(of: option.ingredient, catalog: viewModel.catalog)?.calories ?? 0
    }

    /// Binding de los gramos de un ingrediente que usa 0 cuando no hay valor.
    /// - Parameter ingredient: Ingrediente a editar.
    /// - Returns: Un binding de lectura y escritura.
    private func gramsBinding(for ingredient: Binding<Ingredient>) -> Binding<Double> {
        Binding(
            get: { ingredient.wrappedValue.grams ?? 0 },
            set: { ingredient.wrappedValue.grams = $0 }
        )
    }

    /// Texto con las unidades equivalentes a los gramos, si el ingrediente tiene peso por unidad.
    /// - Parameter ingredient: Ingrediente de la comida.
    /// - Returns: Por ejemplo "≈ 2 unidades", o `nil` si no aplica.
    private func unitsHint(for ingredient: Ingredient) -> String? {
        guard let grams = ingredient.grams, grams > 0,
              let id = ingredient.catalogID,
              let units = RecipeCalculator.units(forGrams: grams, of: viewModel.catalogIngredient(withID: id)) else { return nil }
        let text = units.formatted(.number.precision(.fractionLength(0...1)))
        return "≈ \(text) \(units == 1 ? "unidad" : "unidades")"
    }
}
