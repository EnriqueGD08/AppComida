//
//  MealModels.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-10-12
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Modelos de datos de la aplicación: franjas del día, ingredientes, comidas, plan semanal y copia de seguridad. Todos son `Codable` para guardarse como JSON y mantienen compatibilidad con datos guardados por versiones anteriores.
//

import Foundation

/// Franja del día a la que puede pertenecer una comida: desayuno, almuerzo, merienda o cena.
public nonisolated enum MealSlot: String, Codable, CaseIterable, Identifiable, Sendable {
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
public nonisolated struct Nutrition: Codable, Equatable, Sendable {
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

    /// Devuelve la información nutricional multiplicada por un factor.
    /// - Parameter factor: Factor de escala (por ejemplo, `1 / raciones`).
    /// - Returns: Una nueva `Nutrition` escalada.
    public func scaled(by factor: Double) -> Nutrition {
        Nutrition(protein: protein * factor, carbohydrates: carbohydrates * factor, fat: fat * factor)
    }

    /// Suma dos informaciones nutricionales.
    /// - Parameters:
    ///   - lhs: Primer sumando.
    ///   - rhs: Segundo sumando.
    /// - Returns: La suma de cada macronutriente.
    public static func + (lhs: Nutrition, rhs: Nutrition) -> Nutrition {
        Nutrition(
            protein: lhs.protein + rhs.protein,
            carbohydrates: lhs.carbohydrates + rhs.carbohydrates,
            fat: lhs.fat + rhs.fat
        )
    }
}

/// Ingrediente concreto dentro de una comida, con su cantidad.
///
/// Si `catalogID` y `grams` están definidos, la cantidad procede del catálogo de ingredientes y se usa para calcular las calorías.
public nonisolated struct Ingredient: Codable, Identifiable, Equatable, Sendable {
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
public nonisolated enum CalorieUnit: String, Codable, CaseIterable, Identifiable, Sendable {
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

/// Sección del supermercado en la que se encuentra un ingrediente. Se usa para agrupar la lista de la compra.
///
/// El orden de los casos es el orden en que aparecen las secciones.
public nonisolated enum IngredientCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case produce, meatFish, dairyEggs, bakeryCereals, legumes, nuts, pantry, other

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .produce: "Frutas y verduras"
        case .meatFish: "Carne y pescado"
        case .dairyEggs: "Lácteos y huevos"
        case .bakeryCereals: "Pan, pasta y cereales"
        case .legumes: "Legumbres"
        case .nuts: "Frutos secos y semillas"
        case .pantry: "Despensa"
        case .other: "Otros"
        }
    }
}

/// Ingrediente del catálogo reutilizable al crear comidas, con sus calorías y datos opcionales.
///
/// Los macronutrientes (`protein`, `carbohydrates`, `fat`) se expresan siempre por cada 100 g.
/// `unitWeightGrams` es el peso de una unidad (un huevo, una manzana…) y permite mostrar cantidades en unidades.
public nonisolated struct CatalogIngredient: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var calories: Double
    public var calorieUnit: CalorieUnit
    public var protein: Double?
    public var carbohydrates: Double?
    public var fat: Double?
    public var unitWeightGrams: Double?
    public var category: IngredientCategory?

    /// Crea un ingrediente del catálogo.
    /// - Parameters:
    ///   - id: Identificador único.
    ///   - name: Nombre del ingrediente.
    ///   - calories: Calorías según `calorieUnit`.
    ///   - calorieUnit: Si las calorías son por cada 100 g o por gramo.
    ///   - protein: Proteínas por cada 100 g, si se conocen.
    ///   - carbohydrates: Hidratos por cada 100 g, si se conocen.
    ///   - fat: Grasas por cada 100 g, si se conocen.
    ///   - unitWeightGrams: Peso en gramos de una unidad, si tiene sentido contarlo por unidades.
    ///   - category: Sección del supermercado.
    public init(
        id: UUID = UUID(),
        name: String,
        calories: Double,
        calorieUnit: CalorieUnit = .per100Grams,
        protein: Double? = nil,
        carbohydrates: Double? = nil,
        fat: Double? = nil,
        unitWeightGrams: Double? = nil,
        category: IngredientCategory? = nil
    ) {
        self.id = id
        self.name = name
        self.calories = calories
        self.calorieUnit = calorieUnit
        self.protein = protein
        self.carbohydrates = carbohydrates
        self.fat = fat
        self.unitWeightGrams = unitWeightGrams
        self.category = category
    }

    /// Calorías por gramo, independientemente de la unidad en que se introdujeron.
    public var caloriesPerGram: Double {
        calorieUnit == .per100Grams ? calories / 100 : calories
    }

    /// Macronutrientes por cada 100 g, o `nil` si falta alguno de los tres datos.
    public var macrosPer100g: Nutrition? {
        guard let protein, let carbohydrates, let fat else { return nil }
        return Nutrition(protein: protein, carbohydrates: carbohydrates, fat: fat)
    }
}

