//
//  ShoppingListTests.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: macOS / iOS · Swift Testing
//  Descripción: Pruebas de la lista de la compra: suma de cantidades, conversión de unidades, raciones, unidades por peso y secciones.
//

import Foundation
import Testing
@testable import AppComidaCore

@Suite("ShoppingListBuilder")
struct ShoppingListTests {
    private let date = Fixtures.monday

    private func plan(_ entries: [(Meal, Double)]) -> WeeklyPlan {
        WeeklyPlan(
            weekStart: date,
            meals: entries.enumerated().map { index, entry in
                PlannedMeal(
                    date: Fixtures.calendar.date(byAdding: .day, value: index, to: date)!,
                    slot: .lunch, mealID: entry.0.id, servings: entry.1
                )
            }
        )
    }

    private func item(_ name: String, in list: [ShoppingItem]) -> ShoppingItem? {
        list.first { $0.id == name.searchKey }
    }

    @Test("Suma el mismo ingrediente de varias comidas sin distinguir tildes ni mayúsculas")
    func sumsAcrossMeals() {
        let a = Meal(name: "A", suggestedSlot: .lunch, calories: 1, ingredients: [Ingredient(name: "Plátano", quantity: "100 g", grams: 100)])
        let b = Meal(name: "B", suggestedSlot: .lunch, calories: 1, ingredients: [Ingredient(name: "platano", quantity: "250 g", grams: 250)])
        let list = ShoppingListBuilder.build(plan: plan([(a, 1), (b, 1)]), meals: [a, b])
        #expect(list.count == 1)
        #expect(list.first?.quantityText == "350 g")
    }

    @Test("Convierte kilos y pasa a kg a partir de 1000 g")
    func convertsKilograms() {
        let meal = Meal(name: "A", suggestedSlot: .lunch, calories: 1, ingredients: [Ingredient(name: "Arroz", quantity: "1 kg")])
        let list = ShoppingListBuilder.build(plan: plan([(meal, 1), (meal, 1)]), meals: [meal])
        #expect(list.first?.quantityText == "2 kg")
    }

    @Test("Divide la receta entre sus raciones y multiplica por las raciones planificadas")
    func scalesByServings() {
        let meal = Meal(name: "A", suggestedSlot: .lunch, calories: 1, servings: 4, ingredients: [Ingredient(name: "Pasta", quantity: "400 g", grams: 400)])
        let list = ShoppingListBuilder.build(plan: plan([(meal, 1), (meal, 2)]), meals: [meal])
        #expect(list.first?.quantityText == "300 g")
    }

    @Test("Muestra unidades cuando el catálogo da el peso por unidad")
    func usesUnitWeight() {
        let egg = CatalogIngredient(name: "Huevo", calories: 143, unitWeightGrams: 60, category: .dairyEggs)
        let meal = Meal(
            name: "Tortilla", suggestedSlot: .dinner, calories: 1,
            ingredients: [Ingredient(name: "Huevo", quantity: "120 g", catalogID: egg.id, grams: 120)]
        )
        let list = ShoppingListBuilder.build(plan: plan([(meal, 1), (meal, 1), (meal, 1)]), meals: [meal], catalog: [egg])
        #expect(list.first?.quantityText == "6 unidades")
        #expect(list.first?.category == .dairyEggs)
    }

    @Test("Interpreta fracciones, decimales con coma y unidades de volumen")
    func parsesText() {
        func parse(_ text: String) -> (amount: Double, unit: String)? {
            ShoppingListBuilder.parse(Ingredient(name: "x", quantity: text))
        }
        #expect(parse("1/2 unidad")?.amount == 0.5)
        #expect(parse("1,5 kg")?.amount == 1_500)
        #expect(parse("1,5 kg")?.unit == "g")
        #expect(parse("2 l")?.unit == "ml")
        #expect(parse("al gusto") == nil)
    }

    @Test("Las cantidades incompatibles se muestran juntas")
    func joinsIncompatibleUnits() {
        let meal = Meal(
            name: "A", suggestedSlot: .lunch, calories: 1,
            ingredients: [Ingredient(name: "Pan", quantity: "2 unidades"), Ingredient(name: "Pan", quantity: "100 g", grams: 100)]
        )
        let list = ShoppingListBuilder.build(plan: plan([(meal, 1)]), meals: [meal])
        #expect(list.first?.quantityText == "2 unidades + 100 g")
    }

    @Test("Agrupa por secciones en el orden del supermercado")
    func groupsBySections() {
        let apple = CatalogIngredient(name: "Manzana", calories: 52, category: .produce)
        let milk = CatalogIngredient(name: "Leche", calories: 64, category: .dairyEggs)
        let meal = Meal(
            name: "A", suggestedSlot: .lunch, calories: 1,
            ingredients: [
                Ingredient(name: "Leche", quantity: "200 g", catalogID: milk.id, grams: 200),
                Ingredient(name: "Manzana", quantity: "100 g", catalogID: apple.id, grams: 100)
            ]
        )
        let list = ShoppingListBuilder.build(plan: plan([(meal, 1)]), meals: [meal], catalog: [apple, milk])
        let sections = ShoppingListBuilder.sections(of: list)
        #expect(sections.map(\.category) == [.produce, .dairyEggs])
    }

    @Test("Ignora comidas que ya no existen y el texto plano incluye los manuales")
    func ignoresMissingMealsAndShares() {
        let meal = Meal(name: "A", suggestedSlot: .lunch, calories: 1, ingredients: [Ingredient(name: "Sal", quantity: "al gusto")])
        let ghost = PlannedMeal(date: date, slot: .dinner, mealID: UUID())
        let withGhost = WeeklyPlan(weekStart: date, meals: plan([(meal, 1)]).meals + [ghost])
        let list = ShoppingListBuilder.build(plan: withGhost, meals: [meal])
        #expect(list.count == 1)
        let text = ShoppingListBuilder.plainText(for: list, manual: [ManualShoppingItem(name: "Servilletas", quantity: "1 paquete")])
        #expect(text.contains("• Sal: al gusto"))
        #expect(text.contains("• Servilletas: 1 paquete"))
    }
}
