//
//  MealModels.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-10-12
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Modelos de datos de la aplicación: franjas del día, ingredientes, comidas, plan semanal y copia de seguridad. Todos son `Codable` para guardarse como JSON.
//

import Foundation

/// Franja del día a la que puede pertenecer una comida: desayuno, almuerzo, merienda o cena.
public enum MealSlot: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast, lunch, snack, dinner

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .breakfast: "Desayuno"
        case .lunch: "Almuerzo"
        case .snack: "Merienda"
        case .dinner: "Cena"
        }
    }
}

/// Información nutricional (en gramos) de una comida.
public struct Nutrition: Codable, Equatable, Sendable {
    public var protein: Double
    public var carbohydrates: Double
    public var fat: Double

    /// Crea la información nutricional.
    /// - Parameters:
    ///   - protein: Proteínas en gramos.
    ///   - carbohydrates: Hidratos de carbono en gramos.
    ///   - fat: Grasas en gramos.
    public init(protein: Double = 0, carbohydrates: Double = 0, fat: Double = 0) {
        self.protein = protein
        self.carbohydrates = carbohydrates
        self.fat = fat
    }
}

/// Ingrediente concreto dentro de una comida, con su cantidad.
///
/// Si `catalogID` y `grams` están definidos, la cantidad procede del catálogo de ingredientes y se usa para calcular las calorías.
public struct Ingredient: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var quantity: String
    public var catalogID: UUID?
    public var grams: Double?

    /// Crea un ingrediente de una comida.
    /// - Parameters:
    ///   - id: Identificador único.
    ///   - name: Nombre mostrado.
    ///   - quantity: Cantidad en texto libre (por ejemplo "60 g" o "1 unidad").
    ///   - catalogID: Identificador del ingrediente del catálogo asociado, si lo hay.
    ///   - grams: Cantidad en gramos, si se conoce.
    public init(
        id: UUID = UUID(),
        name: String,
        quantity: String,
        catalogID: UUID? = nil,
        grams: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.catalogID = catalogID
        self.grams = grams
    }

    /// Claves usadas al codificar y decodificar `Ingredient` en JSON.
    private enum CodingKeys: String, CodingKey {
        case id, name, quantity, catalogID, grams
    }

    /// Decodifica un ingrediente desde JSON. `catalogID` y `grams` son opcionales para poder leer copias antiguas.
    /// - Parameter decoder: Decodificador del que se leen los datos.
    /// - Throws: Un error si falta algún campo obligatorio.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        quantity = try container.decode(String.self, forKey: .quantity)
        catalogID = try container.decodeIfPresent(UUID.self, forKey: .catalogID)
        grams = try container.decodeIfPresent(Double.self, forKey: .grams)
    }

    /// Codifica el ingrediente en JSON omitiendo los campos opcionales vacíos.
    /// - Parameter encoder: Codificador donde se escriben los datos.
    /// - Throws: Un error si falla la codificación.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(quantity, forKey: .quantity)
        try container.encodeIfPresent(catalogID, forKey: .catalogID)
        try container.encodeIfPresent(grams, forKey: .grams)
    }
}

/// Unidad en la que se expresan las calorías de un ingrediente del catálogo.
public enum CalorieUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case per100Grams
    case perGram

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .per100Grams: "Por cada 100 g"
        case .perGram: "Por cada gramo"
        }
    }
}

/// Ingrediente del catálogo reutilizable al crear comidas, con sus calorías.
public struct CatalogIngredient: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var calories: Double
    public var calorieUnit: CalorieUnit

    /// Crea un ingrediente del catálogo.
    /// - Parameters:
    ///   - id: Identificador único.
    ///   - name: Nombre del ingrediente.
    ///   - calories: Calorías según `calorieUnit`.
    ///   - calorieUnit: Si las calorías son por cada 100 g o por gramo.
    public init(
        id: UUID = UUID(),
        name: String,
        calories: Double,
        calorieUnit: CalorieUnit = .per100Grams
    ) {
        self.id = id
        self.name = name
        self.calories = calories
        self.calorieUnit = calorieUnit
    }

    /// Calorías por gramo, independientemente de la unidad en que se introdujeron.
    public var caloriesPerGram: Double {
        calorieUnit == .per100Grams ? calories / 100 : calories
    }
}

