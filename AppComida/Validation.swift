//
//  Validation.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Reglas de validación de comidas e ingredientes del catálogo, separadas de la interfaz para poder probarlas y reutilizarlas.
//

import Foundation

/// Valida los datos de una comida antes de guardarla.
public enum MealValidator {
    /// Comprueba que una comida es correcta.
    /// - Parameters:
    ///   - meal: Comida a validar (con el nombre ya recortado).
    ///   - catalog: Catálogo de ingredientes, para comprobar que cada ingrediente existe.
    /// - Returns: El mensaje del primer problema encontrado, o `nil` si todo es correcto.
    public static func validate(_ meal: Meal, catalog: [CatalogIngredient]) -> String? {
        if meal.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Indica un nombre para la comida."
        }
        if meal.mealSlots.isEmpty {
            return "Selecciona al menos un tipo de comida."
        }
        if meal.ingredients.isEmpty {
            return "Añade al menos un ingrediente."
        }
        let known = Set(catalog.map(\.id))
        let ingredientsAreValid = meal.ingredients.allSatisfy { ingredient in
            guard let id = ingredient.catalogID, known.contains(id), let grams = ingredient.grams else { return false }
            return grams > 0
        }
        if !ingredientsAreValid {
            return "Selecciona un ingrediente registrado y una cantidad de gramos mayor que cero para cada ingrediente."
        }
        if meal.servings <= 0 {
            return "Las raciones deben ser mayores que cero."
        }
        if meal.nutrition.protein < 0 || meal.nutrition.carbohydrates < 0 || meal.nutrition.fat < 0 {
            return "Los valores nutricionales no pueden ser negativos."
        }
        return nil
    }
}

/// Valida los datos de un ingrediente del catálogo antes de guardarlo.
public enum CatalogIngredientValidator {
    /// Comprueba que un ingrediente del catálogo es correcto.
    /// - Parameter ingredient: Ingrediente a validar.
    /// - Returns: El mensaje del primer problema encontrado, o `nil` si todo es correcto.
    public static func validate(_ ingredient: CatalogIngredient) -> String? {
        if ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Indica un nombre para el ingrediente."
        }
        if ingredient.calories <= 0 {
            return "Las calorías deben ser mayores que cero."
        }
        if [ingredient.protein, ingredient.carbohydrates, ingredient.fat].contains(where: { ($0 ?? 0) < 0 }) {
            return "Los macronutrientes no pueden ser negativos."
        }
        if let weight = ingredient.unitWeightGrams, weight <= 0 {
            return "El peso de una unidad debe ser mayor que cero."
        }
        return nil
    }
}
