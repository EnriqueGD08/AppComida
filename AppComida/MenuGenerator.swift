//
//  MenuGenerator.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-10-12
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Generador del menú semanal: elige para cada día una comida por franja acercándose al objetivo calórico, repitiendo lo menos posible, con variedad aleatoria y respetando las comidas bloqueadas.
//

import Foundation

/// Contrato de un generador de menús semanales. Permite sustituir el algoritmo (por ejemplo, por uno falso en pruebas).
public protocol MenuGenerating: Sendable {
    /// Genera un plan semanal.
    /// - Parameters:
    ///   - start: Primer día de la semana.
    ///   - meals: Comidas disponibles.
    ///   - dailyGoal: Objetivo calórico diario en kcal.
    ///   - locked: Comidas que deben conservarse tal cual en el plan resultante.
    /// - Returns: El plan generado o el motivo del fallo.
    func generate(
        weekStarting start: Date,
        meals: [Meal],
        dailyGoal: Int,
        locked: [PlannedMeal]
    ) -> Result<WeeklyPlan, GenerationError>
}

/// Generador de números pseudoaleatorios determinista (SplitMix64), útil para obtener menús reproducibles en pruebas.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    /// Crea el generador.
    /// - Parameter seed: Semilla inicial; la misma semilla produce siempre la misma secuencia.
    public init(seed: UInt64) {
        state = seed
    }

    /// Calcula el siguiente número de la secuencia.
    /// - Returns: Un valor de 64 bits.
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Envuelve cualquier generador aleatorio para poder pasarlo como `inout` a funciones genéricas.
private struct AnyRandomNumberGenerator: RandomNumberGenerator {
    var base: any RandomNumberGenerator

    /// Delega en el generador envuelto.
    /// - Returns: El siguiente valor aleatorio de 64 bits.
    mutating func next() -> UInt64 {
        base.next()
    }
}

/// Genera planes semanales ajustando las calorías diarias a un objetivo.
///
/// Para cada día evalúa las combinaciones de una comida por franja y elige, entre las que quedan
/// dentro de la tolerancia, la que menos comidas repite; si hay varias igual de buenas escoge una al azar,
/// de modo que cada generación produce un menú distinto.
public struct MenuGenerator: MenuGenerating {
    /// Diferencia calórica diaria que se considera aceptable por defecto, en kcal.
    public static let defaultTolerance = 150

    /// Máximo de combinaciones de opciones que se evalúan por día; si hay más, se muestrean al azar.
    private static let optionSearchLimit = 4_096

    public var calendar: Calendar
    public var tolerance: Int
    /// Máximo de comidas candidatas por franja y día; limita el coste de la búsqueda.
    public var candidateLimit: Int
    /// Semilla para resultados reproducibles; `nil` usa el generador aleatorio del sistema.
    public var seed: UInt64?

    /// Crea el generador.
    /// - Parameters:
    ///   - calendar: Calendario usado para calcular los días de la semana.
    ///   - tolerance: Diferencia calórica máxima aceptable respecto al objetivo, en kcal.
    ///   - candidateLimit: Máximo de candidatas evaluadas por franja y día.
    ///   - seed: Semilla opcional para obtener siempre el mismo resultado.
    public init(calendar: Calendar = .current, tolerance: Int = MenuGenerator.defaultTolerance, candidateLimit: Int = 24, seed: UInt64? = nil) {
        self.calendar = calendar
        self.tolerance = tolerance
        self.candidateLimit = max(candidateLimit, 1)
        self.seed = seed
    }

