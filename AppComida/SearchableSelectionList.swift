//
//  SearchableSelectionList.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Lista genérica de selección con búsqueda por nombre (sin distinguir mayúsculas ni tildes), reutilizada para elegir ingredientes y comidas.
//

import SwiftUI

/// Lista de elementos con barra de búsqueda; al pulsar uno se llama a `onSelect` y se cierra la pantalla.
///
/// Es genérica para cumplir el principio abierto/cerrado: sirve para cualquier tipo de elemento sin modificarla.
struct SearchableSelectionList<Item: Identifiable, Row: View>: View {
    @Environment(\.dismiss) private var dismiss

    let items: [Item]
    let title: String
    let prompt: String
    /// Texto sobre el que se busca en cada elemento.
    let searchText: (Item) -> String
    let isSelected: (Item) -> Bool
    let onSelect: (Item) -> Void
    @ViewBuilder let row: (Item) -> Row

    @State private var query = ""

    /// Elementos que coinciden con la búsqueda actual.
    private var filtered: [Item] {
        let key = query.searchKey
        return key.isEmpty ? items : items.filter { searchText($0).searchKey.contains(key) }
    }

    var body: some View {
        List(filtered) { item in
            Button {
                onSelect(item)
                dismiss()
            } label: {
                HStack {
                    row(item)
                    Spacer()
                    if isSelected(item) {
                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if filtered.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
