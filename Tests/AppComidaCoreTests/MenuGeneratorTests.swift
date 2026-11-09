//
//  MenuGeneratorTests.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: macOS / iOS · Swift Testing
//  Descripción: Pruebas del generador de menús semanales: objetivo calórico, variedad, reproducibilidad y comidas bloqueadas.
//

import Foundation
import Testing
@testable import AppComidaCore

/// Utilidades para construir datos de prueba.
enum Fixtures {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Lunes 2 de noviembre de 2026 (UTC).
    static let monday = Date(timeIntervalSince1970: 1_793_577_600)

    /// Crea una comida de una sola franja.
    /// - Parameters:
    ///   - name: Nombre.
    ///   - slot: Franja.
    ///   - calories: Calorías por ración.
    /// - Returns: La comida creada.
    static func meal(_ name: String, _ slot: MealSlot, _ calories: Int) -> Meal {
        Meal(name: name, suggestedSlot: slot, calories: calories)
    }

    /// Catálogo de comidas con varias opciones por franja.
    static var variedMeals: [Meal] {
        [
            meal("Tostada", .breakfast, 350), meal("Avena", .breakfast, 420), meal("Yogur y fruta", .breakfast, 300),
            meal("Ensalada", .lunch, 550), meal("Pasta", .lunch, 700), meal("Lentejas", .lunch, 620),
            meal("Fruta", .snack, 150), meal("Frutos secos", .snack, 250), meal("Bocadillo", .snack, 350),
            meal("Salmón", .dinner, 600), meal("Tortilla", .dinner, 500), meal("Crema de verduras", .dinner, 350)
        ]
    }
}

@Suite("MenuGenerator")
struct MenuGeneratorTests {
    private func generator(seed: UInt64? = 1) -> MenuGenerator {
        MenuGenerator(calendar: Fixtures.calendar, seed: seed)
    }

    @Test("Genera siete días con una comida por franja")
    func generatesFullWeek() throws {
        let plan = try generator().generate(
            weekStarting: Fixtures.monday, meals: Fixtures.variedMeals, dailyGoal: 1_800, locked: []
        ).get()
        #expect(plan.meals.count == 28)
        #expect(plan.days(calendar: Fixtures.calendar).count == 7)
        for day in plan.days(calendar: Fixtures.calendar) {
            #expect(day.meals.map(\.slot) == MealSlot.allCases)
        }
    }

    @Test("Cada día queda dentro de la tolerancia cuando es posible")
    func staysWithinTolerance() throws {
        let meals = Fixtures.variedMeals
        let plan = try generator().generate(weekStarting: Fixtures.monday, meals: meals, dailyGoal: 1_800, locked: []).get()
        for day in plan.days(calendar: Fixtures.calendar) {
            let total = day.meals.reduce(0) { sum, planned in
                sum + (meals.first { $0.id == planned.mealID }?.caloriesPerServing ?? 0)
            }
            #expect(abs(total - 1_800) <= 150)
        }
    }

    @Test("La misma semilla produce el mismo menú")
    func sameSeedIsReproducible() throws {
        let meals = Fixtures.variedMeals
        let first = try generator(seed: 7).generate(weekStarting: Fixtures.monday, meals: meals, dailyGoal: 1_800, locked: []).get()
        let second = try generator(seed: 7).generate(weekStarting: Fixtures.monday, meals: meals, dailyGoal: 1_800, locked: []).get()
        #expect(first == second)
    }

    @Test("Semillas distintas producen menús distintos")
    func differentSeedsVary() throws {
        let meals = Fixtures.variedMeals
        let plans = try (1...6).map { seed in
            try generator(seed: UInt64(seed)).generate(weekStarting: Fixtures.monday, meals: meals, dailyGoal: 1_800, locked: []).get()
        }
        let distinct = Set(plans.map { $0.meals.map(\.mealID) })
        #expect(distinct.count > 1)
    }

    @Test("Prefiere no repetir comidas mientras haya alternativas")
    func avoidsRepeatsWhenPossible() throws {
        // Con tres opciones por franja y objetivo flexible, no debería repetirse ninguna en los tres primeros días.
        let plan = try generator().generate(weekStarting: Fixtures.monday, meals: Fixtures.variedMeals, dailyGoal: 1_800, locked: []).get()
        let firstThree = plan.days(calendar: Fixtures.calendar).prefix(3).flatMap(\.meals)
        for slot in MealSlot.allCases {
            let ids = firstThree.filter { $0.slot == slot }.map(\.mealID)
            #expect(Set(ids).count == ids.count)
        }
    }

    @Test("Conserva las comidas bloqueadas")
    func keepsLockedMeals() throws {
        let meals = Fixtures.variedMeals
        let pasta = meals.first { $0.name == "Pasta" }!
        let wednesday = Fixtures.calendar.date(byAdding: .day, value: 2, to: Fixtures.monday)!
        let locked = PlannedMeal(date: wednesday, slot: .lunch, mealID: pasta.id, servings: 1.5, isLocked: true)

        for seed in 1...5 {
            let plan = try generator(seed: UInt64(seed)).generate(
                weekStarting: Fixtures.monday, meals: meals, dailyGoal: 2_000, locked: [locked]
            ).get()
            let kept = plan.meals.first { Fixtures.calendar.isDate($0.date, inSameDayAs: wednesday) && $0.slot == .lunch }
            #expect(kept?.mealID == pasta.id)
            #expect(kept?.servings == 1.5)
            #expect(kept?.isLocked == true)
            #expect(plan.meals.count == 28)
        }
    }

    @Test("Falla si falta alguna franja o el objetivo no es válido")
    func reportsErrors() {
        let onlyBreakfast = [Fixtures.meal("Tostada", .breakfast, 300)]
        #expect(generator().generate(weekStarting: Fixtures.monday, meals: onlyBreakfast, dailyGoal: 1_800, locked: []) == .failure(.notEnoughMeals))
        #expect(generator().generate(weekStarting: Fixtures.monday, meals: Fixtures.variedMeals, dailyGoal: 0, locked: []) == .failure(.invalidGoal))
    }

    @Test("Con una sola comida por franja repite sin fallar")
    func worksWithMinimumMeals() throws {
        let meals = SampleMeals.all
        let plan = try generator().generate(weekStarting: Fixtures.monday, meals: meals, dailyGoal: 1_900, locked: []).get()
        #expect(plan.meals.count == 28)
    }
}
