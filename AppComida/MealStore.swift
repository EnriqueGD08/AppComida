import Foundation

public protocol MealStore: Sendable {
    func loadMeals() throws -> [Meal]
    func saveMeals(_ meals: [Meal]) throws
    func loadIngredients() throws -> [CatalogIngredient]
    func saveIngredients(_ ingredients: [CatalogIngredient]) throws
    func loadPlan() throws -> WeeklyPlan?
    func savePlan(_ plan: WeeklyPlan) throws
    func deletePlan() throws
    func loadDailyCalorieGoal() throws -> Int
    func saveDailyCalorieGoal(_ goal: Int) throws
}

public final class FileMealStore: MealStore, @unchecked Sendable {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MealPlanner", isDirectory: true)
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public func loadMeals() throws -> [Meal] {
        try read([Meal].self, from: "meals.json") ?? SampleMeals.all
    }

    public func saveMeals(_ meals: [Meal]) throws {
        try write(meals, to: "meals.json")
    }

    public func loadIngredients() throws -> [CatalogIngredient] {
        try read([CatalogIngredient].self, from: "ingredients.json") ?? []
    }

    public func saveIngredients(_ ingredients: [CatalogIngredient]) throws {
        try write(ingredients, to: "ingredients.json")
    }

    public func loadPlan() throws -> WeeklyPlan? {
        try read(WeeklyPlan.self, from: "plan.json")
    }

    public func savePlan(_ plan: WeeklyPlan) throws {
        try write(plan, to: "plan.json")
    }

    public func deletePlan() throws {
        let url = directory.appendingPathComponent("plan.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func loadDailyCalorieGoal() throws -> Int {
        try read(Int.self, from: "calorie-goal.json") ?? 2_000
    }

    public func saveDailyCalorieGoal(_ goal: Int) throws {
        try write(goal, to: "calorie-goal.json")
    }

    private func read<T: Decodable>(_ type: T.Type, from filename: String) throws -> T? {
        let url = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    private func write<T: Encodable>(_ value: T, to filename: String) throws {
        let data = try encoder.encode(value)
        try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
    }
}

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
