import SwiftUI

// MARK: - Comidas

struct MealsTabView: View {
    @Binding var goal: Int
    let meals: [Meal]
    let onGenerate: () -> Void
    let onNew: () -> Void
    let onEdit: (Meal) -> Void
    let onDelete: (Meal) -> Void

    @State private var query = ""

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !trimmedQuery.isEmpty }
    private var filteredMeals: [Meal] {
        meals.filter { $0.name.localizedStandardContains(trimmedQuery) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 28) {
                    if isSearching {
                        if filteredMeals.isEmpty {
                            ContentUnavailableView.search(text: trimmedQuery)
                        }
                    } else {
                        goalCard
                    }
                    ForEach(MealSlot.allCases) { slot in
                        slotSection(slot)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(AppBackground())
            .navigationTitle("Mis comidas")
            .searchable(text: $query, prompt: "Buscar comida")
            .toolbar {
                Button(action: onNew) {
                    Label("Nueva comida", systemImage: "plus")
                }
            }
        }
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Objetivo diario", systemImage: "flame.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(goal)")
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("kcal").font(.title3.weight(.medium)).opacity(0.85)
                    }
                    .foregroundStyle(.white)
                }
                Spacer()
                HStack(spacing: 10) {
                    stepButton("minus") { goal = max(500, goal - 50) }
                    stepButton("plus") { goal = min(5_000, goal + 50) }
                }
            }
            Button(action: onGenerate) {
                Label("Generar menú semanal", systemImage: "wand.and.stars")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Theme.accent.opacity(0.35), radius: 16, y: 8)
        .animation(.snappy, value: goal)
    }

    private func stepButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.22), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func slotSection(_ slot: MealSlot) -> some View {
        let slotMeals = (isSearching ? filteredMeals : meals).filter { $0.mealSlots.contains(slot) }
        if isSearching && slotMeals.isEmpty { return AnyView(EmptyView()) }
        return AnyView(VStack(spacing: 12) {
            SectionTitle(title: slot.title, systemImage: slot.icon, color: slot.color, trailing: "\(slotMeals.count)")
            if slotMeals.isEmpty {
                Text("Aún no hay comidas para esta franja.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .card()
            }
            ForEach(slotMeals) { meal in
                NavigationLink {
                    MealDetailView(meal: meal) { onEdit(meal) }
                } label: {
                    MealRow(meal: meal, slot: slot)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { onEdit(meal) } label: { Label("Editar", systemImage: "pencil") }
                    Button(role: .destructive) { onDelete(meal) } label: { Label("Eliminar", systemImage: "trash") }
                }
            }
        })
    }
}

private struct MealRow: View {
    let meal: Meal
    let slot: MealSlot

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(systemName: slot.icon, color: slot.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(meal.name).font(.headline).multilineTextAlignment(.leading)
                Text("\(meal.ingredients.count) ingredientes · \(meal.servings) \(meal.servings == 1 ? "ración" : "raciones")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(meal.caloriesPerServing)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text("kcal").font(.caption2).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card(padding: 14)
    }
}

// MARK: - Detalle

struct MealDetailView: View {
    let meal: Meal
    let onEdit: () -> Void

    private var slot: MealSlot { meal.suggestedSlot }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hero
                macros
                ingredients
                if !meal.steps.isEmpty { steps }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle(meal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Editar", action: onEdit)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(meal.mealSlots) { slot in
                    Label(slot.title, systemImage: slot.icon)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.22), in: Capsule())
                }
            }
            Text(meal.name)
                .font(.title.weight(.bold))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(meal.caloriesPerServing)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("kcal por ración").font(.subheadline).opacity(0.9)
            }
            Text("Receta completa: \(meal.calories) kcal · \(meal.servings) \(meal.servings == 1 ? "ración" : "raciones")")
                .font(.footnote)
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [slot.color, slot.color.opacity(0.65)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .shadow(color: slot.color.opacity(0.35), radius: 14, y: 8)
    }

    private var macros: some View {
        HStack(spacing: 12) {
            macro("Proteínas", meal.nutrition.protein, .red)
            macro("Carbohidratos", meal.nutrition.carbohydrates, .orange)
            macro("Grasas", meal.nutrition.fat, .blue)
        }
    }

    private func macro(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value.formatted()) g")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Ingredientes", systemImage: "carrot.fill", color: .orange)
            VStack(spacing: 0) {
                ForEach(Array(meal.ingredients.enumerated()), id: \.element.id) { index, ingredient in
                    HStack {
                        Text(ingredient.name)
                        Spacer()
                        Text(ingredient.quantity).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    if index < meal.ingredients.count - 1 { Divider() }
                }
            }
            .card(padding: 16)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Preparación", systemImage: "list.number", color: .indigo)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(meal.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Theme.accent, in: Circle())
                        Text(step)
                    }
                }
            }
            .card(padding: 16)
        }
    }
}

