//
//  OptionsTests.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-11
//  Plataforma: macOS / iOS · Swift Testing
//  Descripción: Pruebas de los ingredientes variables (grupos de opciones elegidas al azar en el menú) y de las raciones por toma.
//

import Foundation
import Testing
@testable import AppComidaCore

/// Datos de prueba para ingredientes variables.
enum OptionFixtures {
    /// Opciones del grupo "Untado" con sus calorías (receta completa).
    static func spreadGroup() -> MealOptionGroup {
        func option(_ name: String, _ grams: Double, _ kcal: Int) -> MealOption {
            MealOption(ingredient: Ingredient(name: name, quantity: "\(grams) g", catalogID: UUID(), grams: grams), calories: kcal)
        }
        return MealOptionGroup(name: "Untado", options: [
            option("Chocolate", 20, 108),
            option("Mermelada", 25, 49),
            option("Queso de untar", 30, 39),
            option("Jamón", 30, 30)
        ])
    }

    /// Una comida por franja; el desayuno son unas tortitas de 111 kcal con el grupo de opciones.
    /// Con las demás comidas (700 + 250 + 600) el día suma 1661 kcal más la opción elegida.
    static func dayMeals(plannedServings: Double = 1) -> (meals: [Meal], pancakes: Meal) {
        let pancakes = Meal(
            name: "Tortitas", suggestedSlot: .breakfast, calories: 111,
            optionGroups: [spreadGroup()], plannedServings: plannedServings
        )
        let meals = [
            pancakes,
            Fixtures.meal("Pasta", .lunch, 700),
            Fixtures.meal("Fruta", .snack, 250),
            Fixtures.meal("Salmón", .dinner, 600)
        ]
        return (meals, pancakes)
    }
}

@Suite("Ingredientes variables")
struct OptionsTests {
    private func generator(tolerance: Int = 150, seed: UInt64 = 5) -> MenuGenerator {
        MenuGenerator(calendar: Fixtures.calendar, tolerance: tolerance, seed: seed)
    }

    @Test("Cada día de tortitas lleva una opción elegida del grupo")
    func everyPlannedMealHasAChoice() throws {
        let (meals, pancakes) = OptionFixtures.dayMeals()
        let plan = try generator().generate(weekStarting: Fixtures.monday, meals: meals, dailyGoal: 1_700, locked: []).get()
        let group = try #require(pancakes.optionGroups.first)
        for planned in plan.meals where planned.mealID == pancakes.id {
            #expect(planned.choices.count == 1)
            #expect(planned.choices.first?.groupID == group.id)
            #expect(pancakes.chosenOptions(for: planned.choices).count == 1)
        }
        #expect(plan.meals.filter { $0.mealID != pancakes.id }.allSatisfy { $0.choices.isEmpty })
    }

    @Test("Reparte las opciones a lo largo de la semana")
    func spreadsOptionsAcrossTheWeek() throws {
        let (meals, pancakes) = OptionFixtures.dayMeals()
        // Con este objetivo las cuatro opciones caben dentro de la tolerancia, así que manda la variedad.
        let plan = try generator().generate(weekStarting: Fixtures.monday, meals: meals, dailyGoal: 1_700, locked: []).get()
        let chosen = plan.meals.filter { $0.mealID == pancakes.id }.flatMap { $0.choices.map(\.optionID) }
        #expect(chosen.count == 7)
        let counts = Dictionary(grouping: chosen, by: { $0 }).mapValues(\.count)
        #expect(counts.count == 4)
        #expect((counts.values.max() ?? 0) - (counts.values.min() ?? 0) <= 1)
    }

    @Test("Prefiere la opción que ajusta el día al objetivo")
    func prefersOptionThatFitsTheGoal() throws {
        let (meals, pancakes) = OptionFixtures.dayMeals()
        // 1661 + 108 = 1769: solo el chocolate queda a menos de 10 kcal del objetivo.
        let plan = try generator(tolerance: 10).generate(weekStarting: Fixtures.monday, meals: meals, dailyGoal: 1_769, locked: []).get()
        let chocolate = try #require(pancakes.optionGroups.first?.options.first)
        let chosen = plan.meals.filter { $0.mealID == pancakes.id }.flatMap { $0.choices.map(\.optionID) }
        #expect(chosen.allSatisfy { $0 == chocolate.id })
        for day in plan.days(calendar: Fixtures.calendar) {
            let total = day.meals.reduce(0) { sum, planned in
                sum + (meals.first { $0.id == planned.mealID }?.calories(for: planned) ?? 0)
            }
            #expect(abs(total - 1_769) <= 10)
        }
    }

