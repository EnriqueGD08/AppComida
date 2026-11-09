import SwiftUI
import UniformTypeIdentifiers

private struct AppBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    let backup: AppBackup

    init(backup: AppBackup) {
        self.backup = backup
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        backup = try JSONDecoder().decode(AppBackup.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(backup))
    }
}

@main
struct MealPlannerApp: App {
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
        }
    }
}

struct ContentView: View {
    private let store = FileMealStore()
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @State private var meals: [Meal]
    @State private var catalogIngredients: [CatalogIngredient]
    @State private var goal: Int
    @State private var plan: WeeklyPlan?
    @State private var message: String?
    @State private var editorMode: MealEditorMode?
    @State private var catalogEditorMode: CatalogEditorMode?
    @State private var mealToDelete: Meal?
    @State private var isShowingMessage = false
    @State private var backupDocument = AppBackupDocument(
        backup: AppBackup(meals: [], ingredients: [], plan: nil, dailyCalorieGoal: 2_000)
    )
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var selectedTab = AppTab.meals

    private var shoppingItems: [ShoppingItem] {
        plan.map { ShoppingListBuilder.build(plan: $0, meals: meals) } ?? []
    }

    init() {
        let store = FileMealStore()
        _meals = State(initialValue: (try? store.loadMeals()) ?? SampleMeals.all)
        _catalogIngredients = State(initialValue: (try? store.loadIngredients()) ?? [])
        _goal = State(initialValue: (try? store.loadDailyCalorieGoal()) ?? 2_000)
        _plan = State(initialValue: try? store.loadPlan())
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            MealsTabView(
                goal: $goal,
                meals: meals,
                onGenerate: generatePlan,
                onNew: { editorMode = .new },
                onEdit: { editorMode = .edit($0) },
                onDelete: { mealToDelete = $0 }
            )
            .tabItem { Label("Comidas", systemImage: "fork.knife") }
            .tag(AppTab.meals)

            PlanTabView(
                plan: plan,
                meals: meals,
                goal: goal,
                onEdit: { editorMode = .edit($0) },
                onShowShopping: { selectedTab = .shopping }
            )
            .tabItem { Label("Plan", systemImage: "calendar") }
            .tag(AppTab.plan)

            ShoppingTabView(
                items: shoppingItems,
                weekKey: plan.map { String(Int($0.weekStart.timeIntervalSince1970)) } ?? "none"
            )
            .tabItem { Label("Compra", systemImage: "cart") }
            .tag(AppTab.shopping)

            IngredientsTabView(
                ingredients: catalogIngredients,
                onNew: { catalogEditorMode = .new },
                onEdit: { catalogEditorMode = .edit($0) },
                onDelete: deleteCatalogIngredient
            )
            .tabItem { Label("Ingredientes", systemImage: "carrot") }
            .tag(AppTab.ingredients)

            NavigationStack {
                SettingsView(
                    appearance: $appearance,
                    onExport: exportBackup,
                    onImport: { isImportingBackup = true }
                )
            }
            .tabItem { Label("Ajustes", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
        .tint(Theme.accent)
        .onChange(of: goal) { _, newValue in
            do {
                try store.saveDailyCalorieGoal(newValue)
            } catch {
                presentMessage("No se pudo guardar el objetivo: \(error.localizedDescription)")
            }
        }
        .sheet(item: $editorMode) { mode in
            MealEditorView(
                meal: mode.meal,
                catalogIngredients: catalogIngredients,
                onSave: saveMeal,
                onSaveCatalogIngredient: saveCatalogIngredient
            )
        }
        .sheet(item: $catalogEditorMode) { mode in
            CatalogIngredientEditorView(ingredient: mode.ingredient, onSave: saveCatalogIngredient)
        }

        .confirmationDialog(
            "¿Eliminar \(mealToDelete?.name ?? "esta comida")?",
            isPresented: Binding(
                get: { mealToDelete != nil },
                set: { if !$0 { mealToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                if let mealToDelete {
                    deleteMeal(mealToDelete)
                }
            }
            Button("Cancelar", role: .cancel) {
                mealToDelete = nil
            }
        } message: {
            Text("También se eliminará del menú semanal guardado.")
        }
        .alert("Planificador", isPresented: $isShowingMessage) {
            Button("Aceptar") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .fileExporter(
            isPresented: $isExportingBackup,
            document: backupDocument,
            contentType: .json,
            defaultFilename: "copia-seguridad-appcomida.json"
        ) { result in
            if case .failure(let error) = result {
                presentMessage("No se pudo exportar la copia de seguridad: \(error.localizedDescription)")
            }
        }
        .fileImporter(
            isPresented: $isImportingBackup,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            importBackup(result)
        }
    }

    private func generatePlan() {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let generator = MenuGenerator()
        switch generator.generate(weekStarting: start, meals: meals, dailyGoal: goal) {
        case .success(let generated):
            do {
                try store.savePlan(generated)
                plan = generated
                let dailyCalories = Dictionary(grouping: generated.meals, by: {
                    Calendar.current.startOfDay(for: $0.date)
                }).values.map { plannedMeals in
                    plannedMeals.reduce(0) { total, planned in
                        total + (meals.first { $0.id == planned.mealID }?.caloriesPerServing ?? 0)
                    }
                }
                let hasApproximateDays = dailyCalories.contains { abs($0 - goal) > generator.tolerance }
                presentMessage(
                    hasApproximateDays
                        ? "Menú generado. No había una combinación dentro del límite; se han elegido las opciones más cercanas."
                        : "Menú generado correctamente, ajustando las comidas al objetivo."
                )
                selectedTab = .plan
            } catch {
                presentMessage("No se pudo guardar el menú: \(error.localizedDescription)")
            }
        case .failure(let error):
            presentMessage("No se pudo generar el menú: \(error.localizedDescription)")
        }
    }

    private func deleteCatalogIngredient(_ ingredient: CatalogIngredient) {
        let updated = catalogIngredients.filter { $0.id != ingredient.id }
        do {
            try store.saveIngredients(updated)
            catalogIngredients = updated
        } catch {
            presentMessage("No se pudo eliminar el ingrediente: \(error.localizedDescription)")
        }
    }

    private func saveMeal(_ meal: Meal) throws {
        var updatedMeals = meals
        if let index = updatedMeals.firstIndex(where: { $0.id == meal.id }) {
            updatedMeals[index] = meal
        } else {
            updatedMeals.append(meal)
        }
        try store.saveMeals(updatedMeals)
        meals = updatedMeals
    }

    private func saveCatalogIngredient(_ ingredient: CatalogIngredient) throws {
        var updatedIngredients = catalogIngredients
        if let index = updatedIngredients.firstIndex(where: { $0.id == ingredient.id }) {
            updatedIngredients[index] = ingredient
        } else {
            updatedIngredients.append(ingredient)
        }
        try store.saveIngredients(updatedIngredients)
        catalogIngredients = updatedIngredients
    }

    private func deleteMeal(_ meal: Meal) {
        let previousMeals = meals
        let previousPlan = plan
        let updatedMeals = meals.filter { $0.id != meal.id }
        let updatedPlan = plan.map { currentPlan in
            WeeklyPlan(
                weekStart: currentPlan.weekStart,
                meals: currentPlan.meals.filter { $0.mealID != meal.id }
            )
        }

        do {
            try store.saveMeals(updatedMeals)
            if let updatedPlan {
                try store.savePlan(updatedPlan)
            }
            meals = updatedMeals
            plan = updatedPlan
            mealToDelete = nil
        } catch {
            meals = previousMeals
            plan = previousPlan
            presentMessage("No se pudo eliminar la comida: \(error.localizedDescription)")
        }
    }

    private func presentMessage(_ text: String) {
        message = text
        isShowingMessage = true
    }

    private func exportBackup() {
        backupDocument = AppBackupDocument(
            backup: AppBackup(
                meals: meals,
                ingredients: catalogIngredients,
                plan: plan,
                dailyCalorieGoal: goal
            )
        )
        isExportingBackup = true
    }

    private func importBackup(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }

            let accessedSecurityScopedResource = url.startAccessingSecurityScopedResource()
            defer {
                if accessedSecurityScopedResource {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let backup = try JSONDecoder().decode(AppBackup.self, from: data)
            guard backup.version == AppBackup.currentVersion else {
                throw BackupError.unsupportedVersion(backup.version)
            }
            guard backup.dailyCalorieGoal > 0 else {
                throw BackupError.invalidData
            }

            try store.saveMeals(backup.meals)
            try store.saveIngredients(backup.ingredients)
            try store.saveDailyCalorieGoal(backup.dailyCalorieGoal)
            if let backupPlan = backup.plan {
                try store.savePlan(backupPlan)
            } else {
                try store.deletePlan()
            }

            meals = backup.meals
            catalogIngredients = backup.ingredients
            goal = backup.dailyCalorieGoal
            plan = backup.plan
            presentMessage("Copia de seguridad importada correctamente.")
        } catch {
            presentMessage("No se pudo importar la copia de seguridad: \(error.localizedDescription)")
        }
    }
}

private enum AppTab: Hashable {
    case meals, plan, shopping, ingredients, settings
}

private enum BackupError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "La copia de seguridad usa una versión no compatible (\(version))."
        case .invalidData:
            "La copia de seguridad contiene datos no válidos."
        }
    }
}

private enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Automático"
        case .light: "Claro"
        case .dark: "Oscuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private struct SettingsView: View {
    @Binding var appearance: String
    let onExport: () -> Void
    let onImport: () -> Void

    var body: some View {
        Form {
            Section {
                Picker(selection: $appearance) {
                    ForEach(Appearance.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                } label: {
                    Label("Tema", systemImage: "paintpalette.fill")
                }
            } header: {
                Text("Apariencia")
            }
            Section {
                Label {
                    Text("La sincronización con iCloud requiere una cuenta de Apple Developer de pago. Los datos se guardan localmente en este iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "icloud.slash").foregroundStyle(Theme.accent)
                }
            } header: {
                Text("Sincronización")
            }
            Section("Copia de seguridad") {
                Button {
                    onExport()
                } label: {
                    Label("Exportar datos", systemImage: "square.and.arrow.up")
                }
                Button {
                    onImport()
                } label: {
                    Label("Importar datos", systemImage: "square.and.arrow.down")
                }
                Text("La copia incluye comidas, ingredientes, menú semanal y objetivo diario. Guarda el archivo en un lugar seguro para usarlo en otro dispositivo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Ajustes")
    }
}

private enum MealEditorMode: Identifiable {
    case new
    case edit(Meal)

    var id: String {
        switch self {
        case .new:
            "new"
        case .edit(let meal):
            meal.id.uuidString
        }

    }

    var meal: Meal? {
        switch self {
        case .new:
            nil
        case .edit(let meal):
            meal
        }
    }
}

private enum CatalogEditorMode: Identifiable {
    case new
    case edit(CatalogIngredient)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let ingredient): ingredient.id.uuidString
        }
    }

    var ingredient: CatalogIngredient? {
        switch self {
        case .new: nil
        case .edit(let ingredient): ingredient
        }
    }
}

private struct CatalogIngredientEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CatalogIngredient
    private let isNew: Bool
    let onSave: (CatalogIngredient) throws -> Void
    @State private var errorMessage: String?

    init(ingredient: CatalogIngredient?, onSave: @escaping (CatalogIngredient) throws -> Void) {
        self.onSave = onSave
        isNew = ingredient == nil
        _draft = State(initialValue: ingredient ?? CatalogIngredient(name: "", calories: 0))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $draft.name)
                TextField("Calorías", value: $draft.calories, format: .number)
                    .keyboardType(.decimalPad)
                Picker("Unidad", selection: $draft.calorieUnit) {
                    ForEach(CalorieUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
            }
            .navigationTitle(isNew ? "Nuevo ingrediente" : "Editar ingrediente")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                }
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

    private func save() {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.name.isEmpty else {
            errorMessage = "Indica un nombre para el ingrediente."
            return
        }
        guard draft.calories > 0 else {
            errorMessage = "Las calorías deben ser mayores que cero."
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

private struct MealEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Meal
    @State private var catalogIngredients: [CatalogIngredient]
    @State private var catalogEditorMode: CatalogEditorMode?
    @State private var isPickingIngredient = false
    private let isNew: Bool
    let onSave: (Meal) throws -> Void
    let onSaveCatalogIngredient: (CatalogIngredient) throws -> Void
    @State private var errorMessage: String?

    init(
        meal: Meal?,
        catalogIngredients: [CatalogIngredient],
        onSave: @escaping (Meal) throws -> Void,
        onSaveCatalogIngredient: @escaping (CatalogIngredient) throws -> Void
    ) {
        self.onSave = onSave
        self.onSaveCatalogIngredient = onSaveCatalogIngredient
        isNew = meal == nil
        _draft = State(initialValue: meal ?? Meal(name: "", suggestedSlot: .breakfast, calories: 0))
        _catalogIngredients = State(initialValue: catalogIngredients)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Datos básicos") {
                    TextField("Nombre", text: $draft.name)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tipos de comida")
                        ForEach(MealSlot.allCases) { slot in
                            Toggle(slot.title, isOn: Binding(
                                get: { draft.mealSlots.contains(slot) },
                                set: { isSelected in
                                    if isSelected {
                                        draft.mealSlots.append(slot)
                                    } else {
                                        draft.mealSlots.removeAll { $0 == slot }
                                    }
                                }
                            ))
                        }
                    }
                    LabeledContent("Calorías de la receta", value: calculatedCalories.formatted() + " kcal")
                    TextField("Raciones", value: $draft.servings, format: .number)
                        .keyboardType(.numberPad)
                }
                Section("Ingredientes") {
                    ForEach($draft.ingredients) { $ingredient in
                        VStack(alignment: .leading) {
                            NavigationLink {
                                IngredientPickerView(
                                    ingredients: catalogIngredients,
                                    selectedID: ingredient.catalogID
                                ) { selected in
                                    ingredient.catalogID = selected.id
                                    ingredient.name = selected.name
                                }
                            } label: {
                                LabeledContent("Ingrediente", value: ingredient.name)
                            }
                            TextField("Gramos", value: gramsBinding(for: $ingredient), format: .number)
                                .keyboardType(.decimalPad)
                        }
                    }
                    .onDelete { draft.ingredients.remove(atOffsets: $0) }
                    Button {
                        isPickingIngredient = true
                    } label: {
                        Label("Añadir ingrediente", systemImage: "plus")
                    }
                    .disabled(catalogIngredients.isEmpty)
                    Button {
                        catalogEditorMode = .new
                    } label: {
                        Label("Registrar ingrediente nuevo", systemImage: "plus.circle")
                    }
                    if catalogIngredients.isEmpty {
                        Text("Registra un ingrediente nuevo para poder añadirlo a esta comida.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Información nutricional (opcional)") {
                    TextField("Proteínas (g)", value: $draft.nutrition.protein, format: .number)
                    TextField("Carbohidratos (g)", value: $draft.nutrition.carbohydrates, format: .number)
                    TextField("Grasas (g)", value: $draft.nutrition.fat, format: .number)
                }
                Section("Preparación (opcional)") {
                    ForEach($draft.steps.indices, id: \.self) { index in
                        TextField("Paso \(index + 1)", text: $draft.steps[index])
                    }
                    .onDelete { draft.steps.remove(atOffsets: $0) }
                    Button {
                        draft.steps.append("")
                    } label: {
                        Label("Añadir paso", systemImage: "plus")
                    }
                }
            }
            .navigationTitle(isNew ? "Nueva comida" : "Editar comida")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                }
            }
            .alert("No se puede guardar", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Aceptar") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(item: $catalogEditorMode) { mode in
                CatalogIngredientEditorView(ingredient: mode.ingredient, onSave: saveCatalogIngredient)
            }
            .sheet(isPresented: $isPickingIngredient) {
                NavigationStack {
                    IngredientPickerView(ingredients: catalogIngredients, selectedID: nil) { selected in
                        draft.ingredients.append(Ingredient(
                            name: selected.name,
                            quantity: "0 g",
                            catalogID: selected.id,
                            grams: 0
                        ))
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancelar") { isPickingIngredient = false }
                        }
                    }
                }
            }
        }
    }

    private func saveCatalogIngredient(_ ingredient: CatalogIngredient) throws {
        try onSaveCatalogIngredient(ingredient)
        catalogIngredients.append(ingredient)
        draft.ingredients.append(Ingredient(
            name: ingredient.name,
            quantity: "0 g",
            catalogID: ingredient.id,
            grams: 0
        ))
    }

    private func save() {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.ingredients = draft.ingredients.map {
            var ingredient = $0
            ingredient.name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let grams = ingredient.grams {
                ingredient.quantity = "\(grams.formatted()) g"
            }
            return ingredient
        }
        draft.steps = draft.steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        guard !draft.name.isEmpty else {
            errorMessage = "Indica un nombre para la comida."
            return
        }
        guard !draft.mealSlots.isEmpty else {
            errorMessage = "Selecciona al menos un tipo de comida."
            return
        }
        guard !draft.ingredients.isEmpty else {
            errorMessage = "Añade al menos un ingrediente."
            return
        }
        let selectedIngredients = draft.ingredients.compactMap { ingredient -> (CatalogIngredient, Double)? in
            guard let catalogID = ingredient.catalogID,
                  let grams = ingredient.grams,
                  let catalogIngredient = catalogIngredients.first(where: { $0.id == catalogID }) else {
                return nil
            }
            return (catalogIngredient, grams)
        }
        guard selectedIngredients.count == draft.ingredients.count,
              selectedIngredients.allSatisfy({ $0.1 > 0 }) else {
            errorMessage = "Selecciona un ingrediente registrado y una cantidad de gramos mayor que cero para cada ingrediente."
            return
        }
        draft.calories = Int(selectedIngredients.reduce(0) {
            $0 + $1.0.caloriesPerGram * $1.1
        }.rounded())
        guard draft.servings > 0 else {
            errorMessage = "Las raciones deben ser mayores que cero."
            return
        }
        guard !draft.ingredients.isEmpty, draft.ingredients.allSatisfy({ !$0.name.isEmpty && !$0.quantity.isEmpty }) else {
            errorMessage = "Añade al menos un ingrediente con nombre y cantidad."
            return
        }
        guard draft.nutrition.protein >= 0, draft.nutrition.carbohydrates >= 0, draft.nutrition.fat >= 0 else {
            errorMessage = "Los valores nutricionales no pueden ser negativos."
            return
        }

        do {
            try onSave(draft)
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar la comida: \(error.localizedDescription)"
        }
    }

    private var calculatedCalories: Int {
        Int(draft.ingredients.reduce(0) { total, ingredient in
            guard let catalogID = ingredient.catalogID,
                  let grams = ingredient.grams,
                  let catalogIngredient = catalogIngredients.first(where: { $0.id == catalogID }) else {
                return total
            }
            return total + catalogIngredient.caloriesPerGram * grams
        }.rounded())
    }

    private func gramsBinding(for ingredient: Binding<Ingredient>) -> Binding<Double> {
        Binding(
            get: { ingredient.wrappedValue.grams ?? 0 },
            set: { ingredient.wrappedValue.grams = $0 }
        )
    }
}

private extension GenerationError {
    var localizedDescription: String {
        switch self {
        case .invalidGoal: "el objetivo de calorías no es válido."
        case .invalidDate: "la fecha de inicio no es válida."
        case .notEnoughMeals: "necesitas comidas para las cuatro franjas."
        case .goalUnavailable(let day, let calories): "el día \(day) suma \(calories) kcal y queda fuera de la tolerancia."
        }
    }
}
