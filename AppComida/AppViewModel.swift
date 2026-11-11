//
//  AppViewModel.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Modelo de vista principal. Guarda el estado de la app y expone los casos de uso (comidas, ingredientes, plan, lista de la compra, copias de seguridad y recordatorios). Depende de protocolos inyectados, no de implementaciones concretas.
//

import Foundation
import Observation

extension GenerationError {
    /// Mensaje en español para mostrar al usuario.
    var userMessage: String {
        switch self {
        case .invalidGoal: "el objetivo de calorías no es válido."
        case .invalidDate: "la fecha de inicio no es válida."
        case .notEnoughMeals: "necesitas comidas para las cuatro franjas."
        case .goalUnavailable(let day, let calories): "el día \(day) suma \(calories) kcal y queda fuera de la tolerancia."
        }
    }
}

/// Estado y casos de uso de la aplicación.
///
/// Las vistas solo leen su estado y llaman a sus métodos; la persistencia, el generador de menús y los
/// recordatorios se reciben por protocolo (inversión de dependencias), lo que facilita sustituirlos.
@MainActor @Observable
final class AppViewModel {
    // MARK: Estado

    private(set) var meals: [Meal]
    private(set) var catalog: [CatalogIngredient]
    private(set) var goal: Int
    private(set) var plan: WeeklyPlan?
    private(set) var extras: ShoppingExtras
    private(set) var lastBackupDate: Date?
    private(set) var remindersEnabled: Bool
    /// Texto de la alerta que se muestra al usuario; la vista lo pone a `nil` al cerrarla.
    var message: String?

    // MARK: Dependencias

    private let store: any MealStore
    private let generator: any MenuGenerating
    private let reminders: any ReminderScheduling
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date

    private enum DefaultsKey {
        static let lastBackup = "lastBackupDate"
        static let reminders = "weeklyReminderEnabled"
    }

    /// Días sin copia de seguridad a partir de los cuales se avisa al usuario.
    private let staleBackupDays = 14

    // MARK: Inicio

