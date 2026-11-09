//
//  MealStore.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-10-12
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Persistencia local. Define protocolos pequeños por tipo de dato (principio de segregación de interfaces), su implementación en archivos JSON (`FileMealStore`) y las comidas de ejemplo iniciales.
//

import Foundation

/// Acceso a las comidas guardadas.
public protocol MealRepository: Sendable {
    /// Carga las comidas guardadas.
    /// - Returns: Las comidas almacenadas.
    /// - Throws: Un error si no se pueden leer o decodificar.
    func loadMeals() throws -> [Meal]

    /// Guarda las comidas, reemplazando las anteriores.
    /// - Parameter meals: Comidas a guardar.
    /// - Throws: Un error si no se puede escribir.
    func saveMeals(_ meals: [Meal]) throws
}

/// Acceso al catálogo de ingredientes.
public protocol IngredientRepository: Sendable {
    /// Carga el catálogo de ingredientes.
    /// - Returns: Los ingredientes almacenados.
    /// - Throws: Un error si no se pueden leer o decodificar.
    func loadIngredients() throws -> [CatalogIngredient]

    /// Guarda el catálogo de ingredientes, reemplazando el anterior.
    /// - Parameter ingredients: Ingredientes a guardar.
    /// - Throws: Un error si no se puede escribir.
    func saveIngredients(_ ingredients: [CatalogIngredient]) throws
}

/// Acceso al plan semanal.
public protocol PlanRepository: Sendable {
    /// Carga el plan semanal guardado.
    /// - Returns: El plan, o `nil` si no hay ninguno.
    /// - Throws: Un error si no se puede leer o decodificar.
    func loadPlan() throws -> WeeklyPlan?

    /// Guarda el plan semanal, reemplazando el anterior.
    /// - Parameter plan: Plan a guardar.
    /// - Throws: Un error si no se puede escribir.
    func savePlan(_ plan: WeeklyPlan) throws

    /// Elimina el plan semanal guardado, si existe.
    /// - Throws: Un error si no se puede borrar.
    func deletePlan() throws
}

/// Acceso al objetivo calórico diario.
public protocol GoalRepository: Sendable {
    /// Carga el objetivo calórico diario.
    /// - Returns: El objetivo guardado (2000 kcal por defecto).
    /// - Throws: Un error si no se puede leer o decodificar.
    func loadDailyCalorieGoal() throws -> Int

    /// Guarda el objetivo calórico diario.
    /// - Parameter goal: Calorías diarias objetivo.
    /// - Throws: Un error si no se puede escribir.
    func saveDailyCalorieGoal(_ goal: Int) throws
}

/// Acceso a los datos extra de la lista de la compra.
public protocol ShoppingExtrasRepository: Sendable {
    /// Carga los productos manuales, lo que hay en casa y lo marcado como comprado.
    /// - Returns: Los datos guardados, o unos vacíos si no hay ninguno.
    /// - Throws: Un error si no se puede leer o decodificar.
    func loadShoppingExtras() throws -> ShoppingExtras

    /// Guarda los datos extra de la lista de la compra.
    /// - Parameter extras: Datos a guardar.
    /// - Throws: Un error si no se puede escribir.
    func saveShoppingExtras(_ extras: ShoppingExtras) throws
}

/// Almacén completo de la app: combina todos los repositorios.
///
/// Quien solo necesite una parte puede depender del protocolo concreto (por ejemplo, `MealRepository`).
public typealias MealStore = MealRepository & IngredientRepository & PlanRepository & GoalRepository & ShoppingExtrasRepository

/// Implementación de `MealStore` que guarda cada conjunto de datos en un archivo JSON dentro de Application Support.
public final class FileMealStore: MealStore, @unchecked Sendable {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Crea el almacén y asegura que el directorio existe.
    /// - Parameter directory: Carpeta donde guardar los archivos; por defecto `Application Support/MealPlanner`.
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MealPlanner", isDirectory: true)
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// Carga las comidas de `meals.json`.
    /// - Returns: Las comidas guardadas, o `SampleMeals.all` si todavía no hay archivo.
    /// - Throws: Un error si el archivo existe pero no se puede leer o decodificar.
    public func loadMeals() throws -> [Meal] {
        try read([Meal].self, from: "meals.json") ?? SampleMeals.all
    }

    /// Guarda las comidas en `meals.json`.
    /// - Parameter meals: Comidas a guardar.
    /// - Throws: Un error si no se puede escribir.
    public func saveMeals(_ meals: [Meal]) throws {
        try write(meals, to: "meals.json")
    }

    /// Carga el catálogo de `ingredients.json`.
    /// - Returns: Los ingredientes guardados, o una lista vacía si no hay archivo.
    /// - Throws: Un error si el archivo existe pero no se puede leer o decodificar.
    public func loadIngredients() throws -> [CatalogIngredient] {
        try read([CatalogIngredient].self, from: "ingredients.json") ?? []
    }

    /// Guarda el catálogo en `ingredients.json`.
    /// - Parameter ingredients: Ingredientes a guardar.
    /// - Throws: Un error si no se puede escribir.
    public func saveIngredients(_ ingredients: [CatalogIngredient]) throws {
        try write(ingredients, to: "ingredients.json")
    }

