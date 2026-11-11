//
//  ShoppingList.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-05
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Lógica de la lista de la compra: suma los ingredientes de las comidas del plan semanal (nombre y cantidad total), normaliza unidades, respeta las raciones planificadas y agrupa por sección del supermercado.
//

import Foundation

/// Un producto de la lista de la compra con la cantidad total de la semana.
public struct ShoppingItem: Identifiable, Equatable, Sendable {
    /// Clave normalizada del nombre (`String.searchKey`).
    public var id: String
    public var name: String
    /// Cantidad ya formateada, por ejemplo "420 g" o "3 unidades + 100 g".
    public var quantityText: String
    public var category: IngredientCategory
}

/// Productos de una misma sección del supermercado.
public struct ShoppingSection: Identifiable, Equatable, Sendable {
    public var category: IngredientCategory
    public var items: [ShoppingItem]
    public var id: IngredientCategory { category }
}

/// Suma los ingredientes de todas las comidas del plan semanal.
///
/// Cada comida planificada aporta `servings` raciones, de modo que las cantidades de la receta se
/// multiplican por `raciones planificadas / raciones de la receta`. También se suman los ingredientes de las opciones
/// elegidas en cada comida del plan. Las cantidades con la misma
/// unidad se suman (kg → g, l → ml); si el ingrediente del catálogo tiene peso por unidad, los gramos
/// se convierten a unidades; las cantidades incompatibles se muestran juntas.
public enum ShoppingListBuilder {
    /// Construye la lista de la compra de un plan semanal.
    /// - Parameters:
    ///   - plan: Plan semanal del que se toman las comidas.
    ///   - meals: Comidas disponibles, para resolver los ingredientes de cada una.
    ///   - catalog: Catálogo de ingredientes, para conocer su sección y su peso por unidad.
    /// - Returns: Productos con su cantidad total, ordenados por nombre.
    public static func build(plan: WeeklyPlan, meals: [Meal], catalog: [CatalogIngredient] = []) -> [ShoppingItem] {
        let mealsByID = Dictionary(meals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let catalogByID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let catalogByKey = Dictionary(catalog.map { ($0.name.searchKey, $0) }, uniquingKeysWith: { first, _ in first })

        var entries: [String: Entry] = [:]
        for planned in plan.meals {
            guard let meal = mealsByID[planned.mealID] else { continue }
            let factor = planned.servings / Double(max(meal.servings, 1))
            let chosen = meal.chosenOptions(for: planned.choices).map(\.ingredient)
            for ingredient in meal.ingredients + chosen {
                let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let key = name.searchKey
                let catalogItem = ingredient.catalogID.flatMap { catalogByID[$0] } ?? catalogByKey[key]
                var entry = entries[key] ?? Entry(name: name, category: catalogItem?.category ?? .other)
                entry.add(ingredient, catalogItem: catalogItem, factor: factor)
                entries[key] = entry
            }
        }

        return entries
            .map { key, entry in
                ShoppingItem(id: key, name: entry.name, quantityText: entry.quantityText, category: entry.category)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Agrupa los productos por sección del supermercado, en el orden de `IngredientCategory`.
    /// - Parameter items: Productos a agrupar.
    /// - Returns: Solo las secciones que tienen productos.
    public static func sections(of items: [ShoppingItem]) -> [ShoppingSection] {
        IngredientCategory.allCases.compactMap { category in
            let inCategory = items.filter { $0.category == category }
            return inCategory.isEmpty ? nil : ShoppingSection(category: category, items: inCategory)
        }
    }

    /// Convierte la lista en texto plano para compartirla.
    /// - Parameters:
    ///   - items: Productos de la lista, agrupados por sección en el texto.
    ///   - manual: Productos añadidos a mano.
    /// - Returns: Un texto con un producto por línea.
    public static func plainText(for items: [ShoppingItem], manual: [ManualShoppingItem] = []) -> String {
        var lines = ["Lista de la compra"]
        for section in sections(of: items) {
            lines.append("")
            lines.append(section.category.title)
            lines.append(contentsOf: section.items.map { "• \($0.name): \($0.quantityText)" })
        }
        if !manual.isEmpty {
            lines.append("")
            lines.append("Añadido a mano")
            lines.append(contentsOf: manual.map { $0.quantity.isEmpty ? "• \($0.name)" : "• \($0.name): \($0.quantity)" })
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Acumulación

    /// Acumulador interno de un producto: sus totales por unidad y las cantidades sin número.
    private struct Entry {
        var name: String
        var category: IngredientCategory
        var totals: [String: Double] = [:]
        var unitOrder: [String] = []
        var freeText: [String] = []

        /// Suma un ingrediente de una comida al acumulado.
        /// - Parameters:
        ///   - ingredient: Ingrediente de la receta.
        ///   - catalogItem: Ingrediente del catálogo asociado, si existe.
        ///   - factor: Multiplicador por las raciones planificadas.
        mutating func add(_ ingredient: Ingredient, catalogItem: CatalogIngredient?, factor: Double) {
            if let parsed = ShoppingListBuilder.parse(ingredient, catalogItem: catalogItem) {
                if totals[parsed.unit] == nil { unitOrder.append(parsed.unit) }
                totals[parsed.unit, default: 0] += parsed.amount * factor
            } else {
                let text = ingredient.quantity.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty, !freeText.contains(text) { freeText.append(text) }
            }
        }

        /// Texto con la cantidad total, uniendo con "+" las unidades incompatibles.
        var quantityText: String {
            var parts = unitOrder.compactMap { unit in totals[unit].map { ShoppingListBuilder.format($0, unit: unit) } }
            parts.append(contentsOf: freeText)
            return parts.joined(separator: " + ")
        }
    }

    // MARK: - Interpretación de cantidades

    /// Interpreta la cantidad de un ingrediente.
    ///
    /// Si tiene gramos los usa (convirtiéndolos a unidades cuando el catálogo da el peso por unidad);
    /// si no, lee el número y la unidad del texto (admite decimales con coma y fracciones) y convierte kg a g y l/cl a ml.
    /// - Parameters:
    ///   - ingredient: Ingrediente a interpretar.
    ///   - catalogItem: Ingrediente del catálogo asociado, si existe.
    /// - Returns: Cantidad y unidad normalizada, o `nil` si el texto no contiene una cantidad (por ejemplo "al gusto").
    static func parse(_ ingredient: Ingredient, catalogItem: CatalogIngredient? = nil) -> (amount: Double, unit: String)? {
        if let grams = ingredient.grams, grams > 0 {
            if let units = RecipeCalculator.units(forGrams: grams, of: catalogItem) {
                return (units, "unidad")
            }
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

    /// Formatea un número con un máximo de un decimal según el idioma del dispositivo.
    /// - Parameter value: Número a formatear.
    /// - Returns: El número como texto.
    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// Da formato legible a una cantidad: pasa a kg o l a partir de 1000 y redondea las unidades hacia arriba.
    /// - Parameters:
    ///   - amount: Cantidad total.
    ///   - unit: Unidad normalizada ("g", "ml", "unidad" u otra).
    /// - Returns: Texto como "1,2 kg" o "3 unidades".
    static func format(_ amount: Double, unit: String) -> String {
        switch unit {
        case "g":
            return amount >= 1_000 ? "\(number(amount / 1_000)) kg" : "\(number(amount.rounded())) g"
        case "ml":
            return amount >= 1_000 ? "\(number(amount / 1_000)) l" : "\(number(amount.rounded())) ml"
        case "unidad":
            let count = Int((amount - 0.0001).rounded(.up))
            return count <= 1 ? "1 unidad" : "\(count) unidades"
        default:
            return "\(number(amount)) \(unit)"
        }
    }
}
