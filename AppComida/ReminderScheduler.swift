//
//  ReminderScheduler.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Recordatorio semanal para planificar el menú mediante notificaciones locales (no requieren cuenta de desarrollador de pago).
//

import Foundation
import UserNotifications

/// Programa el recordatorio con `UNUserNotificationCenter`: cada domingo a las 10:00.
struct UserNotificationReminderScheduler: ReminderScheduling {
    private let identifier = "weekly-menu-reminder"

    /// Activa o desactiva el recordatorio semanal, pidiendo permiso de notificaciones si hace falta.
    /// - Parameter enabled: `true` para programarlo, `false` para cancelarlo.
    /// - Returns: `true` si el estado pedido quedó aplicado.
    func setWeeklyMenuReminder(enabled: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard enabled else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return true
        }
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { return false }
            let content = UNMutableNotificationContent()
            content.title = "Planifica tu semana"
            content.body = "Genera el menú y revisa la lista de la compra."
            content.sound = .default
            var when = DateComponents()
            when.weekday = 1
            when.hour = 10
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            return true
        } catch {
            return false
        }
    }
}
