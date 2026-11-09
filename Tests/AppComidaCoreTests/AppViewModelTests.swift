//
//  AppViewModelTests.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: macOS / iOS · Swift Testing
//  Descripción: Pruebas de los casos de uso de `AppViewModel` usando un almacén en memoria y dependencias falsas inyectadas.
//

import Foundation
import Testing
@testable import AppComidaCore

/// Error de prueba para simular fallos de escritura.
struct DiskFullError: Error, LocalizedError {
    var errorDescription: String? { "disco lleno" }
}

/// Almacén en memoria que cumple `MealStore`, con opción de forzar fallos al guardar.
final class InMemoryStore: MealStore, @unchecked Sendable {
    var meals: [Meal] = SampleMeals.all
    var ingredients: [CatalogIngredient] = []
    var plan: WeeklyPlan?
    var goal = 2_000
    var extras = ShoppingExtras()
    var failSaves = false
    var failLoads = false

    private func check() throws { if failSaves { throw DiskFullError() } }

    func loadMeals() throws -> [Meal] { if failLoads { throw DiskFullError() }; return meals }
    func saveMeals(_ meals: [Meal]) throws { try check(); self.meals = meals }
    func loadIngredients() throws -> [CatalogIngredient] { ingredients }
    func saveIngredients(_ ingredients: [CatalogIngredient]) throws { try check(); self.ingredients = ingredients }
    func loadPlan() throws -> WeeklyPlan? { plan }
    func savePlan(_ plan: WeeklyPlan) throws { try check(); self.plan = plan }
    func deletePlan() throws { try check(); plan = nil }
    func loadDailyCalorieGoal() throws -> Int { goal }
    func saveDailyCalorieGoal(_ goal: Int) throws { try check(); self.goal = goal }
    func loadShoppingExtras() throws -> ShoppingExtras { extras }
    func saveShoppingExtras(_ extras: ShoppingExtras) throws { try check(); self.extras = extras }
}

/// Recordatorios falsos: guardan la última petición y devuelven el resultado configurado.
final class FakeReminders: ReminderScheduling {
    var result = true
    var lastRequest: Bool?
    func setWeeklyMenuReminder(enabled: Bool) async -> Bool {
        lastRequest = enabled
        return result
    }
}

@MainActor
@Suite("AppViewModel")
struct AppViewModelTests {
    private let monday = Fixtures.monday

    /// Crea un modelo con dependencias falsas y un reloj fijo.
    private func make(
        store: InMemoryStore = InMemoryStore(),
        now: Date = Fixtures.monday,
        reminders: FakeReminders = FakeReminders()
    ) -> (AppViewModel, InMemoryStore, FakeReminders) {
        let defaults = UserDefaults(suiteName: "appcomida-tests-\(UUID().uuidString)")!
        let model = AppViewModel(
            store: store,
            generator: MenuGenerator(calendar: Fixtures.calendar, seed: 3),
            reminders: reminders,
            defaults: defaults,
            calendar: Fixtures.calendar,
            now: { now }
        )
        return (model, store, reminders)
    }

    private func storeWithVariedMeals() -> InMemoryStore {
        let store = InMemoryStore()
        store.meals = Fixtures.variedMeals
        return store
    }

    // MARK: Plan

    @Test("Generar guarda el plan de la semana actual")
    func generatesAndPersistsPlan() {
        let (model, store, _) = make(store: storeWithVariedMeals())
        #expect(model.generatePlan())
        #expect(model.plan?.meals.count == 28)
        #expect(store.plan == model.plan)
        #expect(model.plan?.weekStart == Fixtures.monday)
    }

    @Test("Informa si no hay comidas suficientes")
    func reportsNotEnoughMeals() {
        let store = InMemoryStore()
        store.meals = [Fixtures.meal("Tostada", .breakfast, 300)]
        let (model, _, _) = make(store: store)
        #expect(!model.generatePlan())
        #expect(model.message?.contains("cuatro franjas") == true)
        #expect(model.plan == nil)
    }

    @Test("Regenerar conserva las comidas bloqueadas")
    func regenerationKeepsLockedMeals() throws {
        let (model, _, _) = make(store: storeWithVariedMeals())
        model.generatePlan()
        let target = try #require(model.plan?.meals.first { $0.slot == .lunch })
        model.toggleLock(planned: target.id)
        model.generatePlan()
        let after = model.plan?.meals.first { $0.id == target.id }
        #expect(after?.mealID == target.mealID)
        #expect(after?.isLocked == true)
    }

    @Test("Cambiar comida y raciones se guarda y limita las raciones")
    func editsPlannedMeal() throws {
        let (model, store, _) = make(store: storeWithVariedMeals())
        model.generatePlan()
        let target = try #require(model.plan?.meals.first { $0.slot == .dinner })
        let other = try #require(model.meals.first { $0.mealSlots.contains(.dinner) && $0.id != target.mealID })

        model.replaceMeal(planned: target.id, with: other.id)
        model.setServings(10, forPlanned: target.id)
        #expect(model.plannedMeal(withID: target.id)?.mealID == other.id)
        #expect(model.plannedMeal(withID: target.id)?.servings == 6)
        #expect(store.plan?.meals.first { $0.id == target.id }?.servings == 6)

        model.setServings(0, forPlanned: target.id)
        #expect(model.plannedMeal(withID: target.id)?.servings == 0.5)
    }

