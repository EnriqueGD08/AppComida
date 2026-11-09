//
//  SettingsScreens.swift
//  AppComida
//
//  Autor: Enrique Gómez Díaz
//  Mail: enriquegd2004@gmail.com
//  Date: 2026-11-09
//  Plataforma: iOS · Swift / SwiftUI
//  Descripción: Ajustes: tema, recordatorio semanal y copias de seguridad (exportar, importar combinando o reemplazando, aviso si hace tiempo que no se hace una).
//

import SwiftUI
import UniformTypeIdentifiers

/// Tema visual elegido por el usuario: automático, claro u oscuro.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Automático"
        case .light: "Claro"
        case .dark: "Oscuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Documento JSON que envuelve una `AppBackup` para exportarla con el selector de archivos.
struct AppBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    let backup: AppBackup

    /// Crea el documento a partir de una copia de seguridad.
    /// - Parameter backup: Datos a exportar.
    init(backup: AppBackup) {
        self.backup = backup
    }

    /// Lee una copia de seguridad desde un archivo.
    /// - Parameter configuration: Configuración con el archivo leído.
    /// - Throws: Un error si el archivo está vacío o no es una copia válida.
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        backup = try JSONDecoder().decode(AppBackup.self, from: data)
    }

    /// Codifica la copia de seguridad como JSON legible para guardarla.
    /// - Parameter configuration: Configuración de escritura.
    /// - Returns: El archivo listo para guardar.
    /// - Throws: Un error si falla la codificación.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(backup))
    }
}

/// Pantalla de ajustes: tema, recordatorio semanal, copia de seguridad e información de sincronización.
struct SettingsView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Binding var appearance: String

    @State private var document = AppBackupDocument(backup: AppBackup(meals: [], ingredients: [], plan: nil, dailyCalorieGoal: 2_000))
    @State private var isExporting = false
    @State private var isChoosingImportMode = false
    @State private var isImporting = false
    @State private var pendingMode = BackupImportMode.merge

    var body: some View {
        Form {
            Section {
                Picker(selection: $appearance) {
                    ForEach(Appearance.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                } label: {
                    Label("Tema", systemImage: "paintpalette.fill")
                }
            } header: {
                Text("Apariencia")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { viewModel.remindersEnabled },
                    set: { enabled in Task { await viewModel.setRemindersEnabled(enabled) } }
                )) {
                    Label("Recordar planificar la semana", systemImage: "bell.badge")
                }
            } header: {
                Text("Recordatorios")
            } footer: {
                Text("Una notificación cada domingo a las 10:00 para generar el menú y revisar la compra.")
            }

            Section {
                LabeledContent("Última copia", value: lastBackupText)
                if viewModel.isBackupStale {
                    Label("Hace tiempo que no haces una copia de seguridad.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Button {
                    document = AppBackupDocument(backup: viewModel.makeBackup())
                    isExporting = true
                } label: {
                    Label("Exportar datos", systemImage: "square.and.arrow.up")
                }
                Button { isChoosingImportMode = true } label: {
                    Label("Importar datos", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Copia de seguridad")
            } footer: {
                Text("La copia incluye comidas, ingredientes, menú semanal, lista de la compra y objetivo diario. Al importar puedes combinarla con tus datos o reemplazarlos.")
            }

            Section {
                Label {
                    Text("La sincronización con iCloud requiere una cuenta de Apple Developer de pago. Los datos se guardan localmente en este iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "icloud.slash").foregroundStyle(Theme.accent)
                }
            } header: {
                Text("Sincronización")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Ajustes")
        .fileExporter(
            isPresented: $isExporting,
            document: document,
            contentType: .json,
            defaultFilename: "copia-seguridad-appcomida.json"
        ) { result in
            switch result {
            case .success: viewModel.markBackupExported()
            case .failure(let error): viewModel.message = "No se pudo exportar la copia de seguridad: \(error.localizedDescription)"
            }
        }
        .confirmationDialog("¿Cómo quieres importar la copia?", isPresented: $isChoosingImportMode, titleVisibility: .visible) {
            Button("Combinar con mis datos (recomendado)") {
                pendingMode = .merge
                isImporting = true
            }
            Button("Reemplazar todo", role: .destructive) {
                pendingMode = .replace
                isImporting = true
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Combinar añade lo que falte sin tocar tus comidas ni tu menú. Reemplazar borra tus datos actuales.")
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            importFile(result)
        }
    }

    /// Texto con la fecha de la última copia de seguridad.
    private var lastBackupText: String {
        viewModel.lastBackupDate?.formatted(date: .abbreviated, time: .omitted) ?? "Nunca"
    }

    /// Lee el archivo elegido (con acceso de seguridad) y se lo pasa al modelo para importarlo.
    /// - Parameter result: Resultado del selector de archivos.
    private func importFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            viewModel.importBackup(from: try Data(contentsOf: url), mode: pendingMode)
        } catch {
            viewModel.message = "No se pudo leer el archivo: \(error.localizedDescription)"
        }
    }
}
