//
//  ReminderScheduling.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Contrato para programar el recordatorio semanal, independiente de la implementación con notificaciones (permite sustituirla en pruebas).
//

import Foundation

/// Contrato para programar el recordatorio semanal.
protocol ReminderScheduling {
    /// Activa o desactiva el recordatorio semanal.
    /// - Parameter enabled: `true` para programarlo, `false` para cancelarlo.
    /// - Returns: `true` si el estado pedido quedó aplicado; `false` si no se pudo activar (por ejemplo, sin permiso de notificaciones).
    func setWeeklyMenuReminder(enabled: Bool) async -> Bool
}