/// Comida o receta: franjas en las que se puede tomar, calorías, raciones, ingredientes y pasos de preparación.
public struct Meal: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var mealSlots: [MealSlot]
    public var calories: Int
    public var servings: Int
    public var nutrition: Nutrition
    public var ingredients: [Ingredient]
    public var steps: [String]

    /// Crea una comida.
    /// - Parameters:
    ///   - id: Identificador único.
    ///   - name: Nombre de la comida.
    ///   - suggestedSlot: Franja principal, usada si `mealSlots` es `nil`.
    ///   - mealSlots: Franjas en las que se puede tomar.
    ///   - calories: Calorías totales de la receta completa.
    ///   - servings: Número de raciones que da la receta.
    ///   - nutrition: Información nutricional.
    ///   - ingredients: Ingredientes de la receta.
    ///   - steps: Pasos de preparación.
    public init(
        id: UUID = UUID(),
        name: String,
        suggestedSlot: MealSlot,
        mealSlots: [MealSlot]? = nil,
        calories: Int,
        servings: Int = 1,
        nutrition: Nutrition = Nutrition(),
        ingredients: [Ingredient] = [],
        steps: [String] = []
    ) {
        self.id = id
        self.name = name
        self.mealSlots = mealSlots ?? [suggestedSlot]
        self.calories = calories
        self.servings = servings
        self.nutrition = nutrition
        self.ingredients = ingredients
        self.steps = steps
    }

    /// Primera franja de la comida; compatibilidad con datos antiguos que solo tenían una.
    public var suggestedSlot: MealSlot {
        get { mealSlots.first ?? .breakfast }
        set { mealSlots = [newValue] }
    }

    /// Claves usadas al codificar y decodificar `Meal` en JSON (incluye `suggestedSlot` por compatibilidad).
    private enum CodingKeys: String, CodingKey {
        case id, name, mealSlots, suggestedSlot, calories, servings, nutrition, ingredients, steps
    }

    /// Decodifica una comida desde JSON. Si no hay `mealSlots` usa `suggestedSlot`, y si no hay `servings` asume 1.
    /// - Parameter decoder: Decodificador del que se leen los datos.
    /// - Throws: Un error si falta algún campo obligatorio.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        mealSlots = try container.decodeIfPresent([MealSlot].self, forKey: .mealSlots)
            ?? [try container.decode(MealSlot.self, forKey: .suggestedSlot)]
        calories = try container.decode(Int.self, forKey: .calories)
        servings = try container.decodeIfPresent(Int.self, forKey: .servings) ?? 1
        nutrition = try container.decode(Nutrition.self, forKey: .nutrition)
        ingredients = try container.decode([Ingredient].self, forKey: .ingredients)
        steps = try container.decode([String].self, forKey: .steps)
    }

    /// Codifica la comida en JSON.
    /// - Parameter encoder: Codificador donde se escriben los datos.
    /// - Throws: Un error si falla la codificación.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(mealSlots, forKey: .mealSlots)
        try container.encode(calories, forKey: .calories)
        try container.encode(servings, forKey: .servings)
        try container.encode(nutrition, forKey: .nutrition)
        try container.encode(ingredients, forKey: .ingredients)
        try container.encode(steps, forKey: .steps)
    }

    /// Calorías de una ración, redondeadas al entero más cercano.
    public var caloriesPerServing: Int {
        Int((Double(calories) / Double(servings)).rounded())
    }
}

/// Comida asignada a una franja de un día concreto del plan semanal (equivale a una ración).
public struct PlannedMeal: Codable, Equatable, Sendable {
    public var date: Date
    public var slot: MealSlot
    public var mealID: UUID

    /// Crea una comida planificada.
    /// - Parameters:
    ///   - date: Día al que corresponde.
    ///   - slot: Franja del día.
    ///   - mealID: Identificador de la comida asignada.
    public init(date: Date, slot: MealSlot, mealID: UUID) {
        self.date = date
        self.slot = slot
        self.mealID = mealID
    }
}

/// Plan semanal: lista de comidas planificadas a partir del día de inicio de la semana.
public struct WeeklyPlan: Codable, Equatable, Sendable {
    public var weekStart: Date
    public var meals: [PlannedMeal]

    /// Crea un plan semanal.
    /// - Parameters:
    ///   - weekStart: Primer día de la semana.
    ///   - meals: Comidas planificadas.
    public init(weekStart: Date, meals: [PlannedMeal] = []) {
        self.weekStart = weekStart
        self.meals = meals
    }
}

/// Copia de seguridad completa de los datos de la app, exportable e importable como JSON.
public struct AppBackup: Codable, Equatable, Sendable {
    /// Versión actual del formato de la copia de seguridad.
    public static let currentVersion = 1

    public let version: Int
    public let meals: [Meal]
    public let ingredients: [CatalogIngredient]
    public let plan: WeeklyPlan?
    public let dailyCalorieGoal: Int

    /// Crea una copia de seguridad.
    /// - Parameters:
    ///   - meals: Comidas guardadas.
    ///   - ingredients: Catálogo de ingredientes.
    ///   - plan: Plan semanal, si existe.
    ///   - dailyCalorieGoal: Objetivo calórico diario.
    ///   - version: Versión del formato.
    public init(
        meals: [Meal],
        ingredients: [CatalogIngredient],
        plan: WeeklyPlan?,
        dailyCalorieGoal: Int,
        version: Int = AppBackup.currentVersion
    ) {
        self.version = version
        self.meals = meals
        self.ingredients = ingredients
        self.plan = plan
        self.dailyCalorieGoal = dailyCalorieGoal
    }
}
