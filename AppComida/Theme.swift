//
//  Theme.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-05
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Sistema de diseño: colores, degradados, iconos por franja y componentes visuales reutilizables (tarjetas, insignias, títulos de sección).
//

import SwiftUI

/// Constantes de diseño compartidas: color de acento, radio de esquinas y degradado principal.
enum Theme {
    static let accent = Color(red: 0.16, green: 0.60, blue: 0.42)
    static let cornerRadius: CGFloat = 20

    static let gradient = LinearGradient(
        colors: [Color(red: 0.22, green: 0.70, blue: 0.47), Color(red: 0.08, green: 0.48, blue: 0.52)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Icono y color asociados a cada franja del día.
extension MealSlot {
    var icon: String {
        switch self {
        case .breakfast: "sun.horizon.fill"
        case .lunch: "fork.knife"
        case .snack: "cup.and.saucer.fill"
        case .dinner: "moon.stars.fill"
        }
    }

    var color: Color {
        switch self {
        case .breakfast: .orange
        case .lunch: Color(red: 0.16, green: 0.60, blue: 0.42)
        case .snack: .pink
        case .dinner: .indigo
        }
    }
}

/// Fondo con un degradado suave en la parte superior.
struct AppBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground)
            Theme.gradient
                .opacity(0.14)
                .frame(height: 320)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea()
    }
}

/// Estilo de tarjeta: fondo, esquinas redondeadas y sombra suave.
private struct CardModifier: ViewModifier {
    let padding: CGFloat

    /// Aplica el estilo de tarjeta al contenido.
    /// - Parameter content: Vista a envolver.
    /// - Returns: La vista con aspecto de tarjeta.
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            )
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

/// Atajos de estilo para cualquier vista.
extension View {
    /// Presenta la vista como una tarjeta.
    /// - Parameter padding: Margen interior en puntos.
    /// - Returns: La vista con el estilo de tarjeta.
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

/// Icono dentro de un cuadrado redondeado y tintado.
struct IconBadge: View {
    let systemName: String
    var color: Color = Theme.accent
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// Título de sección con icono opcional y texto secundario a la derecha.
struct SectionTitle: View {
    let title: String
    var systemImage: String?
    var color: Color = Theme.accent
    var trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(color)
            }
            Text(title).font(.title3.weight(.bold))
            Spacer()
            if let trailing {
                Text(trailing).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Aviso de estado vacío con icono, título y mensaje.
struct EmptyCard: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}
