//
//  TextNormalization.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Utilidad para normalizar textos (sin mayúsculas ni tildes) y compararlos de forma tolerante.
//

import Foundation

extension String {
    /// Versión del texto sin mayúsculas, tildes ni espacios sobrantes.
    ///
    /// Sirve como clave para agrupar nombres equivalentes ("Plátano" y "platano")
    /// y para comparar sin distinguir acentos.
    public var searchKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
