import Foundation

public struct MenuGenerator: Sendable {
    public var calendar: Calendar
    public var tolerance: Int

    public init(calendar: Calendar = .current, tolerance: Int = 150) {
        self.calendar = calendar
        self.tolerance = tolerance
    }

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

public enum GenerationError: Error, Equatable {
    case invalidGoal
    case invalidDate
    case notEnoughMeals
    case goalUnavailable(day: Int, calories: Int)
}
