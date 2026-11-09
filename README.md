# AppComida

Aplicación iOS (SwiftUI) para planificar el menú semanal, ajustarlo a un objetivo de calorías y obtener la lista de la compra. Todo se guarda en local, sin cuentas ni pagos.

**Autor:** Enrique Gómez Díaz · enriquegd2004@gmail.com

## Funciones

- **Comidas:** recetas con ingredientes del catálogo, raciones, favoritas, duplicar y búsqueda por nombre.
- **Ingredientes:** catálogo con calorías, macronutrientes por 100 g, peso por unidad (un huevo ≈ 60 g) y sección del supermercado. Las calorías y los macronutrientes de cada receta se calculan solos.
- **Menú semanal:** genera 7 días (desayuno, almuerzo, merienda y cena) cercanos al objetivo diario, con variedad aleatoria y sin repetir mientras haya alternativas.
  - Se puede **cambiar cualquier comida**, ajustar las **raciones** (admite medias) y **bloquearla** para que se conserve al regenerar.
  - Avisa si el menú guardado es de otra semana.
- **Compra:** suma los ingredientes de la semana según las raciones, en unidades o kg/g, agrupados por sección del supermercado. Admite productos manuales, "ya lo tengo en casa", casillas de comprado y compartir como texto.
- **Copias de seguridad:** exportar/importar JSON. Al importar se puede **combinar** (sin perder nada, completando datos que falten) o **reemplazar**. Aviso si hace más de 14 días de la última copia.
- **Recordatorio semanal:** notificación local cada domingo a las 10:00.

## Importar ingredientes

[`ingredientes-importar.json`](ingredientes-importar.json) contiene 154 ingredientes (73 genéricos y 81 de Mercadona, con datos de etiqueta de Open Food Facts) con calorías, macronutrientes, sección y, cuando procede, peso por unidad. Impórtalo desde *Ajustes → Importar datos → Combinar con mis datos*.

## Arquitectura

La lógica está separada de la interfaz y depende de abstracciones (principios SOLID):

| Capa | Archivos | Responsabilidad |
| --- | --- | --- |
| Modelos | `MealModels.swift` | Datos `Codable`, compatibles con copias antiguas |
| Persistencia | `MealStore.swift` | Protocolos pequeños por tipo de dato (`MealRepository`, `PlanRepository`…) y su implementación en JSON |
| Lógica de dominio | `MenuGenerator.swift`, `ShoppingList.swift`, `RecipeCalculator.swift`, `BackupService.swift`, `Validation.swift` | Funciones puras, sin interfaz ni disco |
| Casos de uso | `AppViewModel.swift` | Estado y operaciones; recibe el almacén, el generador y los recordatorios **por protocolo** |
| Navegación | `Navigator.swift` | Pestaña activa y hojas abiertas |
| Interfaz | `*Screens.swift`, `MealEditorView.swift`, `SearchableSelectionList.swift`, `Theme.swift` | Vistas SwiftUI que solo leen el modelo y llaman a sus métodos |
| Dispositivo | `ReminderScheduler.swift`, `AppViewModel+Live.swift` | Notificaciones locales y composición con las implementaciones reales |

## Pruebas

La lógica (modelos, generador, compra, recetas, copias, validación y `AppViewModel` con dependencias falsas) se prueba con Swift Testing:

```bash
swift test
```

`Package.swift` compila los mismos archivos fuente que la app solo para poder ejecutar las pruebas desde la línea de comandos; la app se construye con `AppComida.xcodeproj`.

## Limitaciones

- Sin sincronización con iCloud (requiere cuenta de desarrollador de pago).
- Con una cuenta gratuita de Apple, la app instalada en el iPhone caduca a los 7 días y hay que reinstalarla desde Xcode; los datos se conservan si se reinstala sobre la misma app, y conviene hacer copia de seguridad.