    @Test("Si el día no llega al objetivo, las opciones siguen variando")
    func variesEvenWhenGoalIsUnreachable() throws {
        let (meals, pancakes) = OptionFixtures.dayMeals()
        // El día solo suma unas 1700 kcal: ninguna opción llega a 3000, pero deben repartirse en vez de repetir la más calórica.
        let plan = try generator().generate(weekStarting: Fixtures.monday, meals: meals, dailyGoal: 3_000, locked: []).get()
        let chosen = plan.meals.filter { $0.mealID == pancakes.id }.flatMap { $0.choices.map(\.optionID) }
        #expect(Set(chosen).count == 4)
    }

    @Test("El mismo resultado con la misma semilla")
    func reproducibleWithSeed() throws {
        let (meals, _) = OptionFixtures.dayMeals()
        let first = try generator(seed: 9).generate(weekStarting: Fixtures.monday, meals: meals, dailyGoal: 1_700, locked: []).get()
        let second = try generator(seed: 9).generate(weekStarting: Fixtures.monday, meals: meals, dailyGoal: 1_700, locked: []).get()
        #expect(first == second)
    }

    @Test("Una comida bloqueada conserva su opción")
    func lockedMealKeepsItsChoice() throws {
        let (meals, pancakes) = OptionFixtures.dayMeals()
        let group = try #require(pancakes.optionGroups.first)
        let ham = try #require(group.options.last)
        let wednesday = Fixtures.calendar.date(byAdding: .day, value: 2, to: Fixtures.monday)!
        let locked = PlannedMeal(
            date: wednesday, slot: .breakfast, mealID: pancakes.id, isLocked: true,
            choices: [OptionChoice(groupID: group.id, optionID: ham.id)]
        )
        let plan = try generator().generate(weekStarting: Fixtures.monday, meals: meals, dailyGoal: 1_700, locked: [locked]).get()
        let kept = try #require(plan.meals.first { Fixtures.calendar.isDate($0.date, inSameDayAs: wednesday) && $0.slot == .breakfast })
        #expect(kept.choices == locked.choices)
        #expect(kept.isLocked)
    }

    @Test("Usa las raciones por toma de cada receta")
    func usesPlannedServings() throws {
        let (meals, pancakes) = OptionFixtures.dayMeals(plannedServings: 2)
        let plan = try generator().generate(weekStarting: Fixtures.monday, meals: meals, dailyGoal: 2_000, locked: []).get()
        #expect(plan.meals.filter { $0.mealID == pancakes.id }.allSatisfy { $0.servings == 2 })
        #expect(plan.meals.filter { $0.mealID != pancakes.id }.allSatisfy { $0.servings == 1 })
    }

    @Test("Calorías de una comida planificada: base, opción y raciones")
    func caloriesForPlannedMeal() throws {
        let (_, pancakes) = OptionFixtures.dayMeals()
        let group = try #require(pancakes.optionGroups.first)
        let chocolate = try #require(group.options.first)
        let planned = PlannedMeal(
            date: Fixtures.monday, slot: .breakfast, mealID: pancakes.id, servings: 2,
            choices: [OptionChoice(groupID: group.id, optionID: chocolate.id)]
        )
        #expect(pancakes.calories(for: planned) == (111 + 108) * 2)
        let withoutChoice = PlannedMeal(date: Fixtures.monday, slot: .breakfast, mealID: pancakes.id)
        #expect(pancakes.calories(for: withoutChoice) == 111)
        // Esperadas: base más la media de las opciones (misma cantidad para un día cualquiera).
        #expect(pancakes.expectedCalories == 111 + Int((Double(108 + 49 + 39 + 30) / 4).rounded()))
    }

    @Test("La lista de la compra incluye la opción elegida de cada día")
    func shoppingListIncludesChosenOptions() throws {
        let (_, pancakes) = OptionFixtures.dayMeals()
        let group = try #require(pancakes.optionGroups.first)
        let chocolate = group.options[0]
        let jam = group.options[1]
        func planned(_ day: Int, _ option: MealOption) -> PlannedMeal {
            PlannedMeal(
                date: Fixtures.calendar.date(byAdding: .day, value: day, to: Fixtures.monday)!,
                slot: .breakfast, mealID: pancakes.id,
                choices: [OptionChoice(groupID: group.id, optionID: option.id)]
            )
        }
        let plan = WeeklyPlan(weekStart: Fixtures.monday, meals: [planned(0, chocolate), planned(1, chocolate), planned(2, jam)])
        let list = ShoppingListBuilder.build(plan: plan, meals: [pancakes])
        #expect(list.first { $0.name == "Chocolate" }?.quantityText == "40 g")
        #expect(list.first { $0.name == "Mermelada" }?.quantityText == "25 g")
        #expect(list.contains { $0.name == "Jamón" } == false)
    }