// MARK: - Plan

struct PlanTabView: View {
    let plan: WeeklyPlan?
    let meals: [Meal]
    let goal: Int
    let onEdit: (Meal) -> Void
    let onShowShopping: () -> Void

    private var days: [(date: Date, meals: [PlannedMeal])] {
        guard let plan else { return [] }
        let calendar = Calendar.current
        return Dictionary(grouping: plan.meals) { calendar.startOfDay(for: $0.date) }
            .map { (date: $0.key, meals: $0.value) }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if plan == nil {
                    EmptyCard(
                        systemImage: "calendar.badge.plus",
                        title: "Sin menú",
                        message: "Genera un menú semanal desde la pestaña Comidas."
                    )
                } else {
                    LazyVStack(spacing: 16) {
                        Button(action: onShowShopping) {
                            HStack(spacing: 14) {
                                IconBadge(systemName: "cart.fill", color: Theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Lista de la compra").font(.headline)
                                    Text("Ingredientes de toda la semana")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .card(padding: 14)
                        }
                        .buttonStyle(.plain)

                        ForEach(days, id: \.date) { day in
                            dayCard(day.date, day.meals)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(AppBackground())
            .navigationTitle("Plan semanal")
        }
    }

    private func dayCard(_ date: Date, _ planned: [PlannedMeal]) -> some View {
        let resolved = planned.compactMap { item in
            meals.first { $0.id == item.mealID }.map { (item, $0) }
        }
        let total = resolved.reduce(0) { $0 + $1.1.caloriesPerServing }
        let onTarget = abs(total - goal) <= 150

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(date.formatted(.dateTime.weekday(.wide)).capitalized)
                        .font(.title3.weight(.bold))
                    Text(date.formatted(.dateTime.day().month(.wide)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(total) kcal")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(onTarget ? Theme.accent : .orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((onTarget ? Theme.accent : Color.orange).opacity(0.15), in: Capsule())
            }
            VStack(spacing: 0) {
                ForEach(Array(resolved.enumerated()), id: \.offset) { index, pair in
                    let (item, meal) = pair
                    NavigationLink {
                        MealDetailView(meal: meal) { onEdit(meal) }
                    } label: {
                        HStack(spacing: 12) {
                            IconBadge(systemName: item.slot.icon, color: item.slot.color, size: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.slot.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(meal.name)
                                    .font(.subheadline.weight(.semibold))
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 8)
                            Text("\(meal.caloriesPerServing) kcal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < resolved.count - 1 { Divider().padding(.leading, 48) }
                }
            }
        }
        .card()
    }
}

// MARK: - Ingredientes

struct IngredientsTabView: View {
    let ingredients: [CatalogIngredient]
    let onNew: () -> Void
    let onEdit: (CatalogIngredient) -> Void
    let onDelete: (CatalogIngredient) -> Void

    @State private var query = ""

    private var filtered: [CatalogIngredient] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? ingredients : ingredients.filter { $0.name.localizedStandardContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { ingredient in
                    HStack(spacing: 14) {
                        IconBadge(systemName: "carrot.fill", color: .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ingredient.name).font(.headline)
                            Text("\(ingredient.calories.formatted()) kcal \(ingredient.calorieUnit.title.lowercased())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .card(padding: 14)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .swipeActions {
                        Button { onEdit(ingredient) } label: { Label("Editar", systemImage: "pencil") }
                            .tint(Theme.accent)
                        Button(role: .destructive) { onDelete(ingredient) } label: { Label("Eliminar", systemImage: "trash") }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .overlay {
                if !ingredients.isEmpty && filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else if ingredients.isEmpty {
                    EmptyCard(
                        systemImage: "carrot",
                        title: "Sin ingredientes",
                        message: "Añade ingredientes para reutilizarlos al crear comidas."
                    )
                }
            }
            .navigationTitle("Ingredientes")
            .searchable(text: $query, prompt: "Buscar ingrediente")
            .toolbar {
                Button(action: onNew) {
                    Label("Nuevo ingrediente", systemImage: "plus")
                }
            }
        }
    }
}

// MARK: - Lista de la compra

struct ShoppingTabView: View {
    let items: [ShoppingItem]
    let weekKey: String

    @AppStorage("shoppingChecked") private var checkedRaw = ""

    private var checked: Set<String> {
        Set(checkedRaw.split(separator: "\n").map(String.init))
    }

    private func storageKey(_ item: ShoppingItem) -> String { "\(weekKey)|\(item.id)" }
    private func isChecked(_ item: ShoppingItem) -> Bool { checked.contains(storageKey(item)) }

    private func toggle(_ item: ShoppingItem) {
        var current = checked
        let key = storageKey(item)
        if current.contains(key) { current.remove(key) } else { current.insert(key) }
        checkedRaw = current.sorted().joined(separator: "\n")
    }

    private func resetChecks() {
        let prefix = "\(weekKey)|"
        checkedRaw = checked.filter { !$0.hasPrefix(prefix) }.sorted().joined(separator: "\n")
    }

    private var doneCount: Int { items.filter(isChecked).count }
    private var sortedItems: [ShoppingItem] {
        items.filter { !isChecked($0) } + items.filter(isChecked)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if items.isEmpty {
                    EmptyCard(
                        systemImage: "cart",
                        title: "Lista vacía",
                        message: "Genera un menú semanal y aquí aparecerán los ingredientes que necesitas comprar."
                    )
                } else {
                    LazyVStack(spacing: 10) {
                        summary
                        ForEach(sortedItems) { item in
                            row(item)
                        }
                        Text("Cantidades para una ración de cada comida del plan.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .animation(.snappy, value: checkedRaw)
                }
            }
            .background(AppBackground())
            .navigationTitle("Compra")
            .toolbar {
                if !items.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            ShareLink(item: ShoppingListBuilder.plainText(for: items)) {
                                Label("Compartir lista", systemImage: "square.and.arrow.up")
                            }
                            Button(action: resetChecks) {
                                Label("Desmarcar todo", systemImage: "arrow.uturn.backward")
                            }
                        } label: {
                            Label("Más", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(doneCount) de \(items.count)")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text("productos comprados").foregroundStyle(.secondary)
                Spacer()
                if doneCount == items.count {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.accent)
                }
            }
            ProgressView(value: Double(doneCount), total: Double(max(items.count, 1)))
                .tint(Theme.accent)
        }
        .card()
        .padding(.bottom, 6)
    }

    private func row(_ item: ShoppingItem) -> some View {
        let done = isChecked(item)
        return Button {
            toggle(item)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? Theme.accent : Color.secondary.opacity(0.5))
                Text(item.name)
                    .font(.headline)
                    .strikethrough(done)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Text(item.quantityText)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.trailing)
            }
            .opacity(done ? 0.5 : 1)
            .card(padding: 14)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: done)
    }
}

// MARK: - Selector de ingredientes con búsqueda

struct IngredientPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let ingredients: [CatalogIngredient]
    let selectedID: UUID?
    let onSelect: (CatalogIngredient) -> Void

    @State private var query = ""

    private var filtered: [CatalogIngredient] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = q.isEmpty ? ingredients : ingredients.filter { $0.name.localizedStandardContains(q) }
        return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List(filtered) { ingredient in
            Button {
                onSelect(ingredient)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ingredient.name).foregroundStyle(.primary)
                        Text("\(ingredient.calories.formatted()) kcal \(ingredient.calorieUnit.title.lowercased())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if ingredient.id == selectedID {
                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .overlay {
            if filtered.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar ingrediente")
        .navigationTitle("Ingrediente")
        .navigationBarTitleDisplayMode(.inline)
    }
}