    /// Carga el plan de `plan.json`.
    /// - Returns: El plan guardado, o `nil` si no hay archivo.
    /// - Throws: Un error si el archivo existe pero no se puede leer o decodificar.
    public func loadPlan() throws -> WeeklyPlan? {
        try read(WeeklyPlan.self, from: "plan.json")
    }

    /// Guarda el plan en `plan.json`.
    /// - Parameter plan: Plan a guardar.
    /// - Throws: Un error si no se puede escribir.
    public func savePlan(_ plan: WeeklyPlan) throws {
        try write(plan, to: "plan.json")
    }

    /// Borra `plan.json` si existe.
    /// - Throws: Un error si no se puede eliminar el archivo.
    public func deletePlan() throws {
        let url = directory.appendingPathComponent("plan.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Carga el objetivo de `calorie-goal.json`.
    /// - Returns: El objetivo guardado, o 2000 kcal si no hay archivo.
    /// - Throws: Un error si el archivo existe pero no se puede leer o decodificar.
    public func loadDailyCalorieGoal() throws -> Int {
        try read(Int.self, from: "calorie-goal.json") ?? 2_000
    }

    /// Guarda el objetivo en `calorie-goal.json`.
    /// - Parameter goal: Calorías diarias objetivo.
    /// - Throws: Un error si no se puede escribir.
    public func saveDailyCalorieGoal(_ goal: Int) throws {
        try write(goal, to: "calorie-goal.json")
    }

    /// Carga los datos extra de la compra de `shopping-extras.json`.
    /// - Returns: Los datos guardados, o unos vacíos si no hay archivo.
    /// - Throws: Un error si el archivo existe pero no se puede leer o decodificar.
    public func loadShoppingExtras() throws -> ShoppingExtras {
        try read(ShoppingExtras.self, from: "shopping-extras.json") ?? ShoppingExtras()
    }

    /// Guarda los datos extra de la compra en `shopping-extras.json`.
    /// - Parameter extras: Datos a guardar.
    /// - Throws: Un error si no se puede escribir.
    public func saveShoppingExtras(_ extras: ShoppingExtras) throws {
        try write(extras, to: "shopping-extras.json")
    }

    /// Lee y decodifica un archivo JSON del directorio de datos.
    /// - Parameters:
    ///   - type: Tipo al que decodificar.
    ///   - filename: Nombre del archivo.
    /// - Returns: El valor decodificado, o `nil` si el archivo no existe.
    /// - Throws: Un error si no se puede leer o decodificar.
    private func read<T: Decodable>(_ type: T.Type, from filename: String) throws -> T? {
        let url = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do {
            return try decoder.decode(type, from: data)
        } catch let error as DecodingError {
            quarantine(url)
            throw error
        }
    }

    /// Aparta un archivo ilegible renombrándolo con la extensión `.corrupt`, para que no se sobrescriba y los datos puedan recuperarse a mano.
    /// - Parameter url: Archivo dañado.
    private func quarantine(_ url: URL) {
        let target = url.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.moveItem(at: url, to: target)
    }

    /// Codifica un valor y lo escribe de forma atómica en el directorio de datos.
    /// - Parameters:
    ///   - value: Valor a guardar.
    ///   - filename: Nombre del archivo de destino.
    /// - Throws: Un error si falla la codificación o la escritura.
    private func write<T: Encodable>(_ value: T, to filename: String) throws {
        let data = try encoder.encode(value)
        try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
    }
}

/// Comidas de ejemplo (una por franja) que se muestran la primera vez que se abre la app.
public enum SampleMeals {
    public static let all: [Meal] = [
        Meal(name: "Avena con plátano", suggestedSlot: .breakfast, calories: 420,
             nutrition: Nutrition(protein: 14, carbohydrates: 65, fat: 11),
             ingredients: [Ingredient(name: "Avena", quantity: "60 g"), Ingredient(name: "Plátano", quantity: "1 unidad")],
             steps: ["Cocer la avena con leche.", "Añadir el plátano en rodajas."]),
        Meal(name: "Ensalada de pollo", suggestedSlot: .lunch, calories: 560,
             nutrition: Nutrition(protein: 42, carbohydrates: 35, fat: 24),
             ingredients: [Ingredient(name: "Pechuga de pollo", quantity: "150 g"), Ingredient(name: "Verduras", quantity: "200 g")],
             steps: ["Cocinar el pollo.", "Mezclar con las verduras."]),
        Meal(name: "Yogur con frutos secos", suggestedSlot: .snack, calories: 280,
             nutrition: Nutrition(protein: 15, carbohydrates: 20, fat: 14),
             ingredients: [Ingredient(name: "Yogur natural", quantity: "200 g"), Ingredient(name: "Frutos secos", quantity: "20 g")],
             steps: ["Servir el yogur.", "Añadir los frutos secos."]),
        Meal(name: "Salmón con patata", suggestedSlot: .dinner, calories: 640,
             nutrition: Nutrition(protein: 38, carbohydrates: 48, fat: 29),
             ingredients: [Ingredient(name: "Salmón", quantity: "160 g"), Ingredient(name: "Patata", quantity: "200 g")],
             steps: ["Hornear el salmón.", "Cocer la patata y servir."])
    ]
}