    @Test("Si guardar falla, el plan en memoria no cambia y se avisa")
    func failedSaveDoesNotChangeState() throws {
        let store = storeWithVariedMeals()
        let (model, _, _) = make(store: store)
        model.generatePlan()
        let before = model.plan
        let target = try #require(before?.meals.first)

        store.failSaves = true
        model.toggleLock(planned: target.id)
        #expect(model.plan == before)
        #expect(model.message?.contains("disco lleno") == true)
    }

    // MARK: Comidas e ingredientes

    @Test("Eliminar una comida la quita también del plan")
    func deletingMealRemovesItFromPlan() throws {
        let (model, store, _) = make(store: storeWithVariedMeals())
        model.generatePlan()
        let used = try #require(model.plan?.meals.first)
        let meal = try #require(model.meal(withID: used.mealID))
        model.deleteMeal(meal)
        #expect(model.meal(withID: meal.id) == nil)
        #expect(model.plan?.meals.contains { $0.mealID == meal.id } == false)
        #expect(store.meals.contains { $0.id == meal.id } == false)
    }

    @Test("Duplicar y marcar favorita")
    func duplicatesAndFavorites() throws {
        let (model, _, _) = make(store: storeWithVariedMeals())
        let original = try #require(model.meals.first)
        let count = model.meals.count
        model.duplicateMeal(original.id)
        #expect(model.meals.count == count + 1)
        #expect(model.meals.contains { $0.name == original.name + " (copia)" })

        model.toggleFavorite(original.id)
        #expect(model.meal(withID: original.id)?.isFavorite == true)
    }

    @Test("Guardar un ingrediente recalcula las calorías de las comidas que lo usan")
    func catalogChangeRecalculatesMeals() throws {
        let (model, _, _) = make()
        var oats = CatalogIngredient(name: "Avena", calories: 300)
        try model.saveCatalogIngredient(oats)
        let meal = Meal(name: "Gachas", suggestedSlot: .breakfast, calories: 300, ingredients: [Ingredient(name: "Avena", quantity: "100 g", catalogID: oats.id, grams: 100)])
        try model.saveMeal(meal)

        oats.calories = 400
        try model.saveCatalogIngredient(oats)
        #expect(model.meal(withID: meal.id)?.calories == 400)
    }

    @Test("No deja eliminar un ingrediente que se usa en alguna comida")
    func refusesToDeleteUsedIngredient() throws {
        let (model, _, _) = make()
        let oats = CatalogIngredient(name: "Avena", calories: 300)
        try model.saveCatalogIngredient(oats)
        try model.saveMeal(Meal(name: "Gachas", suggestedSlot: .breakfast, calories: 300, ingredients: [Ingredient(name: "Avena", quantity: "", catalogID: oats.id, grams: 100)]))

        model.deleteCatalogIngredient(oats)
        #expect(model.catalog.count == 1)
        #expect(model.message?.contains("1 comida") == true)

        let unused = CatalogIngredient(name: "Sal", calories: 1)
        try model.saveCatalogIngredient(unused)
        model.deleteCatalogIngredient(unused)
        #expect(model.catalog.contains { $0.id == unused.id } == false)
    }

    @Test("El objetivo se limita entre 500 y 5000 kcal")
    func clampsGoal() {
        let (model, store, _) = make()
        model.setGoal(100)
        #expect(model.goal == 500)
        model.setGoal(9_999)
        #expect(model.goal == 5_000)
        #expect(store.goal == 5_000)
    }

    // MARK: Compra

    @Test("La lista de la compra incluye el plan y respeta lo que ya hay en casa")
    func shoppingListAndPantry() throws {
        let (model, _, _) = make(store: storeWithVariedMeals())
        let flour = CatalogIngredient(name: "Harina", calories: 360, category: .bakeryCereals)
        try model.saveCatalogIngredient(flour)
        for meal in model.meals {
            var updated = meal
            updated.ingredients = [Ingredient(name: "Harina", quantity: "100 g", catalogID: flour.id, grams: 100)]
            try model.saveMeal(updated)
        }
        model.generatePlan()
        let item = try #require(model.shoppingItems.first)
        #expect(item.name == "Harina")

        model.toggleChecked(item)
        #expect(model.isChecked(item))
        model.toggleChecked(item)
        #expect(!model.isChecked(item))

        model.addToPantry(item)
        #expect(model.shoppingItems.isEmpty)
        #expect(model.pantryItems.count == 1)
        model.removeFromPantry(item)
        #expect(model.shoppingItems.count == 1)
    }

