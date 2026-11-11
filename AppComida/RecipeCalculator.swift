//
//  RecipeCalculator.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Cálculo de calorías y macronutrientes de una receta a partir de los ingredientes del catálogo.
//

import Foundation

/// Calcula los valores nutricionales de una receta a partir del catálogo de ingredientes.
public enum RecipeCalculator {
    /// Calorías totales de una lista de ingredientes.
    ///
    /// Los ingredientes que no están en el catálogo o no tienen gramos no suman.
    /// - Parameters:
    ///   - ingredients: Ingredientes de la receta.
    ///   - catalog: Catálogo de ingredientes.
    /// - Returns: Las calorías de la receta completa, redondeadas.
    public static func calories(of ingredients: [Ingredient], catalog: [CatalogIngredient]) -> Int {
        let byID = index(catalog)
        let total = ingredients.reduce(0.0) { sum, ingredient in
            guard let grams = ingredient.grams, let id = ingredient.catalogID, let item = byID[id] else { return sum }
            return sum + item.caloriesPerGram * grams
        }
        return Int(total.rounded())
    }

    /// Macronutrientes totales de una lista de ingredientes.
    /// - Parameters:
    ///   - ingredients: Ingredientes de la receta.
    ///   - catalog: Catálogo de ingredientes.
    /// - Returns: Los macronutrientes de la receta completa, o `nil` si no hay ingredientes o alguno no tiene
    ///   macronutrientes en el catálogo (en ese caso no se puede calcular con fiabilidad).
    public static func nutrition(of ingredients: [Ingredient], catalog: [CatalogIngredient]) -> Nutrition? {
        guard !ingredients.isEmpty else { return nil }
        let byID = index(catalog)
        var total = Nutrition()
        for ingredient in ingredients {
            guard let grams = ingredient.grams,
                  let id = ingredient.catalogID,
                  let macros = byID[id]?.macrosPer100g else { return nil }
            total = total + macros.scaled(by: grams / 100)
        }
        return total
    }

    /// Calorías y macronutrientes de un conjunto de ingredientes (por ejemplo, una opción de un ingrediente variable).
    /// - Parameters:
    ///   - ingredients: Ingredientes con su cantidad en gramos.
    ///   - catalog: Catálogo de ingredientes.
    /// - Returns: La suma de calorías y de macronutrientes (los ingredientes sin macronutrientes en el catálogo suman cero),
    ///   o `nil` si no hay ingredientes o alguno no se puede resolver.
    public static func values(of ingredients: [Ingredient], catalog: [CatalogIngredient]) -> (calories: Int, nutrition: Nutrition)? {
        guard !ingredients.isEmpty else { return nil }
        let byID = index(catalog)
        var calories = 0.0
        var nutrition = Nutrition()
        for ingredient in ingredients {
            guard let grams = ingredient.grams, let id = ingredient.catalogID, let item = byID[id] else { return nil }
            calories += item.caloriesPerGram * grams
            nutrition = nutrition + (item.macrosPer100g?.scaled(by: grams / 100) ?? Nutrition())
        }
        return (Int(calories.rounded()), nutrition)
    }

    /// Recalcula las calorías (y los macronutrientes, si son calculables) de una comida con el catálogo actual,
    /// incluidas las opciones de sus ingredientes variables.
    ///
    /// Si algún ingrediente fijo no se puede resolver, las calorías de la receta no se tocan; las opciones se recalculan una a una.
    /// - Parameters:
    ///   - meal: Comida a recalcular.
    ///   - catalog: Catálogo de ingredientes.
    /// - Returns: La comida con los valores actualizados.
    public static func recalculated(_ meal: Meal, catalog: [CatalogIngredient]) -> Meal {
        var updated = meal
        updated.optionGroups = meal.optionGroups.map { group in
            var recalculatedGroup = group
            recalculatedGroup.options = group.options.map { option in
                guard let values = values(of: option.ingredients, catalog: catalog) else { return option }
                var recalculatedOption = option
                recalculatedOption.calories = values.calories
                recalculatedOption.nutrition = values.nutrition
                return recalculatedOption
            }
            return recalculatedGroup
        }

        let byID = index(catalog)
        let resolvable = !meal.ingredients.isEmpty && meal.ingredients.allSatisfy {
            $0.grams != nil && $0.catalogID.flatMap { byID[$0] } != nil
        }
        guard resolvable else { return updated }
        updated.calories = calories(of: meal.ingredients, catalog: catalog)
        if let computed = nutrition(of: meal.ingredients, catalog: catalog) {
            updated.nutrition = computed
        }
        return updated
    }

    /// Cantidad de unidades equivalentes a unos gramos, si el ingrediente se cuenta por unidades.
    /// - Parameters:
    ///   - grams: Gramos del ingrediente.
    ///   - item: Ingrediente del catálogo.
    /// - Returns: El número de unidades, o `nil` si el ingrediente no tiene peso por unidad.
    public static func units(forGrams grams: Double, of item: CatalogIngredient?) -> Double? {
        guard let weight = item?.unitWeightGrams, weight > 0 else { return nil }
        return grams / weight
    }

    /// Indexa el catálogo por identificador.
    /// - Parameter catalog: Catálogo de ingredientes.
    /// - Returns: Un diccionario `id → ingrediente`.
    private static func index(_ catalog: [CatalogIngredient]) -> [UUID: CatalogIngredient] {
        Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
