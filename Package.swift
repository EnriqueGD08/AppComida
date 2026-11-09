// swift-tools-version: 6.0
//
//  Package.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Descripción: Paquete auxiliar que compila la lógica de la app independiente de la interfaz (modelos, almacén,
//  generador de menús, lista de la compra, recetas y copias de seguridad) para ejecutar las pruebas con `swift test`.
//  La app en sí se construye con AppComida.xcodeproj; ambos usan los mismos archivos fuente.
//

import PackageDescription

let package = Package(
    name: "AppComidaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "AppComidaCore", targets: ["AppComidaCore"])],
    targets: [
        .target(
            name: "AppComidaCore",
            path: "AppComida",
            exclude: [
                "Assets.xcassets",
                "AppComida.entitlements",
                "AppViewModel+Live.swift",
                "IngredientScreens.swift",
                "MealEditorView.swift",
                "MealPlannerApp.swift",
                "MealsScreens.swift",
                "Navigator.swift",
                "PlanScreens.swift",
                "ReminderScheduler.swift",
                "SearchableSelectionList.swift",
                "SettingsScreens.swift",
                "ShoppingScreens.swift",
                "Theme.swift"
            ],
            sources: [
                "MealModels.swift",
                "MealStore.swift",
                "MenuGenerator.swift",
                "ShoppingList.swift",
                "RecipeCalculator.swift",
                "BackupService.swift",
                "TextNormalization.swift",
                "Validation.swift",
                "ReminderScheduling.swift",
                "AppViewModel.swift"
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AppComidaCoreTests",
            dependencies: ["AppComidaCore"],
            path: "Tests/AppComidaCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
