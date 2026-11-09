//
//  Navigator.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Estado de navegación de la interfaz (pestaña activa, hojas de edición abiertas), separado de los datos de la app.
//

import Foundation
import Observation

/// Pestañas de la barra inferior.
enum AppTab: Hashable {
    case meals, plan, shopping, ingredients, settings
}

/// Modo del editor de comidas: crear una nueva o editar una existente.
enum MealEditorMode: Identifiable {
    case new
    case edit(Meal)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let meal): meal.id.uuidString
        }
    }

    var meal: Meal? {
        switch self {
        case .new: nil
        case .edit(let meal): meal
        }
    }
}

/// Modo del editor de ingredientes del catálogo: crear uno nuevo o editar uno existente.
enum CatalogEditorMode: Identifiable {
    case new
    case edit(CatalogIngredient)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let ingredient): ingredient.id.uuidString
        }
    }

    var ingredient: CatalogIngredient? {
        switch self {
        case .new: nil
        case .edit(let ingredient): ingredient
        }
    }
}

/// Referencia a una comida del plan que se está editando.
struct PlannedMealRef: Identifiable {
    let id: String
}

/// Guarda qué pestaña está activa y qué hojas o diálogos hay abiertos.
@MainActor @Observable
final class Navigator {
    var selectedTab = AppTab.meals
    var mealEditor: MealEditorMode?
    var catalogEditor: CatalogEditorMode?
    var plannedMealEditor: PlannedMealRef?
    var mealToDelete: Meal?
}
