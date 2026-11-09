//
//  ModelsAndBackupTests.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: macOS / iOS · Swift Testing
//  Descripción: Pruebas de los modelos (compatibilidad con datos antiguos), del cálculo de recetas, de las copias de seguridad y del almacén en disco.
//

import Foundation
import Testing
@testable import AppComidaCore

@Suite("Modelos y compatibilidad")
struct ModelsTests {
    @Test("Lee datos antiguos sin los campos nuevos")
    func decodesLegacyData() throws {
        let legacyMeal = """
        {"id":"11111111-1111-1111-1111-111111111111","name":"Avena","suggestedSlot":"breakfast","calories":420,
         "nutrition":{"protein":1,"carbohydrates":2,"fat":3},"ingredients":[],"steps":[]}
        """
        let meal = try JSONDecoder().decode(Meal.self, from: Data(legacyMeal.utf8))
        #expect(meal.mealSlots == [.breakfast])
        #expect(meal.servings == 1)
        #expect(meal.isFavorite == false)

        let legacyPlanned = """
        {"date":0,"slot":"lunch","mealID":"11111111-1111-1111-1111-111111111111"}
        """
        let planned = try JSONDecoder().decode(PlannedMeal.self, from: Data(legacyPlanned.utf8))
        #expect(planned.servings == 1)
        #expect(planned.isLocked == false)

        let legacyIngredient = """
        {"id":"22222222-2222-2222-2222-222222222222","name":"Avena","calories":370,"calorieUnit":"per100Grams"}
        """
        let catalog = try JSONDecoder().decode(CatalogIngredient.self, from: Data(legacyIngredient.utf8))
        #expect(catalog.protein == nil)
        #expect(catalog.unitWeightGrams == nil)
        #expect(catalog.macrosPer100g == nil)
    }

    @Test("Los datos nuevos sobreviven a un ciclo de codificación")
    func roundTrips() throws {
        let planned = PlannedMeal(date: Fixtures.monday, slot: .dinner, mealID: UUID(), servings: 0.5, isLocked: true)
        let decoded = try JSONDecoder().decode(PlannedMeal.self, from: JSONEncoder().encode(planned))
        #expect(decoded == planned)
    }

    @Test("Raciones: calorías y macronutrientes por ración")
    func perServingValues() {
        let meal = Meal(name: "A", suggestedSlot: .lunch, calories: 900, servings: 3, nutrition: Nutrition(protein: 30, carbohydrates: 60, fat: 15))
        #expect(meal.caloriesPerServing == 300)
        #expect(meal.nutritionPerServing == Nutrition(protein: 10, carbohydrates: 20, fat: 5))
    }

    @Test("El plan agrupa por día, ordena las franjas y reconoce la semana actual")
    func planHelpers() {
        let id = UUID()
        let tuesday = Fixtures.calendar.date(byAdding: .day, value: 1, to: Fixtures.monday)!
        let plan = WeeklyPlan(weekStart: Fixtures.monday, meals: [
            PlannedMeal(date: tuesday, slot: .dinner, mealID: id),
            PlannedMeal(date: Fixtures.monday, slot: .snack, mealID: id),
            PlannedMeal(date: Fixtures.monday, slot: .breakfast, mealID: id)
        ])
        let days = plan.days(calendar: Fixtures.calendar)
        #expect(days.count == 2)
        #expect(days[0].meals.map(\.slot) == [.breakfast, .snack])
        #expect(plan.isCurrent(on: tuesday, calendar: Fixtures.calendar))
        let nextWeek = Fixtures.calendar.date(byAdding: .day, value: 8, to: Fixtures.monday)!
        #expect(!plan.isCurrent(on: nextWeek, calendar: Fixtures.calendar))
    }