    /// Genera un plan de siete días con una comida por franja y día.
    ///
    /// Cada comida entra con sus raciones por toma y, si tiene ingredientes variables, con una opción elegida de cada grupo.
    ///
    /// Las comidas de `locked` se conservan y cuentan para las calorías del día; el resto de franjas se rellenan.
    /// - Parameters:
    ///   - start: Primer día de la semana.
    ///   - meals: Comidas disponibles.
    ///   - dailyGoal: Objetivo calórico diario en kcal.
    ///   - locked: Comidas bloqueadas que deben mantenerse.
    /// - Returns: El plan generado, o un `GenerationError` si el objetivo no es válido, la fecha falla o falta alguna franja.
    public func generate(
        weekStarting start: Date,
        meals: [Meal],
        dailyGoal: Int,
        locked: [PlannedMeal] = []
    ) -> Result<WeeklyPlan, GenerationError> {
        guard dailyGoal > 0 else { return .failure(.invalidGoal) }
        guard MealSlot.allCases.allSatisfy({ slot in meals.contains { $0.mealSlots.contains(slot) } }) else {
            return .failure(.notEnoughMeals)
        }

        var random = AnyRandomNumberGenerator(base: seed.map { SplitMix64(seed: $0) } ?? SystemRandomNumberGenerator())
        let mealsByID = Dictionary(meals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var usedIDs = Set<UUID>()
        var optionUsage: [UUID: Int] = [:]
        var planned: [PlannedMeal] = []

        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: start) else {
                return .failure(.invalidDate)
            }
            let fixed = locked.filter {
                calendar.isDate($0.date, inSameDayAs: date) && mealsByID[$0.mealID] != nil
            }
            let fixedSlots = Set(fixed.map(\.slot))
            let freeSlots = MealSlot.allCases.filter { !fixedSlots.contains($0) }
            let fixedCalories = fixed.reduce(0) { total, item in
                total + (mealsByID[item.mealID]?.calories(for: item) ?? 0)
            }

            guard let chosen = bestCombination(
                freeSlots: freeSlots,
                fixedCalories: fixedCalories,
                fixedIDs: fixed.map(\.mealID),
                meals: meals,
                usedIDs: usedIDs,
                dailyGoal: dailyGoal,
                random: &random
            ) else {
                return .failure(.notEnoughMeals)
            }

            var dayMeals: [PlannedMeal] = []
            for item in fixed {
                usedIDs.insert(item.mealID)
                var kept = item
                kept.date = date
                dayMeals.append(kept)
            }
            for (slot, meal) in zip(freeSlots, chosen) {
                usedIDs.insert(meal.id)
                dayMeals.append(PlannedMeal(date: date, slot: slot, mealID: meal.id, servings: meal.plannedServings))
            }
            assignOptions(
                to: &dayMeals,
                mealsByID: mealsByID,
                usage: &optionUsage,
                dailyGoal: dailyGoal,
                random: &random
            )
            planned.append(contentsOf: dayMeals)
        }
        return .success(WeeklyPlan(weekStart: start, meals: planned))
    }

    /// Busca la mejor combinación de una comida por cada franja libre de un día.
    ///
    /// Criterio: primero las combinaciones dentro de la tolerancia, con el menor número de comidas ya usadas;
    /// si ninguna está dentro de la tolerancia, la más cercana al objetivo. Los empates se resuelven al azar.
    /// - Parameters:
    ///   - freeSlots: Franjas que hay que rellenar.
    ///   - fixedCalories: Calorías ya aportadas por las comidas bloqueadas del día.
    ///   - fixedIDs: Comidas bloqueadas del día, que cuentan como usadas.
    ///   - meals: Comidas disponibles.
    ///   - usedIDs: Comidas ya usadas en días anteriores.
    ///   - dailyGoal: Objetivo calórico diario en kcal.
    ///   - random: Generador aleatorio.
    /// - Returns: Las comidas elegidas en el orden de `freeSlots`, o `nil` si alguna franja no tiene candidatas.
    private func bestCombination(
        freeSlots: [MealSlot],
        fixedCalories: Int,
        fixedIDs: [UUID],
        meals: [Meal],
        usedIDs: Set<UUID>,
        dailyGoal: Int,
        random: inout AnyRandomNumberGenerator
    ) -> [Meal]? {
        if freeSlots.isEmpty { return [] }

        var candidates: [[Meal]] = []
        for slot in freeSlots {
            var options = meals.filter { $0.mealSlots.contains(slot) }
            if options.isEmpty { return nil }
            options.shuffle(using: &random)
            let unused = options.filter { !usedIDs.contains($0.id) }
            let reused = options.filter { usedIDs.contains($0.id) }
            candidates.append(Array((unused + reused).prefix(candidateLimit)))
        }

        var best: [Meal]?
        var bestKey = (outside: Int.max, difference: Int.max, reuse: Int.max)
        var ties = 0
        var current: [Meal] = []

        /// Recorre todas las combinaciones (una comida por franja) y conserva la mejor, eligiendo al azar entre empates.
        /// - Parameters:
        ///   - slotIndex: Franja que se está eligiendo.
        ///   - calories: Calorías acumuladas hasta ahora.
        func search(slotIndex: Int, calories: Int) {
            if slotIndex == candidates.count {
                let difference = abs(calories - dailyGoal)
                let outside = difference > tolerance ? 1 : 0
                let reuse = reuseCount(of: current, fixedIDs: fixedIDs, usedIDs: usedIDs)
                let key = (outside: outside, difference: outside == 0 ? 0 : difference, reuse: reuse)
                if best == nil || isBetter(key, than: bestKey) {
                    best = current
                    bestKey = key
                    ties = 1
                } else if key == bestKey {
                    ties += 1
                    if Int.random(in: 0..<ties, using: &random) == 0 { best = current }
                }
                return
            }
            for meal in candidates[slotIndex] {
                current.append(meal)
                search(slotIndex: slotIndex + 1, calories: calories + meal.expectedCalories)
                current.removeLast()
            }
        }

        search(slotIndex: 0, calories: fixedCalories)
        return best
    }

    /// Elige, para cada ingrediente variable de las comidas de un día, una de sus opciones.
    ///
    /// Criterio: se aceptan las combinaciones que dejan el día dentro de la tolerancia (con las calorías exactas de las opciones) o,
    /// si ninguna lo consigue, las que no se alejan del mejor resultado posible más que la tolerancia. Entre las aceptables
    /// se eligen las opciones menos usadas durante la semana, para que haya variedad; los empates se resuelven al azar.
    /// Las comidas que ya traen una elección (bloqueadas) la conservan y cuentan como usadas.
    /// - Parameters:
    ///   - dayMeals: Comidas planificadas del día; se les añaden las elecciones.
    ///   - mealsByID: Comidas disponibles por identificador.
    ///   - usage: Veces que se ha usado cada opción en la semana; se actualiza.
    ///   - dailyGoal: Objetivo calórico diario en kcal.
    ///   - random: Generador aleatorio.
    private func assignOptions(
        to dayMeals: inout [PlannedMeal],
        mealsByID: [UUID: Meal],
        usage: inout [UUID: Int],
        dailyGoal: Int,
        random: inout AnyRandomNumberGenerator
    ) {
        var baseCalories = 0.0
        var pending: [(index: Int, group: MealOptionGroup, factor: Double)] = []
        for (index, item) in dayMeals.enumerated() {
            guard let meal = mealsByID[item.mealID] else { continue }
            let factor = item.servings / Double(max(meal.servings, 1))
            baseCalories += Double(meal.calories) * factor
            for option in meal.chosenOptions(for: item.choices) {
                baseCalories += Double(option.calories) * factor
                usage[option.id, default: 0] += 1
            }
            for group in meal.optionGroups where !group.options.isEmpty
                && !item.choices.contains(where: { $0.groupID == group.id }) {
                pending.append((index, group, factor))
            }
        }
        guard !pending.isEmpty else { return }

        let counts = pending.map { $0.group.options.count }
        var space = 1
        for count in counts { space = min(space * count, Self.optionSearchLimit + 1) }

        var candidates: [(picks: [Int], difference: Int, reuse: Int)] = []

        /// Evalúa una combinación de opciones (una por grupo) y la guarda como candidata.
        /// - Parameter picks: Índice de la opción elegida en cada grupo pendiente.
        func consider(_ picks: [Int]) {
            var calories = baseCalories
            var reuse = 0
            for (slot, pick) in picks.enumerated() {
                let option = pending[slot].group.options[pick]
                calories += Double(option.calories) * pending[slot].factor
                reuse += usage[option.id, default: 0]
            }
            candidates.append((picks, abs(Int(calories.rounded()) - dailyGoal), reuse))
        }

        if space <= Self.optionSearchLimit {
            var picks = Array(repeating: 0, count: counts.count)
            while true {
                consider(picks)
                var position = picks.count - 1
                while position >= 0 {
                    picks[position] += 1
                    if picks[position] < counts[position] { break }
                    picks[position] = 0
                    position -= 1
                }
                if position < 0 { break }
            }
        } else {
            for _ in 0..<Self.optionSearchLimit {
                consider(counts.map { Int.random(in: 0..<$0, using: &random) })
            }
        }

        // Combinaciones aceptables: las que dejan el día dentro de la tolerancia o, si ninguna lo consigue,
        // las que no se alejan del mejor resultado posible más que la propia tolerancia. Entre ellas manda la variedad.
        let minDifference = candidates.map(\.difference).min() ?? 0
        let limit = minDifference > tolerance ? minDifference + tolerance : tolerance
        let acceptable = candidates.filter { $0.difference <= limit }
        let lowestReuse = acceptable.map(\.reuse).min() ?? 0
        let finalists = acceptable.filter { $0.reuse == lowestReuse }
        let best = finalists[Int.random(in: 0..<finalists.count, using: &random)].picks

        for (slot, pick) in best.enumerated() {
            let option = pending[slot].group.options[pick]
            dayMeals[pending[slot].index].choices.append(OptionChoice(groupID: pending[slot].group.id, optionID: option.id))
            usage[option.id, default: 0] += 1
        }
    }

    /// Compara dos puntuaciones de combinación de forma lexicográfica (menor es mejor).
    /// - Parameters:
    ///   - lhs: Puntuación candidata.
    ///   - rhs: Mejor puntuación hasta ahora.
    /// - Returns: `true` si `lhs` es estrictamente mejor que `rhs`.
    private func isBetter(
        _ lhs: (outside: Int, difference: Int, reuse: Int),
        than rhs: (outside: Int, difference: Int, reuse: Int)
    ) -> Bool {
        if lhs.outside != rhs.outside { return lhs.outside < rhs.outside }
        if lhs.difference != rhs.difference { return lhs.difference < rhs.difference }
        return lhs.reuse < rhs.reuse
    }

    /// Cuenta cuántas comidas de una combinación ya se habían usado (en la semana o dentro del mismo día).
    /// - Parameters:
    ///   - combination: Comidas elegidas.
    ///   - fixedIDs: Comidas bloqueadas del día.
    ///   - usedIDs: Comidas usadas en días anteriores.
    /// - Returns: El número de repeticiones.
    private func reuseCount(of combination: [Meal], fixedIDs: [UUID], usedIDs: Set<UUID>) -> Int {
        var seen = Set(fixedIDs)
        var count = 0
        for meal in combination {
            if usedIDs.contains(meal.id) || seen.contains(meal.id) { count += 1 }
            seen.insert(meal.id)
        }
        return count
    }
}

/// Motivos por los que no se puede generar un plan semanal.
public enum GenerationError: Error, Equatable {
    case invalidGoal
    case invalidDate
    case notEnoughMeals
    case goalUnavailable(day: Int, calories: Int)
}
