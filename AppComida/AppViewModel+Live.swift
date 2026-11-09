//
//  AppViewModel+Live.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Fábrica del modelo con las implementaciones reales (archivos JSON, generador de menús y notificaciones locales). Solo la usa la app; las pruebas inyectan implementaciones falsas.
//

import Foundation

extension AppViewModel {
    /// Crea el modelo con las implementaciones reales para ejecutar la app.
    /// - Returns: Un `AppViewModel` listo para usar.
    static func live() -> AppViewModel {
        AppViewModel(store: FileMealStore(), generator: MenuGenerator(), reminders: UserNotificationReminderScheduler())
    }
}