    @Test("Editar una comida del plan por su identificador")
    func updatesPlannedMeal() {
        var plan = WeeklyPlan(weekStart: Fixtures.monday, meals: [PlannedMeal(date: Fixtures.monday, slot: .lunch, mealID: UUID())])
        let id = plan.meals[0].id
        #expect(plan.update(id) { $0.servings = 2 })
        #expect(plan.meals[0].servings == 2)
        #expect(!plan.update("no-existe") { $0.servings = 3 })
    }
}

@Suite("RecipeCalculator")
struct RecipeCalculatorTests {
    private let oats = CatalogIngredient(name: "Avena", calories: 370, protein: 13, carbohydrates: 60, fat: 7)
    private let oil = CatalogIngredient(name: "Aceite", calories: 880)

    @Test("Calcula las calorías por gramos")
    func calories() {
        let ingredients = [Ingredient(name: "Avena", quantity: "", catalogID: oats.id, grams: 50)]
        #expect(RecipeCalculator.calories(of: ingredients, catalog: [oats]) == 185)
    }

    @Test("Calcula macronutrientes solo si todos los ingredientes los tienen")
    func nutrition() {
        let complete = [Ingredient(name: "Avena", quantity: "", catalogID: oats.id, grams: 200)]
        #expect(RecipeCalculator.nutrition(of: complete, catalog: [oats]) == Nutrition(protein: 26, carbohydrates: 120, fat: 14))

        let incomplete = complete + [Ingredient(name: "Aceite", quantity: "", catalogID: oil.id, grams: 10)]
        #expect(RecipeCalculator.nutrition(of: incomplete, catalog: [oats, oil]) == nil)
    }

    @Test("Recalcular actualiza las calorías de la comida con el catálogo nuevo")
    func recalculates() {
        let meal = Meal(name: "A", suggestedSlot: .breakfast, calories: 1, ingredients: [Ingredient(name: "Avena", quantity: "", catalogID: oats.id, grams: 100)])
        let updated = RecipeCalculator.recalculated(meal, catalog: [oats])
        #expect(updated.calories == 370)
        #expect(updated.nutrition.protein == 13)

        let unresolved = RecipeCalculator.recalculated(meal, catalog: [])
        #expect(unresolved.calories == 1)
    }

    @Test("Unidades equivalentes a unos gramos")
    func units() {
        let egg = CatalogIngredient(name: "Huevo", calories: 143, unitWeightGrams: 60)
        #expect(RecipeCalculator.units(forGrams: 180, of: egg) == 3)
        #expect(RecipeCalculator.units(forGrams: 180, of: oats) == nil)
    }
}

@Suite("BackupService")
struct BackupServiceTests {
    private func backup(meals: [Meal] = [], ingredients: [CatalogIngredient] = [], goal: Int = 2_000, extras: ShoppingExtras? = nil, version: Int = AppBackup.currentVersion) -> AppBackup {
        AppBackup(meals: meals, ingredients: ingredients, plan: nil, dailyCalorieGoal: goal, extras: extras, version: version)
    }

    @Test("Valida la versión y el objetivo")
    func validates() throws {
        try BackupService.validate(backup())
        #expect(throws: BackupError.unsupportedVersion(99)) { try BackupService.validate(backup(version: 99)) }
        #expect(throws: BackupError.invalidData) { try BackupService.validate(backup(goal: 0)) }
    }

