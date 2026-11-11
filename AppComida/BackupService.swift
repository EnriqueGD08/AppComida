//
//  BackupService.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Reglas de las copias de seguridad: validación del archivo importado y combinación (sin perder datos) con los datos actuales.
//

import Foundation

/// Cómo se aplica una copia de seguridad importada.
public enum BackupImportMode: Sendable {
    /// Sustituye por completo los datos actuales.
    case replace
    /// Añade lo que falte conservando los datos actuales.
    case merge
}

/// Errores al importar una copia de seguridad.
public enum BackupError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidData
}

extension BackupError: LocalizedError {
    /// Mensaje en español para mostrar al usuario.
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "La copia de seguridad usa una versión no compatible (\(version))."
        case .invalidData:
            "La copia de seguridad contiene datos no válidos."
        }
    }
}

/// Valida y combina copias de seguridad. Es lógica pura, sin acceso a disco ni a la interfaz.
public enum BackupService {
    /// Comprueba que una copia importada se puede usar.
    /// - Parameter backup: Copia a validar.
    /// - Throws: `BackupError.unsupportedVersion` si la versión no coincide o `BackupError.invalidData` si el objetivo no es positivo.
    public static func validate(_ backup: AppBackup) throws {
        guard backup.version == AppBackup.currentVersion else {
            throw BackupError.unsupportedVersion(backup.version)
        }
        guard backup.dailyCalorieGoal > 0 else {
            throw BackupError.invalidData
        }
    }

    /// Combina los datos actuales con una copia importada sin perder nada de lo actual.
    ///
    /// - Los ingredientes y comidas se identifican por nombre (sin distinguir mayúsculas ni tildes): si ya existe uno igual, se conserva el actual.
    /// - Las comidas importadas se reapuntan a los ingredientes que ya existían con el mismo nombre, y a esos ingredientes se les rellenan los datos que les faltaban (macronutrientes, peso por unidad, sección).
    /// - El plan, el objetivo y los favoritos actuales no se modifican; los productos manuales y lo que hay en casa se unen.
    /// - Parameters:
    ///   - current: Datos actuales.
    ///   - incoming: Copia importada (ya validada).
    /// - Returns: La copia resultante.
    public static func merge(current: AppBackup, incoming: AppBackup) -> AppBackup {
        var ingredients = current.ingredients
        var idByName = Dictionary(
            ingredients.map { ($0.name.searchKey, $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        var remap: [UUID: UUID] = [:]
        for ingredient in incoming.ingredients {
            let key = ingredient.name.searchKey
            if let existing = idByName[key] {
                remap[ingredient.id] = existing
                if let index = ingredients.firstIndex(where: { $0.id == existing }) {
                    ingredients[index] = fillingGaps(of: ingredients[index], from: ingredient)
                }
            } else {
                ingredients.append(ingredient)
                idByName[key] = ingredient.id
            }
        }

        var meals = current.meals
        var mealNames = Set(meals.map { $0.name.searchKey })
        for meal in incoming.meals where !mealNames.contains(meal.name.searchKey) {
            var copy = meal
            /// Reapunta un ingrediente al del catálogo actual con el mismo nombre, si lo hay.
            func remapped(_ ingredient: Ingredient) -> Ingredient {
                var updated = ingredient
                if let id = ingredient.catalogID, let mapped = remap[id] { updated.catalogID = mapped }
                return updated
            }
            copy.ingredients = meal.ingredients.map(remapped)
            copy.optionGroups = meal.optionGroups.map { group in
                var updatedGroup = group
                updatedGroup.options = group.options.map { option in
                    var updatedOption = option
                    updatedOption.ingredients = option.ingredients.map(remapped)
                    return updatedOption
                }
                return updatedGroup
            }
            meals.append(copy)
            mealNames.insert(meal.name.searchKey)
        }

        let currentExtras = current.extras ?? ShoppingExtras()
        let incomingExtras = incoming.extras ?? ShoppingExtras()
        let knownManual = Set(currentExtras.manualItems.map { $0.name.searchKey })
        let extras = ShoppingExtras(
            manualItems: currentExtras.manualItems + incomingExtras.manualItems.filter { !knownManual.contains($0.name.searchKey) },
            pantryKeys: Array(Set(currentExtras.pantryKeys + incomingExtras.pantryKeys)).sorted(),
            checkedKeys: currentExtras.checkedKeys
        )

        return AppBackup(
            meals: meals,
            ingredients: ingredients,
            plan: current.plan,
            dailyCalorieGoal: current.dailyCalorieGoal,
            extras: extras
        )
    }

    /// Completa los datos que le faltan a un ingrediente con los de otro equivalente, sin sobrescribir los que ya tiene.
    /// - Parameters:
    ///   - base: Ingrediente actual.
    ///   - donor: Ingrediente importado con el mismo nombre.
    /// - Returns: El ingrediente actual con macronutrientes, peso por unidad y sección rellenados si faltaban.
    private static func fillingGaps(of base: CatalogIngredient, from donor: CatalogIngredient) -> CatalogIngredient {
        var result = base
        result.protein = base.protein ?? donor.protein
        result.carbohydrates = base.carbohydrates ?? donor.carbohydrates
        result.fat = base.fat ?? donor.fat
        result.unitWeightGrams = base.unitWeightGrams ?? donor.unitWeightGrams
        result.category = base.category ?? donor.category
        return result
    }
}