    @Test("Recalcular actualiza las calorías de las opciones con el catálogo")
    func recalculatesOptions() {
        let jam = CatalogIngredient(name: "Mermelada", calories: 200, protein: 0.5, carbohydrates: 50, fat: 0)
        let milk = CatalogIngredient(name: "Leche", calories: 64)
        let group = MealOptionGroup(name: "Untado", options: [
            MealOption(ingredient: Ingredient(name: "Mermelada", quantity: "", catalogID: jam.id, grams: 25)),
            MealOption(ingredient: Ingredient(name: "Leche", quantity: "", catalogID: milk.id, grams: 100))
        ])
        let meal = Meal(name: "Tortitas", suggestedSlot: .breakfast, calories: 1, optionGroups: [group])
        let updated = RecipeCalculator.recalculated(meal, catalog: [jam, milk])
        let options = updated.optionGroups[0].options
        #expect(options[0].calories == 50)
        #expect(options[0].nutrition.carbohydrates == 12.5)
        #expect(options[1].calories == 64)
        #expect(options[1].nutrition == Nutrition())
    }

    @Test("Validación de los grupos de opciones")
    func validatesGroups() {
        let oats = CatalogIngredient(name: "Avena", calories: 370)
        let jam = CatalogIngredient(name: "Mermelada", calories: 200)
        func option(_ item: CatalogIngredient, grams: Double = 20) -> MealOption {
            MealOption(ingredient: Ingredient(name: item.name, quantity: "", catalogID: item.id, grams: grams))
        }
        func meal(_ groups: [MealOptionGroup], planned: Double = 1) -> Meal {
            Meal(
                name: "A", suggestedSlot: .breakfast, calories: 1,
                ingredients: [Ingredient(name: "Avena", quantity: "", catalogID: oats.id, grams: 50)],
                optionGroups: groups, plannedServings: planned
            )
        }
        let catalog = [oats, jam]
        let valid = MealOptionGroup(name: "Untado", options: [option(oats), option(jam)])
        #expect(MealValidator.validate(meal([valid]), catalog: catalog) == nil)
        #expect(MealValidator.validate(meal([MealOptionGroup(name: " ", options: valid.options)]), catalog: catalog) != nil)
        #expect(MealValidator.validate(meal([MealOptionGroup(name: "Untado", options: [option(jam)])]), catalog: catalog) != nil)
        #expect(MealValidator.validate(meal([MealOptionGroup(name: "Untado", options: [option(jam), option(oats, grams: 0)])]), catalog: catalog) != nil)
        #expect(MealValidator.validate(meal([valid], planned: 0), catalog: catalog) != nil)
        #expect(MealValidator.validate(meal([valid], planned: 7), catalog: catalog) != nil)
    }

    @Test("Los datos antiguos se leen sin grupos ni elecciones")
    func decodesLegacyData() throws {
        let legacyMeal = """
        {"id":"11111111-1111-1111-1111-111111111111","name":"Avena","mealSlots":["breakfast"],"calories":420,
         "nutrition":{"protein":1,"carbohydrates":2,"fat":3},"ingredients":[],"steps":[]}
        """
        let meal = try JSONDecoder().decode(Meal.self, from: Data(legacyMeal.utf8))
        #expect(meal.optionGroups.isEmpty)
        #expect(meal.plannedServings == 1)

        let planned = try JSONDecoder().decode(
            PlannedMeal.self,
            from: Data(#"{"date":0,"slot":"lunch","mealID":"11111111-1111-1111-1111-111111111111"}"#.utf8)
        )
        #expect(planned.choices.isEmpty)
    }

    @Test("Los grupos y las elecciones sobreviven a un ciclo de codificación")
    func roundTrips() throws {
        let (_, pancakes) = OptionFixtures.dayMeals(plannedServings: 1.5)
        let decoded = try JSONDecoder().decode(Meal.self, from: JSONEncoder().encode(pancakes))
        #expect(decoded == pancakes)
        let group = try #require(pancakes.optionGroups.first)
        let planned = PlannedMeal(
            date: Fixtures.monday, slot: .breakfast, mealID: pancakes.id,
            choices: [OptionChoice(groupID: group.id, optionID: group.options[2].id)]
        )
        #expect(try JSONDecoder().decode(PlannedMeal.self, from: JSONEncoder().encode(planned)) == planned)
    }

    @Test("Combinar copias reapunta las opciones al catálogo actual")
    func mergeRemapsOptions() {
        let myJam = CatalogIngredient(name: "Mermelada", calories: 200)
        let theirJam = CatalogIngredient(name: "mermelada", calories: 190)
        let group = MealOptionGroup(name: "Untado", options: [
            MealOption(ingredient: Ingredient(name: "Mermelada", quantity: "", catalogID: theirJam.id, grams: 20)),
            MealOption(ingredient: Ingredient(name: "Otra", quantity: "", catalogID: UUID(), grams: 20))
        ])
        let incomingMeal = Meal(name: "Tortitas", suggestedSlot: .breakfast, calories: 1, optionGroups: [group])
        let current = AppBackup(meals: [], ingredients: [myJam], plan: nil, dailyCalorieGoal: 2_000)
        let incoming = AppBackup(meals: [incomingMeal], ingredients: [theirJam], plan: nil, dailyCalorieGoal: 1_500)
        let merged = BackupService.merge(current: current, incoming: incoming)
        let options = merged.meals.first?.optionGroups.first?.options
        #expect(options?.first?.ingredient.catalogID == myJam.id)
    }
}

@MainActor
@Suite("Ingredientes variables en el ViewModel")
struct OptionsViewModelTests {
    private func makeModel(meals: [Meal]) -> (AppViewModel, InMemoryStore) {
        let store = InMemoryStore()
        store.meals = meals
        let model = AppViewModel(
            store: store,
            generator: MenuGenerator(calendar: Fixtures.calendar, seed: 4),
            reminders: FakeReminders(),
            defaults: UserDefaults(suiteName: "appcomida-tests-\(UUID().uuidString)")!,
            calendar: Fixtures.calendar,
            now: { Fixtures.monday }
        )
        return (model, store)
    }