    /// Crea el modelo cargando los datos guardados; si algún archivo no se puede leer usa valores por defecto y avisa.
    /// - Parameters:
    ///   - store: Almacén de datos.
    ///   - generator: Generador de menús.
    ///   - reminders: Programador del recordatorio semanal.
    ///   - defaults: Preferencias simples (fecha de la última copia, recordatorio).
    ///   - calendar: Calendario usado para las fechas.
    ///   - now: Reloj, inyectable para pruebas.
    init(
        store: any MealStore,
        generator: any MenuGenerating,
        reminders: any ReminderScheduling,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now }
    ) {
        self.store = store
        self.generator = generator
        self.reminders = reminders
        self.defaults = defaults
        self.calendar = calendar
        self.now = now

        var loadFailed = false
        /// Carga un dato y, si falla, devuelve el valor por defecto y recuerda el fallo.
        func load<T>(_ fallback: T, _ body: () throws -> T) -> T {
            do { return try body() } catch { loadFailed = true; return fallback }
        }
        meals = load(SampleMeals.all) { try store.loadMeals() }
        catalog = load([]) { try store.loadIngredients() }
        goal = load(2_000) { try store.loadDailyCalorieGoal() }
        plan = load(nil) { try store.loadPlan() }
        extras = load(ShoppingExtras()) { try store.loadShoppingExtras() }
        lastBackupDate = defaults.object(forKey: DefaultsKey.lastBackup) as? Date
        remindersEnabled = defaults.bool(forKey: DefaultsKey.reminders)
        if loadFailed {
            message = "Algún dato no se pudo leer. El archivo dañado se ha guardado aparte (extensión .corrupt) y se han usado valores por defecto."
        }
    }

    // MARK: Utilidades internas

    /// Ejecuta una acción que puede fallar y, si falla, muestra el motivo.
    /// - Parameters:
    ///   - failure: Texto que describe qué no se pudo hacer.
    ///   - action: Acción a ejecutar.
    /// - Returns: `true` si la acción terminó sin error.
    @discardableResult
    private func attempt(_ failure: String, _ action: () throws -> Void) -> Bool {
        do {
            try action()
            return true
        } catch {
            message = "\(failure): \(error.localizedDescription)"
            return false
        }
    }

    // MARK: Consultas

    /// Busca una comida por identificador.
    /// - Parameter id: Identificador de la comida.
    /// - Returns: La comida, o `nil` si ya no existe.
    func meal(withID id: UUID) -> Meal? {
        meals.first { $0.id == id }
    }

    /// Busca un ingrediente del catálogo por identificador.
    /// - Parameter id: Identificador del ingrediente.
    /// - Returns: El ingrediente, o `nil` si no existe.
    func catalogIngredient(withID id: UUID) -> CatalogIngredient? {
        catalog.first { $0.id == id }
    }

    /// Busca una comida planificada por su identificador de franja.
    /// - Parameter id: `PlannedMeal.id`.
    /// - Returns: La comida planificada, o `nil` si no está en el plan.
    func plannedMeal(withID id: String) -> PlannedMeal? {
        plan?.meals.first { $0.id == id }
    }

    /// Calorías que aporta una comida planificada, teniendo en cuenta las raciones y las opciones elegidas.
    /// - Parameter planned: Comida planificada.
    /// - Returns: Las calorías, redondeadas.
    func calories(of planned: PlannedMeal) -> Int {
        meal(withID: planned.mealID)?.calories(for: planned) ?? 0
    }

    /// Calorías totales de un día del plan.
    /// - Parameter day: Día del plan.
    /// - Returns: La suma de las calorías de sus comidas.
    func calories(on day: PlanDay) -> Int {
        day.meals.reduce(0) { $0 + calories(of: $1) }
    }

    /// Macronutrientes totales de un día del plan.
    /// - Parameter day: Día del plan.
    /// - Returns: La suma de los macronutrientes de sus comidas, según las raciones.
    func nutrition(on day: PlanDay) -> Nutrition {
        day.meals.reduce(Nutrition()) { total, planned in
            guard let meal = meal(withID: planned.mealID) else { return total }
            return total + meal.nutrition(for: planned)
        }
    }

    /// Número de comidas que usan un ingrediente del catálogo, ya sea como ingrediente fijo o como opción de un ingrediente variable.
    /// - Parameter ingredient: Ingrediente del catálogo.
    /// - Returns: Cuántas comidas lo contienen.
    func usageCount(of ingredient: CatalogIngredient) -> Int {
        meals.filter { meal in
            meal.ingredients.contains { $0.catalogID == ingredient.id }
                || meal.optionGroups.contains { group in group.options.contains { $0.ingredient.catalogID == ingredient.id } }
        }.count
    }

    // MARK: Objetivo

    /// Cambia el objetivo calórico diario (entre 500 y 5000 kcal) y lo guarda.
    /// - Parameter newGoal: Nuevo objetivo.
    func setGoal(_ newGoal: Int) {
        let clamped = min(max(newGoal, 500), 5_000)
        guard clamped != goal else { return }
        if attempt("No se pudo guardar el objetivo", { try store.saveDailyCalorieGoal(clamped) }) {
            goal = clamped
        }
    }

    // MARK: Comidas

    /// Añade una comida nueva o actualiza una existente y la guarda en disco.
    /// - Parameter meal: Comida a guardar.
    /// - Throws: Un error si no se puede guardar.
    func saveMeal(_ meal: Meal) throws {
        var updated = meals
        if let index = updated.firstIndex(where: { $0.id == meal.id }) {
            updated[index] = meal
        } else {
            updated.append(meal)
        }
        try store.saveMeals(updated)
        meals = updated
    }

    /// Elimina una comida y sus apariciones en el plan semanal. Si no se puede guardar, deja todo como estaba.
    /// - Parameter meal: Comida a eliminar.
    func deleteMeal(_ meal: Meal) {
        let updatedMeals = meals.filter { $0.id != meal.id }
        let updatedPlan = plan.map { WeeklyPlan(weekStart: $0.weekStart, meals: $0.meals.filter { $0.mealID != meal.id }) }
        let saved = attempt("No se pudo eliminar la comida") {
            try store.saveMeals(updatedMeals)
            if let updatedPlan { try store.savePlan(updatedPlan) }
        }
        if saved {
            meals = updatedMeals
            plan = updatedPlan
        }
    }

    /// Crea una copia de una comida con nombre "… (copia)".
    /// - Parameter id: Identificador de la comida a duplicar.
    func duplicateMeal(_ id: UUID) {
        guard var copy = meal(withID: id) else { return }
        copy.id = UUID()
        copy.name += " (copia)"
        copy.isFavorite = false
        copy.ingredients = copy.ingredients.map { ingredient in
            var duplicate = ingredient
            duplicate.id = UUID()
            return duplicate
        }
        attempt("No se pudo duplicar la comida") { try saveMeal(copy) }
    }

    /// Marca o desmarca una comida como favorita.
    /// - Parameter id: Identificador de la comida.
    func toggleFavorite(_ id: UUID) {
        guard var meal = meal(withID: id) else { return }
        meal.isFavorite.toggle()
        attempt("No se pudo actualizar la comida") { try saveMeal(meal) }
    }

    // MARK: Catálogo de ingredientes

    /// Añade un ingrediente al catálogo o actualiza uno existente, y recalcula las comidas que lo usan.
    /// - Parameter ingredient: Ingrediente a guardar.
    /// - Throws: Un error si no se puede guardar.
    func saveCatalogIngredient(_ ingredient: CatalogIngredient) throws {
        var updatedCatalog = catalog
        if let index = updatedCatalog.firstIndex(where: { $0.id == ingredient.id }) {
            updatedCatalog[index] = ingredient
        } else {
            updatedCatalog.append(ingredient)
        }
        let recalculated = meals.map { RecipeCalculator.recalculated($0, catalog: updatedCatalog) }
        try store.saveIngredients(updatedCatalog)
        if recalculated != meals {
            try store.saveMeals(recalculated)
            meals = recalculated
        }
        catalog = updatedCatalog
    }

    /// Elimina un ingrediente del catálogo, salvo que alguna comida lo use.
    /// - Parameter ingredient: Ingrediente a eliminar.
    func deleteCatalogIngredient(_ ingredient: CatalogIngredient) {
        let uses = usageCount(of: ingredient)
        guard uses == 0 else {
            message = "\"\(ingredient.name)\" se usa en \(uses) \(uses == 1 ? "comida" : "comidas"). Quítalo de ellas antes de eliminarlo."
            return
        }
        let updated = catalog.filter { $0.id != ingredient.id }
        if attempt("No se pudo eliminar el ingrediente", { try store.saveIngredients(updated) }) {
            catalog = updated
        }
    }

    // MARK: Plan semanal

    /// Genera y guarda el menú de la semana actual con el objetivo diario, conservando las comidas bloqueadas si el plan es de esta semana.
    /// - Returns: `true` si se generó y guardó el menú.
    @discardableResult
    func generatePlan() -> Bool {
        let today = now()
        let start = WeeklyPlan.startOfWeek(containing: today, calendar: calendar)
        let locked = plan.flatMap { $0.isCurrent(on: today, calendar: calendar) ? $0.meals.filter(\.isLocked) : nil } ?? []

        switch generator.generate(weekStarting: start, meals: meals, dailyGoal: goal, locked: locked) {
        case .success(let generated):
            guard attempt("No se pudo guardar el menú", { try store.savePlan(generated) }) else { return false }
            plan = generated
            pruneCheckedKeys()
            let approximate = generated.days(calendar: calendar).contains {
                abs(calories(on: $0) - goal) > MenuGenerator.defaultTolerance
            }
            message = approximate
                ? "Menú generado. No había una combinación dentro del límite; se han elegido las opciones más cercanas."
                : "Menú generado correctamente, ajustando las comidas al objetivo."
            return true
        case .failure(let error):
            message = "No se pudo generar el menú: \(error.userMessage)"
            return false
        }
    }

    /// Cambia la comida de una franja del plan. Las raciones pasan a ser las "raciones por toma" de la comida nueva y,
    /// si tiene ingredientes variables, se elige la primera opción de cada grupo (se puede cambiar después).
    /// - Parameters:
    ///   - plannedID: Identificador de la franja (`PlannedMeal.id`).
    ///   - mealID: Comida nueva.
    func replaceMeal(planned plannedID: String, with mealID: UUID) {
        let newMeal = meal(withID: mealID)
        updatePlanned(plannedID) { planned in
            planned.mealID = mealID
            planned.servings = newMeal?.plannedServings ?? planned.servings
            planned.choices = (newMeal?.optionGroups ?? []).compactMap { group in
                group.options.first.map { OptionChoice(groupID: group.id, optionID: $0.id) }
            }
        }
    }

    /// Cambia la opción elegida de un ingrediente variable en una franja del plan.
    /// - Parameters:
    ///   - plannedID: Identificador de la franja.
    ///   - groupID: Grupo de opciones.
    ///   - optionID: Opción elegida.
    func setChoice(planned plannedID: String, group groupID: UUID, option optionID: UUID) {
        updatePlanned(plannedID) { planned in
            planned.choices.removeAll { $0.groupID == groupID }
            planned.choices.append(OptionChoice(groupID: groupID, optionID: optionID))
        }
    }

    /// Cambia el número de raciones de una franja del plan.
    /// - Parameters:
    ///   - servings: Raciones (se limita a 0,5–6).
    ///   - plannedID: Identificador de la franja.
    func setServings(_ servings: Double, forPlanned plannedID: String) {
        updatePlanned(plannedID) { $0.servings = min(max(servings, 0.5), 6) }
    }

    /// Bloquea o desbloquea una franja para que se conserve al regenerar el menú.
    /// - Parameter plannedID: Identificador de la franja.
    func toggleLock(planned plannedID: String) {
        updatePlanned(plannedID) { $0.isLocked.toggle() }
    }

    /// Aplica un cambio a una franja del plan y lo guarda.
    /// - Parameters:
    ///   - plannedID: Identificador de la franja.
    ///   - transform: Cambio a aplicar.
    private func updatePlanned(_ plannedID: String, _ transform: (inout PlannedMeal) -> Void) {
        guard var updated = plan, updated.update(plannedID, transform) else { return }
        if attempt("No se pudo guardar el menú", { try store.savePlan(updated) }) {
            plan = updated
        }
    }

    // MARK: Lista de la compra

    /// Identificador de la semana del plan, usado para recordar qué productos se marcaron.
    var weekKey: String {
        plan.map { String(Int($0.weekStart.timeIntervalSince1970)) } ?? "none"
    }

    /// Todos los productos que necesita el plan, estén o no en casa.
    var allShoppingItems: [ShoppingItem] {
        plan.map { ShoppingListBuilder.build(plan: $0, meals: meals, catalog: catalog) } ?? []
    }

    /// Productos que hay que comprar (los que no están marcados como "ya en casa").
    var shoppingItems: [ShoppingItem] {
        let pantry = Set(extras.pantryKeys)
        return allShoppingItems.filter { !pantry.contains($0.id) }
    }

    /// Productos que el plan necesita pero el usuario ya tiene en casa.
    var pantryItems: [ShoppingItem] {
        let pantry = Set(extras.pantryKeys)
        return allShoppingItems.filter { pantry.contains($0.id) }
    }

    /// Indica si un producto del plan está marcado como comprado.
    /// - Parameter item: Producto.
    /// - Returns: `true` si está marcado.
    func isChecked(_ item: ShoppingItem) -> Bool {
        extras.checkedKeys.contains("\(weekKey)|\(item.id)")
    }

    /// Indica si un producto manual está marcado como comprado.
    /// - Parameter item: Producto manual.
    /// - Returns: `true` si está marcado.
    func isChecked(_ item: ManualShoppingItem) -> Bool {
        extras.checkedKeys.contains("manual|\(item.id.uuidString)")
    }

    /// Marca o desmarca un producto del plan como comprado.
    /// - Parameter item: Producto.
    func toggleChecked(_ item: ShoppingItem) {
        toggleCheckedKey("\(weekKey)|\(item.id)")
    }

    /// Marca o desmarca un producto manual como comprado.
    /// - Parameter item: Producto manual.
    func toggleChecked(_ item: ManualShoppingItem) {
        toggleCheckedKey("manual|\(item.id.uuidString)")
    }

    /// Añade o quita una clave de la lista de marcados.
    /// - Parameter key: Clave a alternar.
    private func toggleCheckedKey(_ key: String) {
        updateExtras { extras in
            if let index = extras.checkedKeys.firstIndex(of: key) {
                extras.checkedKeys.remove(at: index)
            } else {
                extras.checkedKeys.append(key)
            }
        }
    }

    /// Marca un producto como "ya lo tengo en casa", de modo que sale de la lista de compra.
    /// - Parameter item: Producto.
    func addToPantry(_ item: ShoppingItem) {
        updateExtras { extras in
            if !extras.pantryKeys.contains(item.id) { extras.pantryKeys.append(item.id) }
        }
    }

    /// Devuelve un producto a la lista de compra.
    /// - Parameter item: Producto.
    func removeFromPantry(_ item: ShoppingItem) {
        updateExtras { $0.pantryKeys.removeAll { $0 == item.id } }
    }

    /// Añade un producto a mano a la lista de la compra.
    /// - Parameters:
    ///   - name: Nombre del producto (se ignora si está vacío).
    ///   - quantity: Cantidad en texto libre.
    func addManualItem(name: String, quantity: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = ManualShoppingItem(name: trimmed, quantity: quantity.trimmingCharacters(in: .whitespacesAndNewlines))
        updateExtras { $0.manualItems.append(item) }
    }

    /// Elimina un producto manual de la lista.
    /// - Parameter item: Producto manual.
    func removeManualItem(_ item: ManualShoppingItem) {
        updateExtras { extras in
            extras.manualItems.removeAll { $0.id == item.id }
            extras.checkedKeys.removeAll { $0 == "manual|\(item.id.uuidString)" }
        }
    }

    /// Desmarca todos los productos de la lista (del plan y manuales).
    func resetChecks() {
        updateExtras { $0.checkedKeys = [] }
    }

    /// Descarta las marcas de semanas anteriores al generar un menú nuevo.
    private func pruneCheckedKeys() {
        let prefix = "\(weekKey)|"
        updateExtras { extras in
            extras.checkedKeys = extras.checkedKeys.filter { $0.hasPrefix(prefix) || $0.hasPrefix("manual|") }
        }
    }

    /// Aplica un cambio a los datos extra de la compra y lo guarda.
    /// - Parameter change: Cambio a aplicar.
    private func updateExtras(_ change: (inout ShoppingExtras) -> Void) {
        var updated = extras
        change(&updated)
        guard updated != extras else { return }
        if attempt("No se pudo guardar la lista de la compra", { try store.saveShoppingExtras(updated) }) {
            extras = updated
        }
    }

    // MARK: Copias de seguridad

    /// Indica si conviene avisar al usuario de que haga una copia: nunca la hizo teniendo datos propios, o hace más de 14 días.
    var isBackupStale: Bool {
        guard let last = lastBackupDate else { return !catalog.isEmpty }
        let days = calendar.dateComponents([.day], from: last, to: now()).day ?? 0
        return days >= staleBackupDays
    }

    /// Crea una copia de seguridad con los datos actuales.
    /// - Returns: La copia lista para exportar.
    func makeBackup() -> AppBackup {
        AppBackup(meals: meals, ingredients: catalog, plan: plan, dailyCalorieGoal: goal, extras: extras)
    }

    /// Anota que se acaba de exportar una copia de seguridad.
    func markBackupExported() {
        let date = now()
        lastBackupDate = date
        defaults.set(date, forKey: DefaultsKey.lastBackup)
    }

    /// Importa una copia de seguridad.
    ///
    /// Si algo falla al escribir en disco, se restauran los datos que había antes.
    /// - Parameters:
    ///   - data: Contenido JSON del archivo.
    ///   - mode: Si se reemplazan los datos actuales o se combinan con ellos.
    func importBackup(from data: Data, mode: BackupImportMode) {
        let previous = makeBackup()
        do {
            let incoming = try JSONDecoder().decode(AppBackup.self, from: data)
            try BackupService.validate(incoming)
            let result: AppBackup = switch mode {
            case .replace: incoming
            case .merge: BackupService.merge(current: previous, incoming: incoming)
            }
            do {
                try write(result)
            } catch {
                try? write(previous)
                throw error
            }
            apply(result)
            message = mode == .merge
                ? "Copia combinada con tus datos correctamente."
                : "Copia de seguridad importada correctamente."
        } catch {
            message = "No se pudo importar la copia de seguridad: \(error.localizedDescription)"
        }
    }

    /// Escribe una copia de seguridad completa en el almacén.
    /// - Parameter backup: Datos a escribir.
    /// - Throws: Un error si falla alguna escritura.
    private func write(_ backup: AppBackup) throws {
        try store.saveMeals(backup.meals)
        try store.saveIngredients(backup.ingredients)
        try store.saveDailyCalorieGoal(backup.dailyCalorieGoal)
        try store.saveShoppingExtras(backup.extras ?? ShoppingExtras())
        if let plan = backup.plan {
            try store.savePlan(plan)
        } else {
            try store.deletePlan()
        }
    }

    /// Actualiza el estado en memoria con los datos de una copia.
    /// - Parameter backup: Datos a aplicar.
    private func apply(_ backup: AppBackup) {
        meals = backup.meals
        catalog = backup.ingredients
        goal = backup.dailyCalorieGoal
        plan = backup.plan
        extras = backup.extras ?? ShoppingExtras()
    }

    // MARK: Recordatorios

    /// Activa o desactiva el recordatorio semanal para planificar el menú.
    /// - Parameter enabled: `true` para activarlo.
    func setRemindersEnabled(_ enabled: Bool) async {
        let applied = await reminders.setWeeklyMenuReminder(enabled: enabled)
        if enabled && !applied {
            message = "No se pudo activar el recordatorio. Permite las notificaciones de la app en Ajustes del iPhone."
        }
        remindersEnabled = enabled && applied
        defaults.set(remindersEnabled, forKey: DefaultsKey.reminders)
    }
}