    @Test("Combinar conserva lo actual y añade lo nuevo por nombre")
    func mergeKeepsCurrentAndAddsNew() {
        let myOats = CatalogIngredient(name: "Avena", calories: 370)
        let myMeal = Meal(name: "Mi receta", suggestedSlot: .lunch, calories: 500)
        let current = backup(meals: [myMeal], ingredients: [myOats], goal: 2_400)

        let importedOats = CatalogIngredient(name: "avena", calories: 999, protein: 13, carbohydrates: 60, fat: 7, unitWeightGrams: 30, category: .bakeryCereals)
        let milk = CatalogIngredient(name: "Leche", calories: 64)
        let importedMeal = Meal(
            name: "Gachas", suggestedSlot: .breakfast, calories: 300,
            ingredients: [Ingredient(name: "Avena", quantity: "", catalogID: importedOats.id, grams: 50)]
        )
        let merged = BackupService.merge(current: current, incoming: backup(meals: [importedMeal], ingredients: [importedOats, milk], goal: 1_500))

        #expect(merged.dailyCalorieGoal == 2_400)
        #expect(merged.ingredients.count == 2)
        #expect(merged.meals.count == 2)

        let oats = merged.ingredients.first { $0.name == "Avena" }
        #expect(oats?.id == myOats.id)
        #expect(oats?.calories == 370)
        #expect(oats?.protein == 13)
        #expect(oats?.unitWeightGrams == 30)
        #expect(oats?.category == .bakeryCereals)

        let porridge = merged.meals.first { $0.name == "Gachas" }
        #expect(porridge?.ingredients.first?.catalogID == myOats.id)
    }

    @Test("Combinar no duplica comidas ni productos manuales con el mismo nombre")
    func mergeDoesNotDuplicate() {
        let meal = Meal(name: "Tortilla", suggestedSlot: .dinner, calories: 400)
        let current = backup(meals: [meal], extras: ShoppingExtras(manualItems: [ManualShoppingItem(name: "Pilas")], pantryKeys: ["sal"]))
        let incoming = backup(
            meals: [Meal(name: "TORTILLA", suggestedSlot: .dinner, calories: 1)],
            extras: ShoppingExtras(manualItems: [ManualShoppingItem(name: "pilas"), ManualShoppingItem(name: "Bolsas")], pantryKeys: ["sal", "aceite"])
        )
        let merged = BackupService.merge(current: current, incoming: incoming)
        #expect(merged.meals.count == 1)
        #expect(merged.extras?.manualItems.map(\.name).sorted() == ["Bolsas", "Pilas"])
        #expect(merged.extras?.pantryKeys == ["aceite", "sal"])
    }
}

@Suite("FileMealStore")
struct FileMealStoreTests {
    private func makeStore() -> (FileMealStore, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("appcomida-tests-\(UUID().uuidString)")
        return (FileMealStore(directory: url), url)
    }

    @Test("Devuelve valores por defecto cuando no hay archivos")
    func defaults() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try store.loadMeals() == SampleMeals.all)
        #expect(try store.loadIngredients().isEmpty)
        #expect(try store.loadPlan() == nil)
        #expect(try store.loadDailyCalorieGoal() == 2_000)
        #expect(try store.loadShoppingExtras() == ShoppingExtras())
    }

    @Test("Guarda y vuelve a cargar cada tipo de dato")
    func roundTrip() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let meal = Meal(name: "A", suggestedSlot: .lunch, calories: 500, isFavorite: true)
        let ingredient = CatalogIngredient(name: "Huevo", calories: 143, protein: 12.6, carbohydrates: 0.7, fat: 9.5, unitWeightGrams: 60, category: .dairyEggs)
        let plan = WeeklyPlan(weekStart: Fixtures.monday, meals: [PlannedMeal(date: Fixtures.monday, slot: .lunch, mealID: meal.id, servings: 2, isLocked: true)])
        let extras = ShoppingExtras(manualItems: [ManualShoppingItem(name: "Pilas")], pantryKeys: ["sal"], checkedKeys: ["x|y"])

        try store.saveMeals([meal])
        try store.saveIngredients([ingredient])
        try store.savePlan(plan)
        try store.saveDailyCalorieGoal(2_300)
        try store.saveShoppingExtras(extras)

        #expect(try store.loadMeals() == [meal])
        #expect(try store.loadIngredients() == [ingredient])
        #expect(try store.loadPlan() == plan)
        #expect(try store.loadDailyCalorieGoal() == 2_300)
        #expect(try store.loadShoppingExtras() == extras)

        try store.deletePlan()
        #expect(try store.loadPlan() == nil)
    }
}

