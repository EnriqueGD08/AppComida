//
//  MenuGenerator.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-10-12
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Generador del menú semanal: elige para cada día una comida por franja intentando acercarse al objetivo calórico diario y repitiendo lo menos posible.
//

import Foundation

/// Genera planes semanales ajustando las calorías diarias a un objetivo.
public struct MenuGenerator: Sendable {
    public var calendar: Calendar
    public var tolerance: Int

    /// Crea el generador.
    /// - Parameters:
    ///   - calendar: Calendario usado para calcular los días de la semana.
    ///   - tolerance: Diferencia calórica máxima aceptable respecto al objetivo, en kcal.
    public init(calendar: Calendar = .current, tolerance: Int = 150) {
        self.calendar = calendar
        self.tolerance = tolerance
    }

    /// Genera un plan de siete días con una comida por franja y día.
    ///
    /// Para cada día elige la combinación cuyas calorías por ración se acercan más al objetivo, prefiriendo comidas que aún no se hayan usado en la semana.
    /// - Parameters:
    ///   - start: Primer día de la semana.
    ///   - meals: Comidas disponibles.
    ///   - dailyGoal: Objetivo calórico diario en kcal.
    /// - Returns: El plan generado, o un `GenerationError` si el objetivo no es válido, la fecha falla o falta alguna franja.
    public func generate(weekStarting start: Date, meals: [Meal], dailyGoal: Int) -> Result<WeeklyPlan, GenerationError> {
        guard dailyGoal > 0 else { return .failure(.invalidGoal) }
        guard MealSlot.allCases.allSatisfy({ slot in meals.contains { meal in meal.mealSlots.contains(slot) } }) else {
            return .failure(.notEnoughMeals)
        }

        var selectedIDs = Set<UUID>()
        var planned: [PlannedMeal] = []
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: start) else {
                return .failure(.invalidDate)
            }
            guard let dayMeals = bestCombination(
                meals: meals,
                selectedIDs: selectedIDs,
                dailyGoal: dailyGoal
            ) else {
                return .failure(.notEnoughMeals)
            }
            for (slot, meal) in zip(MealSlot.allCases, dayMeals) {
                selectedIDs.insert(meal.id)
                planned.append(PlannedMeal(date: date, slot: slot, mealID: meal.id))
            }
        }
        return .success(WeeklyPlan(weekStart: start, meals: planned))
    }

    /// Busca la mejor combinación de una comida por franja para un día.
    ///
    /// Minimiza la diferencia con el objetivo y, a igualdad, el número de comidas repetidas en el mismo día.
    /// - Parameters:
    ///   - meals: Comidas disponibles.
    ///   - selectedIDs: Comidas ya usadas en días anteriores, que se ordenan al final.
    ///   - dailyGoal: Objetivo calórico diario en kcal.
    /// - Returns: Las comidas elegidas en el orden de `MealSlot.allCases`, o `nil` si alguna franja no tiene candidatas.
    private func bestCombination(
        meals: [Meal],
        selectedIDs: Set<UUID>,
        dailyGoal: Int
    ) -> [Meal]? {
        let candidates = MealSlot.allCases.map { slot in
            meals
                .filter { $0.mealSlots.contains(slot) }
                .sorted {
                    let firstIsUsed = selectedIDs.contains($0.id)
                    let secondIsUsed = selectedIDs.contains($1.id)
                    if firstIsUsed != secondIsUsed {
                        return !firstIsUsed
                    }
                    if $0.caloriesPerServing != $1.caloriesPerServing {
                        return $0.caloriesPerServing < $1.caloriesPerServing
                    }
                    return $0.name < $1.name
                }
        }
        guard candidates.allSatisfy({ !$0.isEmpty }) else { return nil }

        var best: [Meal]?
        var bestDifference = Int.max
        var bestRepeatedMeals = Int.max
        var current: [Meal] = []

        /// Recorre recursivamente todas las combinaciones, una franja por nivel, guardando la mejor encontrada.
        /// - Parameters:
        ///   - slotIndex: Franja que se está eligiendo.
        ///   - calories: Calorías acumuladas hasta ahora.
        ///   - repeatedMeals: Comidas repetidas acumuladas hasta ahora.
        func search(slotIndex: Int, calories: Int, repeatedMeals: Int) {
            if slotIndex == candidates.count {
                let difference = abs(calories - dailyGoal)
                if difference < bestDifference ||
                    (difference == bestDifference && repeatedMeals < bestRepeatedMeals) {
                    best = current
                    bestDifference = difference
                    bestRepeatedMeals = repeatedMeals
                }
                return
            }

            for meal in candidates[slotIndex] {
                let nextCalories = calories + meal.caloriesPerServing
                let nextRepeatedMeals = repeatedMeals + (current.contains { $0.id == meal.id } ? 1 : 0)
                current.append(meal)
                search(slotIndex: slotIndex + 1, calories: nextCalories, repeatedMeals: nextRepeatedMeals)
                current.removeLast()
            }
        }

        search(slotIndex: 0, calories: 0, repeatedMeals: 0)
        return best
    }
}

/// Motivos por los que no se puede generar un plan semanal.
public enum GenerationError: Error, Equatable {
    case invalidGoal
    case invalidDate
    case notEnoughMeals
    case goalUnavailable(day: Int, calories: Int)
}