    @Test("Productos manuales: añadir, marcar y eliminar")
    func manualItems() throws {
        let (model, store, _) = make()
        model.addManualItem(name: "  ", quantity: "1")
        #expect(model.extras.manualItems.isEmpty)

        model.addManualItem(name: "Pilas", quantity: "2")
        let item = try #require(model.extras.manualItems.first)
        model.toggleChecked(item)
        #expect(model.isChecked(item))
        #expect(store.extras.checkedKeys.count == 1)

        model.removeManualItem(item)
        #expect(model.extras.manualItems.isEmpty)
        #expect(model.extras.checkedKeys.isEmpty)
    }

    // MARK: Copias de seguridad

    @Test("Importar combinando conserva los datos actuales")
    func importMergeKeepsCurrentData() throws {
        let (model, _, _) = make()
        try model.saveMeal(Meal(name: "Mi receta", suggestedSlot: .lunch, calories: 500))
        model.setGoal(2_400)

        let incoming = AppBackup(
            meals: [Meal(name: "Otra", suggestedSlot: .dinner, calories: 300)],
            ingredients: [CatalogIngredient(name: "Huevo", calories: 143)],
            plan: nil, dailyCalorieGoal: 1_500
        )
        model.importBackup(from: try JSONEncoder().encode(incoming), mode: .merge)
        #expect(model.meals.contains { $0.name == "Mi receta" })
        #expect(model.meals.contains { $0.name == "Otra" })
        #expect(model.catalog.count == 1)
        #expect(model.goal == 2_400)
    }

    @Test("Importar reemplazando sustituye todo")
    func importReplaceOverwritesEverything() throws {
        let (model, store, _) = make()
        let incoming = AppBackup(meals: [Meal(name: "Única", suggestedSlot: .lunch, calories: 1)], ingredients: [], plan: nil, dailyCalorieGoal: 1_700)
        model.importBackup(from: try JSONEncoder().encode(incoming), mode: .replace)
        #expect(model.meals.map(\.name) == ["Única"])
        #expect(model.goal == 1_700)
        #expect(store.goal == 1_700)
    }

    @Test("Una copia inválida no cambia nada")
    func invalidBackupChangesNothing() throws {
        let (model, _, _) = make()
        let before = model.meals
        model.importBackup(from: Data("no es json".utf8), mode: .replace)
        #expect(model.meals == before)
        #expect(model.message?.contains("No se pudo importar") == true)

        let wrongVersion = AppBackup(meals: [], ingredients: [], plan: nil, dailyCalorieGoal: 2_000, version: 42)
        model.importBackup(from: try JSONEncoder().encode(wrongVersion), mode: .replace)
        #expect(model.meals == before)
    }

    @Test("Si falla la escritura al importar se restauran los datos anteriores")
    func importRollsBackOnFailure() throws {
        let store = InMemoryStore()
        let (model, _, _) = make(store: store)
        let before = model.meals
        store.failSaves = true
        let incoming = AppBackup(meals: [Meal(name: "Nueva", suggestedSlot: .lunch, calories: 1)], ingredients: [], plan: nil, dailyCalorieGoal: 1_700)
        model.importBackup(from: try JSONEncoder().encode(incoming), mode: .replace)
        #expect(model.meals == before)
        #expect(model.goal == 2_000)
    }

    @Test("Avisa de copia antigua o inexistente")
    func staleBackupWarning() throws {
        let clock = Date()
        let (model, _, _) = make(now: clock)
        #expect(!model.isBackupStale)                       // sin datos propios no molesta
        try model.saveCatalogIngredient(CatalogIngredient(name: "Huevo", calories: 143))
        #expect(model.isBackupStale)                        // tiene datos y nunca hizo copia
        model.markBackupExported()
        #expect(!model.isBackupStale)

        let (later, _, _) = make(now: clock.addingTimeInterval(20 * 86_400))
        try later.saveCatalogIngredient(CatalogIngredient(name: "Huevo", calories: 143))
        later.markBackupExported()
        #expect(!later.isBackupStale)
    }

    // MARK: Recordatorios y carga

    @Test("Activar el recordatorio sin permiso muestra un aviso y lo deja desactivado")
    func remindersWithoutPermission() async {
        let reminders = FakeReminders()
        reminders.result = false
        let (model, _, _) = make(reminders: reminders)
        await model.setRemindersEnabled(true)
        #expect(!model.remindersEnabled)
        #expect(model.message != nil)

        reminders.result = true
        model.message = nil
        await model.setRemindersEnabled(true)
        #expect(model.remindersEnabled)
        #expect(reminders.lastRequest == true)
    }

    @Test("Si un dato no se puede leer usa valores por defecto y avisa")
    func loadFailureFallsBack() {
        let store = InMemoryStore()
        store.failLoads = true
        let (model, _, _) = make(store: store)
        #expect(model.meals == SampleMeals.all)
        #expect(model.message?.contains(".corrupt") == true)
    }
}
