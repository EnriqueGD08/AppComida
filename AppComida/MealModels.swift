import Foundation

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

public struct Nutrition: Codable, Equatable, Sendable {
    public var protein: Double
    public var carbohydrates: Double
    public var fat: Double

    public init(protein: Double = 0, carbohydrates: Double = 0, fat: Double = 0) {
        self.protein = protein
        self.carbohydrates = carbohydrates
        self.fat = fat
    }
}

public struct Ingredient: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var quantity: String
    public var catalogID: UUID?
    public var grams: Double?

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

    private enum CodingKeys: String, CodingKey {
        case id, name, quantity, catalogID, grams
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        quantity = try container.decode(String.self, forKey: .quantity)
        catalogID = try container.decodeIfPresent(UUID.self, forKey: .catalogID)
        grams = try container.decodeIfPresent(Double.self, forKey: .grams)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(quantity, forKey: .quantity)
        try container.encodeIfPresent(catalogID, forKey: .catalogID)
        try container.encodeIfPresent(grams, forKey: .grams)
    }
}

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

public struct CatalogIngredient: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var calories: Double
    public var calorieUnit: CalorieUnit

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

    public var caloriesPerGram: Double {
        calorieUnit == .per100Grams ? calories / 100 : calories
    }
}

public struct Meal: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var mealSlots: [MealSlot]
    public var calories: Int
    public var servings: Int
    public var nutrition: Nutrition
    public var ingredients: [Ingredient]
    public var steps: [String]

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

    public var suggestedSlot: MealSlot {
        get { mealSlots.first ?? .breakfast }
        set { mealSlots = [newValue] }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, mealSlots, suggestedSlot, calories, servings, nutrition, ingredients, steps
    }

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

    public var caloriesPerServing: Int {
        Int((Double(calories) / Double(servings)).rounded())
    }
}

public struct PlannedMeal: Codable, Equatable, Sendable {
    public var date: Date
    public var slot: MealSlot
    public var mealID: UUID

    public init(date: Date, slot: MealSlot, mealID: UUID) {
        self.date = date
        self.slot = slot
        self.mealID = mealID
    }
}

public struct WeeklyPlan: Codable, Equatable, Sendable {
    public var weekStart: Date
    public var meals: [PlannedMeal]

    public init(weekStart: Date, meals: [PlannedMeal] = []) {
        self.weekStart = weekStart
        self.meals = meals
    }
}

public struct AppBackup: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let meals: [Meal]
    public let ingredients: [CatalogIngredient]
    public let plan: WeeklyPlan?
    public let dailyCalorieGoal: Int

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
