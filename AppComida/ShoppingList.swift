import Foundation

/// Un producto de la lista de la compra con la cantidad total de la semana.
public struct ShoppingItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// Cantidad ya formateada, por ejemplo "420 g" o "3 unidades + 100 g".
    public var quantityText: String
}

/// Suma los ingredientes de todas las comidas del plan semanal.
///
/// Cada comida planificada equivale a una ración, de modo que las cantidades de la
/// receta se dividen entre sus raciones. Las cantidades con la misma unidad se suman
/// (kg → g, l → ml) y las que no son compatibles se muestran juntas.
public enum ShoppingListBuilder {
    public static func build(plan: WeeklyPlan, meals: [Meal]) -> [ShoppingItem] {
        let mealsByID = Dictionary(meals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        struct Entry {
            var name: String
            var totals: [String: Double] = [:]
            var unitOrder: [String] = []
            var freeText: [String] = []
        }
        var entries: [String: Entry] = [:]

        for planned in plan.meals {
            guard let meal = mealsByID[planned.mealID] else { continue }
            let servings = Double(max(meal.servings, 1))
            for ingredient in meal.ingredients {
                let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let key = normalized(name)
                var entry = entries[key] ?? Entry(name: name)

                if let parsed = parse(ingredient) {
                    if entry.totals[parsed.unit] == nil { entry.unitOrder.append(parsed.unit) }
                    entry.totals[parsed.unit, default: 0] += parsed.amount / servings
                } else {
                    let text = ingredient.quantity.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty, !entry.freeText.contains(text) { entry.freeText.append(text) }
                }
                entries[key] = entry
            }
        }

        return entries
            .map { key, entry in
                var parts = entry.unitOrder.compactMap { unit in
                    entry.totals[unit].map { format($0, unit: unit) }
                }
                parts.append(contentsOf: entry.freeText)
                return ShoppingItem(id: key, name: entry.name, quantityText: parts.joined(separator: " + "))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func plainText(for items: [ShoppingItem]) -> String {
        let lines = items.map { "• \($0.name): \($0.quantityText)" }
        return (["Lista de la compra"] + lines).joined(separator: "\n")
    }

    // MARK: - Parsing

    private static func normalized(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parse(_ ingredient: Ingredient) -> (amount: Double, unit: String)? {
        if let grams = ingredient.grams, grams > 0 {
            return (grams, "g")
        }
        let text = ingredient.quantity
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let scanner = Scanner(string: text)
        scanner.locale = nil
        guard var amount = scanner.scanDouble() else { return nil }
        if scanner.scanString("/") != nil, let denominator = scanner.scanDouble(), denominator != 0 {
            amount /= denominator
        }
        let rest = String(text[scanner.currentIndex...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
        guard amount > 0 else { return nil }

        switch rest {
        case "g", "gr", "grs", "gramo", "gramos": return (amount, "g")
        case "kg", "kilo", "kilos": return (amount * 1_000, "g")
        case "ml", "mililitro", "mililitros": return (amount, "ml")
        case "cl": return (amount * 10, "ml")
        case "l", "litro", "litros": return (amount * 1_000, "ml")
        case "", "u", "ud", "uds", "unidad", "unidades": return (amount, "unidad")
        default: return (amount, rest)
        }
    }

    // MARK: - Formato

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private static func format(_ amount: Double, unit: String) -> String {
        switch unit {
        case "g":
            return amount >= 1_000 ? "\(number(amount / 1_000)) kg" : "\(number(amount.rounded())) g"
        case "ml":
            return amount >= 1_000 ? "\(number(amount / 1_000)) l" : "\(number(amount.rounded())) ml"
        case "unidad":
            let count = Int(amount.rounded(.up))
            return count == 1 ? "1 unidad" : "\(count) unidades"
        default:
            return "\(number(amount)) \(unit)"
        }
    }
}