    @Test("Cambiar la opción de una comida del plan actualiza las calorías del día")
    func changingChoiceUpdatesCalories() throws {
        let (meals, pancakes) = OptionFixtures.dayMeals()
        let (model, store) = makeModel(meals: meals)
        model.generatePlan()
        let planned = try #require(model.plan?.meals.first { $0.mealID == pancakes.id })
        let group = try #require(pancakes.optionGroups.first)
        let chocolate = group.options[0]
        let ham = group.options[3]

        model.setChoice(planned: planned.id, group: group.id, option: chocolate.id)
        #expect(model.calories(of: model.plannedMeal(withID: planned.id)!) == 111 + 108)
        model.setChoice(planned: planned.id, group: group.id, option: ham.id)
        #expect(model.calories(of: model.plannedMeal(withID: planned.id)!) == 111 + 30)
        #expect(model.plannedMeal(withID: planned.id)?.choices.count == 1)
        #expect(store.plan?.meals.first { $0.id == planned.id }?.choices.first?.optionID == ham.id)
    }

    @Test("Cambiar de comida reinicia las raciones y las opciones")
    func replacingMealResetsServingsAndChoices() throws {
        var (meals, pancakes) = OptionFixtures.dayMeals()
        let alternative = Meal(name: "Gachas", suggestedSlot: .breakfast, calories: 300, optionGroups: [OptionFixtures.spreadGroup()], plannedServings: 1.5)
        meals.append(alternative)
        let (model, _) = makeModel(meals: meals)
        model.generatePlan()
        let planned = try #require(model.plan?.meals.first { $0.slot == .breakfast })

        model.replaceMeal(planned: planned.id, with: alternative.id)
        let updated = try #require(model.plannedMeal(withID: planned.id))
        #expect(updated.mealID == alternative.id)
        #expect(updated.servings == 1.5)
        #expect(updated.choices == [OptionChoice(groupID: alternative.optionGroups[0].id, optionID: alternative.optionGroups[0].options[0].id)])
        _ = pancakes
    }

    @Test("No se puede eliminar un ingrediente usado como opción")
    func usedAsOptionCannotBeDeleted() throws {
        let jam = CatalogIngredient(name: "Mermelada", calories: 200)
        let group = MealOptionGroup(name: "Untado", options: [
            MealOption(ingredient: Ingredient(name: "Mermelada", quantity: "", catalogID: jam.id, grams: 20)),
            MealOption(ingredient: Ingredient(name: "Otra", quantity: "", catalogID: UUID(), grams: 20))
        ])
        let meal = Meal(name: "Tortitas", suggestedSlot: .breakfast, calories: 100, optionGroups: [group])
        let (model, _) = makeModel(meals: [meal])
        try model.saveCatalogIngredient(jam)

        #expect(model.usageCount(of: jam) == 1)
        model.deleteCatalogIngredient(jam)
        #expect(model.catalog.contains { $0.id == jam.id })
        #expect(model.message?.contains("1 comida") == true)
    }
}
