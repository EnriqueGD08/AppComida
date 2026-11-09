//
//  ShoppingScreens.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Pestaña "Compra": lista de ingredientes de la semana agrupada por secciones del supermercado, con productos manuales, "ya lo tengo en casa", casillas de comprado y compartir.
//

import SwiftUI

/// Pestaña "Compra": lista de los ingredientes de la semana agrupada por secciones.
struct ShoppingTabView: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var isAddingItem = false
    @State private var newItemName = ""
    @State private var newItemQuantity = ""

    private var items: [ShoppingItem] { viewModel.shoppingItems }
    private var manualItems: [ManualShoppingItem] { viewModel.extras.manualItems }
    private var pantryItems: [ShoppingItem] { viewModel.pantryItems }
    private var total: Int { items.count + manualItems.count }
    private var done: Int { items.filter(viewModel.isChecked).count + manualItems.filter { viewModel.isChecked($0) }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                if total == 0 && pantryItems.isEmpty {
                    EmptyCard(
                        systemImage: "cart",
                        title: "Lista vacía",
                        message: "Genera un menú semanal y aquí aparecerán los ingredientes que necesitas comprar. También puedes añadir productos a mano con +."
                    )
                } else {
                    LazyVStack(spacing: 10) {
                        summary
                        ForEach(ShoppingListBuilder.sections(of: items)) { section in
                            sectionHeader(section.category)
                            ForEach(sorted(section.items)) { item in
                                row(item)
                            }
                        }
                        if !manualItems.isEmpty {
                            SectionTitle(title: "Añadido a mano", systemImage: "pencil.and.list.clipboard", color: .indigo)
                                .padding(.top, 10)
                            ForEach(manualItems) { item in
                                manualRow(item)
                            }
                        }
                        if !pantryItems.isEmpty { pantrySection }
                        if viewModel.plan != nil {
                            Text("Cantidades según las raciones de cada comida del plan. Mantén pulsado un producto para marcarlo como \"ya lo tengo\".")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .animation(.snappy, value: viewModel.extras)
                }
            }
            .background(AppBackground())
            .navigationTitle("Compra")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isAddingItem = true } label: { Label("Añadir producto", systemImage: "plus") }
                }
                if total > 0 {
                    ToolbarItem(placement: .secondaryAction) {
                        ShareLink(item: ShoppingListBuilder.plainText(for: items, manual: manualItems)) {
                            Label("Compartir lista", systemImage: "square.and.arrow.up")
                        }
                    }
                    ToolbarItem(placement: .secondaryAction) {
                        Button { viewModel.resetChecks() } label: { Label("Desmarcar todo", systemImage: "arrow.uturn.backward") }
                    }
                }
            }
            .alert("Añadir producto", isPresented: $isAddingItem) {
                TextField("Nombre", text: $newItemName)
                TextField("Cantidad (opcional)", text: $newItemQuantity)
                Button("Añadir") {
                    viewModel.addManualItem(name: newItemName, quantity: newItemQuantity)
                    newItemName = ""
                    newItemQuantity = ""
                }
                Button("Cancelar", role: .cancel) {
                    newItemName = ""
                    newItemQuantity = ""
                }
            }
        }
    }

    // MARK: Componentes

    /// Productos de una sección con los marcados al final.
    /// - Parameter items: Productos de la sección.
    /// - Returns: Los productos pendientes seguidos de los comprados.
    private func sorted(_ items: [ShoppingItem]) -> [ShoppingItem] {
        items.filter { !viewModel.isChecked($0) } + items.filter(viewModel.isChecked)
    }

    /// Resumen con el progreso de la compra.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(done) de \(total)").font(.system(.title2, design: .rounded).weight(.bold))
                Text("productos comprados").foregroundStyle(.secondary)
                Spacer()
                if total > 0 && done == total {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.accent)
                }
            }
            ProgressView(value: Double(done), total: Double(max(total, 1))).tint(Theme.accent)
        }
        .card()
        .padding(.bottom, 6)
    }

    /// Cabecera de una sección del supermercado.
    /// - Parameter category: Sección.
    /// - Returns: El título con su icono.
    private func sectionHeader(_ category: IngredientCategory) -> some View {
        SectionTitle(title: category.title, systemImage: category.icon, color: Theme.accent).padding(.top, 10)
    }

    /// Fila de un producto del plan con su casilla, nombre y cantidad.
    /// - Parameter item: Producto a mostrar.
    /// - Returns: La fila pulsable.
    private func row(_ item: ShoppingItem) -> some View {
        let isDone = viewModel.isChecked(item)
        return Button {
            viewModel.toggleChecked(item)
        } label: {
            HStack(spacing: 14) {
                checkmark(isDone)
                Text(item.name).font(.headline).strikethrough(isDone).multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Text(item.quantityText)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.trailing)
            }
            .opacity(isDone ? 0.5 : 1)
            .card(padding: 14)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isDone)
        .contextMenu {
            Button { viewModel.addToPantry(item) } label: { Label("Ya lo tengo en casa", systemImage: "house") }
        }
    }

    /// Fila de un producto añadido a mano.
    /// - Parameter item: Producto manual.
    /// - Returns: La fila pulsable.
    private func manualRow(_ item: ManualShoppingItem) -> some View {
        let isDone = viewModel.isChecked(item)
        return Button {
            viewModel.toggleChecked(item)
        } label: {
            HStack(spacing: 14) {
                checkmark(isDone)
                Text(item.name).font(.headline).strikethrough(isDone).multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if !item.quantity.isEmpty {
                    Text(item.quantity)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.indigo)
                }
            }
            .opacity(isDone ? 0.5 : 1)
            .card(padding: 14)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { viewModel.removeManualItem(item) } label: { Label("Eliminar", systemImage: "trash") }
        }
    }

    /// Icono de casilla marcada o vacía.
    /// - Parameter isDone: Si está marcada.
    /// - Returns: El icono.
    private func checkmark(_ isDone: Bool) -> some View {
        Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundStyle(isDone ? Theme.accent : Color.secondary.opacity(0.5))
    }

    /// Productos del plan que ya están en casa, con opción de devolverlos a la lista.
    private var pantrySection: some View {
        DisclosureGroup {
            VStack(spacing: 8) {
                ForEach(pantryItems) { item in
                    HStack {
                        Text(item.name)
                        Spacer()
                        Text(item.quantityText).foregroundStyle(.secondary)
                        Button { viewModel.removeFromPantry(item) } label: {
                            Image(systemName: "arrow.uturn.backward.circle")
                        }
                        .accessibilityLabel("Volver a la lista")
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Ya en casa (\(pantryItems.count))", systemImage: "house")
                .font(.headline)
        }
        .card()
        .padding(.top, 10)
    }
}
