//
//  MealPlannerApp.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-05
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Punto de entrada de la app (`@main`) y vista raíz con las pestañas. Solo compone las pantallas e inyecta el modelo y el navegador; la lógica vive en `AppViewModel` y cada pantalla en su archivo.
//

import SwiftUI

/// Aplicación principal: crea el modelo y el navegador, y aplica el tema (claro, oscuro o del sistema) elegido en ajustes.
@main
struct MealPlannerApp: App {
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @State private var viewModel = AppViewModel.live()
    @State private var navigator = Navigator()

    var body: some Scene {
        WindowGroup {
            RootView(appearance: $appearance)
                .environment(viewModel)
                .environment(navigator)
                .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
        }
    }
}

/// Vista raíz: barra de pestañas, hojas de edición y diálogos globales (alertas y confirmación de borrado).
struct RootView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(Navigator.self) private var navigator
    @Binding var appearance: String

    var body: some View {
        @Bindable var navigator = navigator

        TabView(selection: $navigator.selectedTab) {
            MealsTabView()
                .tabItem { Label("Comidas", systemImage: "fork.knife") }
                .tag(AppTab.meals)

            PlanTabView()
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(AppTab.plan)

            ShoppingTabView()
                .tabItem { Label("Compra", systemImage: "cart") }
                .tag(AppTab.shopping)

            IngredientsTabView()
                .tabItem { Label("Ingredientes", systemImage: "carrot") }
                .tag(AppTab.ingredients)

            NavigationStack {
                SettingsView(appearance: $appearance)
            }
            .tabItem { Label("Ajustes", systemImage: "gearshape") }
            .badge(viewModel.isBackupStale ? "!" : nil)
            .tag(AppTab.settings)
        }
        .tint(Theme.accent)
        .sheet(item: $navigator.mealEditor) { mode in
            MealEditorView(meal: mode.meal)
        }
        .sheet(item: $navigator.catalogEditor) { mode in
            CatalogIngredientEditorView(ingredient: mode.ingredient) { try viewModel.saveCatalogIngredient($0) }
        }
        .sheet(item: $navigator.plannedMealEditor) { reference in
            PlannedMealEditorView(plannedID: reference.id)
        }
        .confirmationDialog(
            "¿Eliminar \(navigator.mealToDelete?.name ?? "esta comida")?",
            isPresented: Binding(
                get: { navigator.mealToDelete != nil },
                set: { if !$0 { navigator.mealToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                if let meal = navigator.mealToDelete { viewModel.deleteMeal(meal) }
                navigator.mealToDelete = nil
            }
            Button("Cancelar", role: .cancel) { navigator.mealToDelete = nil }
        } message: {
            Text("También se eliminará del menú semanal guardado.")
        }
        .alert("Planificador", isPresented: Binding(
            get: { viewModel.message != nil },
            set: { if !$0 { viewModel.message = nil } }
        )) {
            Button("Aceptar") { viewModel.message = nil }
        } message: {
            Text(viewModel.message ?? "")
        }
    }
}