@Suite("Validación")
struct ValidationTests {
    private let oats = CatalogIngredient(name: "Avena", calories: 370)

    private func meal(name: String = "A", slots: [MealSlot] = [.lunch], grams: Double? = 50, servings: Int = 1, useCatalog: Bool = true) -> Meal {
        Meal(
            name: name, suggestedSlot: .lunch, mealSlots: slots, calories: 1, servings: servings,
            ingredients: [Ingredient(name: "Avena", quantity: "", catalogID: useCatalog ? oats.id : UUID(), grams: grams)]
        )
    }

    @Test("Acepta una comida correcta")
    func acceptsValidMeal() {
        #expect(MealValidator.validate(meal(), catalog: [oats]) == nil)
    }

    @Test("Rechaza comidas incompletas")
    func rejectsInvalidMeals() {
        #expect(MealValidator.validate(meal(name: "  "), catalog: [oats]) != nil)
        #expect(MealValidator.validate(meal(slots: []), catalog: [oats]) != nil)
        #expect(MealValidator.validate(meal(grams: 0), catalog: [oats]) != nil)
        #expect(MealValidator.validate(meal(grams: nil), catalog: [oats]) != nil)
        #expect(MealValidator.validate(meal(servings: 0), catalog: [oats]) != nil)
        #expect(MealValidator.validate(meal(useCatalog: false), catalog: [oats]) != nil)
        #expect(MealValidator.validate(Meal(name: "A", suggestedSlot: .lunch, calories: 1), catalog: [oats]) != nil)
    }

    @Test("Valida ingredientes del catálogo")
    func validatesCatalogIngredients() {
        #expect(CatalogIngredientValidator.validate(oats) == nil)
        #expect(CatalogIngredientValidator.validate(CatalogIngredient(name: "", calories: 10)) != nil)
        #expect(CatalogIngredientValidator.validate(CatalogIngredient(name: "A", calories: 0)) != nil)
        #expect(CatalogIngredientValidator.validate(CatalogIngredient(name: "A", calories: 10, protein: -1)) != nil)
        #expect(CatalogIngredientValidator.validate(CatalogIngredient(name: "A", calories: 10, unitWeightGrams: 0)) != nil)
    }
}

@Suite("Datos dañados")
struct CorruptDataTests {
    @Test("Aparta el archivo ilegible en lugar de sobrescribirlo")
    func quarantinesCorruptFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("appcomida-corrupt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileMealStore(directory: url)
        try Data("esto no es json".utf8).write(to: url.appendingPathComponent("meals.json"))

        #expect(throws: DecodingError.self) { try store.loadMeals() }
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("meals.json.corrupt").path))
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathComponent("meals.json").path))
        #expect(try store.loadMeals() == SampleMeals.all)
    }
}

@Suite("Archivo de ingredientes")
struct ImportFileTests {
    @Test("ingredientes-importar.json es una copia válida y completa")
    func bundledIngredientsFileIsValid() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("ingredientes-importar.json"))
        let backup = try JSONDecoder().decode(AppBackup.self, from: data)
        try BackupService.validate(backup)

        #expect(backup.ingredients.count > 100)
        #expect(Set(backup.ingredients.map(\.id)).count == backup.ingredients.count)
        #expect(Set(backup.ingredients.map { $0.name.searchKey }).count == backup.ingredients.count)
        for ingredient in backup.ingredients {
            #expect(CatalogIngredientValidator.validate(ingredient) == nil, "\(ingredient.name)")
            #expect(ingredient.macrosPer100g != nil, "\(ingredient.name)")
            #expect(ingredient.category != nil, "\(ingredient.name)")
        }
        let egg = backup.ingredients.first { $0.name == "Huevo entero" }
        #expect(egg?.unitWeightGrams == 60)
    }
}