/// Comida o receta: franjas en las que se puede tomar, calorías, raciones, ingredientes y pasos de preparación.
///
/// `calories` y `nutrition` corresponden a la receta completa; para una ración usa `caloriesPerServing` y `nutritionPerServing`.
public nonisolated struct Meal: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var mealSlots: [MealSlot]
    public var calories: Int
    public var servings: Int
    public var nutrition: Nutrition
    public var ingredients: [Ingredient]
    public var steps: [String]
    public var isFavorite: Bool

    /// Crea una comida.
    /// - Parameters:
    ///   - id: Identificador único.
    ///   - name: Nombre de la comida.
    ///   - suggestedSlot: Franja principal, usada si `mealSlots` es `nil`.
    ///   - mealSlots: Franjas en las que se puede tomar.
    ///   - calories: Calorías totales de la receta completa.
    ///   - servings: Número de raciones que da la receta.
    ///   - nutrition: Información nutricional de la receta completa.
    ///   - ingredients: Ingredientes de la receta.
    ///   - steps: Pasos de preparación.
    ///   - isFavorite: Si la comida está marcada como favorita.
    public init(
        id: UUID = UUID(),
        name: String,
        suggestedSlot: MealSlot,
        mealSlots: [MealSlot]? = nil,
        calories: Int,
        servings: Int = 1,
        nutrition: Nutrition = Nutrition(),
        ingredients: [Ingredient] = [],
        steps: [String] = [],
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.mealSlots = mealSlots ?? [suggestedSlot]
        self.calories = calories
        self.servings = servings
        self.nutrition = nutrition
        self.ingredients = ingredients
        self.steps = steps
        self.isFavorite = isFavorite
    }

    /// Primera franja de la comida; compatibilidad con datos antiguos que solo tenían una.
    public var suggestedSlot: MealSlot {
        get { mealSlots.first ?? .breakfast }
        set { mealSlots = [newValue] }
    }

    /// Claves usadas al codificar y decodificar `Meal` en JSON (incluye `suggestedSlot` por compatibilidad).
    private enum CodingKeys: String, CodingKey {
        case id, name, mealSlots, suggestedSlot, calories, servings, nutrition, ingredients, steps, isFavorite
    }

    /// Decodifica una comida desde JSON. Si no hay `mealSlots` usa `suggestedSlot`, si no hay `servings` asume 1 y si no hay `isFavorite` asume `false`.
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
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
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
        try container.encode(isFavorite, forKey: .isFavorite)
    }

    /// Calorías de una ración, redondeadas al entero más cercano.
    public var caloriesPerServing: Int {
        Int((Double(calories) / Double(max(servings, 1))).rounded())
    }

    /// Macronutrientes de una ración.
    public var nutritionPerServing: Nutrition {
        nutrition.scaled(by: 1 / Double(max(servings, 1)))
    }
}

/// Comida asignada a una franja de un día concreto del plan semanal.
///
/// `servings` indica cuántas raciones se toman (admite medias raciones) y `isLocked`
/// hace que se conserve al regenerar el menú.
public nonisolated struct PlannedMeal: Codable, Equatable, Identifiable, Sendable {
    public var date: Date
    public var slot: MealSlot
    public var mealID: UUID
    public var servings: Double
    public var isLocked: Bool

    /// Identificador estable de la franja (día + franja), válido mientras el plan no cambie de semana.
    public var id: String { "\(Int(date.timeIntervalSince1970))-\(slot.rawValue)" }

    /// Crea una comida planificada.
    /// - Parameters:
    ///   - date: Día al que corresponde.
    ///   - slot: Franja del día.
    ///   - mealID: Identificador de la comida asignada.
    ///   - servings: Raciones que se toman.
    ///   - isLocked: Si se conserva al regenerar el menú.
    public init(date: Date, slot: MealSlot, mealID: UUID, servings: Double = 1, isLocked: Bool = false) {
        self.date = date
        self.slot = slot
        self.mealID = mealID
        self.servings = servings
        self.isLocked = isLocked
    }

    /// Claves usadas al codificar y decodificar `PlannedMeal` en JSON.
    private enum CodingKeys: String, CodingKey {
        case date, slot, mealID, servings, isLocked
    }

    /// Decodifica una comida planificada. Si faltan `servings` o `isLocked` (datos antiguos) usa 1 ración y sin bloquear.
    /// - Parameter decoder: Decodificador del que se leen los datos.
    /// - Throws: Un error si falta algún campo obligatorio.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        slot = try container.decode(MealSlot.self, forKey: .slot)
        mealID = try container.decode(UUID.self, forKey: .mealID)
        servings = try container.decodeIfPresent(Double.self, forKey: .servings) ?? 1
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
    }

    /// Codifica la comida planificada en JSON (sin la propiedad calculada `id`).
    /// - Parameter encoder: Codificador donde se escriben los datos.
    /// - Throws: Un error si falla la codificación.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(slot, forKey: .slot)
        try container.encode(mealID, forKey: .mealID)
        try container.encode(servings, forKey: .servings)
        try container.encode(isLocked, forKey: .isLocked)
    }
}

/// Un día del plan con sus comidas ordenadas por franja.
public nonisolated struct PlanDay: Identifiable, Equatable, Sendable {
    public var date: Date
    public var meals: [PlannedMeal]
    public var id: Date { date }
}

/// Plan semanal: lista de comidas planificadas a partir del día de inicio de la semana.
public nonisolated struct WeeklyPlan: Codable, Equatable, Sendable {
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

    /// Calcula el primer día de la semana que contiene una fecha.
    /// - Parameters:
    ///   - date: Fecha de referencia.
    ///   - calendar: Calendario a usar.
    /// - Returns: El inicio de la semana, o la propia fecha si no se puede calcular.
    public static func startOfWeek(containing date: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    /// Indica si el plan corresponde a la semana de una fecha.
    /// - Parameters:
    ///   - date: Fecha de referencia.
    ///   - calendar: Calendario a usar.
    /// - Returns: `true` si el plan empieza en la misma semana que `date`.
    public func isCurrent(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.isDate(weekStart, equalTo: Self.startOfWeek(containing: date, calendar: calendar), toGranularity: .day)
    }

    /// Agrupa las comidas por día, con los días y las franjas ordenados.
    /// - Parameter calendar: Calendario usado para agrupar.
    /// - Returns: Una entrada por día del plan.
    public func days(calendar: Calendar = .current) -> [PlanDay] {
        let order = Dictionary(uniqueKeysWithValues: MealSlot.allCases.enumerated().map { ($1, $0) })
        return Dictionary(grouping: meals) { calendar.startOfDay(for: $0.date) }
            .map { day, items in
                PlanDay(date: day, meals: items.sorted { (order[$0.slot] ?? 0) < (order[$1.slot] ?? 0) })
            }
            .sorted { $0.date < $1.date }
    }

    /// Modifica una comida planificada identificada por su `id`.
    /// - Parameters:
    ///   - id: Identificador de la franja (`PlannedMeal.id`).
    ///   - transform: Cambio a aplicar.
    /// - Returns: `true` si se encontró la franja.
    @discardableResult
    public mutating func update(_ id: String, _ transform: (inout PlannedMeal) -> Void) -> Bool {
        guard let index = meals.firstIndex(where: { $0.id == id }) else { return false }
        transform(&meals[index])
        return true
    }
}

/// Producto añadido a mano a la lista de la compra.
public nonisolated struct ManualShoppingItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var quantity: String

    /// Crea un producto manual.
    /// - Parameters:
    ///   - id: Identificador único.
    ///   - name: Nombre del producto.
    ///   - quantity: Cantidad en texto libre (puede estar vacía).
    public init(id: UUID = UUID(), name: String, quantity: String = "") {
        self.id = id
        self.name = name
        self.quantity = quantity
    }
}

/// Datos de la lista de la compra que no se derivan del plan: productos manuales, lo que ya hay en casa y lo marcado como comprado.
public nonisolated struct ShoppingExtras: Codable, Equatable, Sendable {
    public var manualItems: [ManualShoppingItem]
    public var pantryKeys: [String]
    public var checkedKeys: [String]

    /// Crea los datos extra de la lista de la compra.
    /// - Parameters:
    ///   - manualItems: Productos añadidos a mano.
    ///   - pantryKeys: Claves (`searchKey`) de los ingredientes que ya hay en casa.
    ///   - checkedKeys: Claves de los productos marcados como comprados.
    public init(manualItems: [ManualShoppingItem] = [], pantryKeys: [String] = [], checkedKeys: [String] = []) {
        self.manualItems = manualItems
        self.pantryKeys = pantryKeys
        self.checkedKeys = checkedKeys
    }
}

/// Copia de seguridad completa de los datos de la app, exportable e importable como JSON.
public nonisolated struct AppBackup: Codable, Equatable, Sendable {
    /// Versión actual del formato de la copia de seguridad.
    public static let currentVersion = 1

    public let version: Int
    public let meals: [Meal]
    public let ingredients: [CatalogIngredient]
    public let plan: WeeklyPlan?
    public let dailyCalorieGoal: Int
    public let extras: ShoppingExtras?

    /// Crea una copia de seguridad.
    /// - Parameters:
    ///   - meals: Comidas guardadas.
    ///   - ingredients: Catálogo de ingredientes.
    ///   - plan: Plan semanal, si existe.
    ///   - dailyCalorieGoal: Objetivo calórico diario.
    ///   - extras: Datos extra de la lista de la compra, si existen.
    ///   - version: Versión del formato.
    public init(
        meals: [Meal],
        ingredients: [CatalogIngredient],
        plan: WeeklyPlan?,
        dailyCalorieGoal: Int,
        extras: ShoppingExtras? = nil,
        version: Int = AppBackup.currentVersion
    ) {
        self.version = version
        self.meals = meals
        self.ingredients = ingredients
        self.plan = plan
        self.dailyCalorieGoal = dailyCalorieGoal
        self.extras = extras
    }
}
