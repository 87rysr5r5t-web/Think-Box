# Think Box

Aplicación personal de escritura para macOS. Reúne borradores, notas, PDF, lienzos JSON Canvas y otros archivos en una biblioteca local.

## Primer uso

1. Crea un proyecto con el botón `+` junto a **Proyectos**. También puedes escribir en **Entrada** y clasificar el texto más adelante.
2. Pulsa **Nuevo texto** para escribir o **Importar archivos…** para añadir material de referencia.
3. Abre **Etiquetas** al pie del documento para clasificarlo, cambiar su estado o asignarlo a varios proyectos. Cada proyecto muestra el mismo documento y sus ediciones.
4. Busca por título, contenido o etiqueta. `tag:Fuentes tag:"Trabajo de campo"` exige ambas etiquetas. El marcador junto al campo guarda la consulta como una vista dinámica de toda la biblioteca.
5. **Enlaces** permite copiar una referencia Markdown al documento y seguir referencias a otros documentos o fragmentos. Las referencias sobreviven a cambios de título.

## Ajustes

Abre **Ajustes** desde el engranaje de la barra lateral o con `⌘,`. Los cambios de tipografía y aspecto se aplican a la ventana abierta y se recuerdan al reiniciar.

- **Apariencia** permite elegir tema, fuente y tamaños de interfaz y lista, además del ancho y la densidad de la barra lateral.
- **Editor** permite elegir fuente, tamaño, interlineado, ancho, ajuste de líneas y colores, mostrar el recuento de palabras y configurar la corrección y las sustituciones de escritura.
- **Biblioteca** reúne orden, fechas, extensiones, etiquetas y reglas de etiquetado. **Lectura** controla la vista inicial de PDF, el autor de las anotaciones y la cuadrícula y el encuadre del canvas.

Think Box incluye iA Writer Quattro, de Information Architects, para la interfaz y JetBrains Mono Light para el editor. Las dos fuentes y sus licencias SIL Open Font License se distribuyen con la app. [iA Writer Quattro](https://github.com/iaolo/iA-Fonts/tree/master/iA%20Writer%20Quattro) · [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono/tree/v2.304).

## Navegación rápida

- **⇧⌘P** abre la paleta de comandos. Escribe unas letras de la acción y pulsa Intro. Las flechas cambian la selección.
- **⌘P** busca documentos y proyectos de la biblioteca por nombre.
- **⇧⌘L** muestra u oculta la barra lateral. **⌘F** vuelve al campo de búsqueda de la biblioteca.

Consulta el [registro de atajos](docs/ATAJOS.md) y el [inventario de paridad](docs/PARIDAD_DEVONTHINK.md).

## Etiquetas y fragmentos

- Escribe `Fuentes/Archivo/Cartas` para crear una rama de etiquetas. Al abrir `Fuentes` aparecen los resultados de sus subetiquetas. Puedes mover una rama, cambiarle el nombre o asignar etiquetas arrastrando un resultado sobre ellas.
- En Markdown, selecciona una cita y abre **Selección**. **Etiquetar fragmento** indexa la selección. **Copiar enlace al fragmento** genera una URL `thinkbox://` que puedes pegar en cualquier texto. En el visor PDF también puedes enlazar páginas y posiciones de anotaciones.
- Desde **Acciones de biblioteca → Reglas de etiquetado** puedes activar etiquetas derivadas de proyectos, herencia de etiquetas del proyecto, hashtags en líneas independientes, intercambio con Finder y palabras clave de PDF. El menú contextual del proyecto permite editar sus etiquetas o excluirlo de las reglas dinámicas.

## PDF, otros archivos y canvas

- **PDF.** Miniaturas, índice, panel de anotaciones, búsqueda en el documento, zoom, modos de página, resaltado, subrayado, tachado, notas, giro, formularios compatibles, impresión y exportación de la página actual. Las anotaciones y el giro modifican la copia de la biblioteca. El OCR en español e inglés añade texto a la búsqueda de la biblioteca. La selección y la búsqueda dentro de un PDF dependen de su capa de texto.
- **Otros formatos.** Vista previa mediante Quick Look, según los formatos y extensiones disponibles en macOS. Los archivos con texto extraíble ofrecen también la vista **Texto** para buscar y etiquetar fragmentos.
- **JSON Canvas.** Importa un `.canvas` o crea uno con **Acciones de biblioteca → Nuevo canvas**. Admite tarjetas Markdown, archivos, enlaces y grupos, además de conexiones editables. Usa doble clic para abrir una tarjeta, arrastra para moverla y usa la esquina para redimensionarla. Puedes vincular la carpeta raíz de la bóveda para resolver archivos relativos o exportar el lienzo editado como `.canvas`.

Puedes enviar cualquier documento a **Papelera** y restaurarlo desde allí.

## Compilar y ejecutar

Requiere macOS 14 o posterior y Swift 6.

```sh
swift test
./scripts/build-app.sh
```

El script genera un ZIP con la versión en `dist`. Extrae el archivo en una carpeta local para abrir `Think Box.app`.

Si las Command Line Tools muestran `TestingMacros ... not found`, ejecuta las pruebas con el complemento del compilador explícito.

```sh
swift test -Xswiftc -load-plugin-library \
  -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
```

La app guarda la biblioteca en `~/Library/Application Support/Think Box/Biblioteca.json` y los archivos importados en la carpeta contigua `Biblioteca.assets`. Para usar una biblioteca de prueba independiente, inicia el ejecutable con `THINKBOX_LIBRARY_PATH` apuntando a otro archivo. Cierra la app y copia ambos como respaldo. Las bibliotecas de la primera versión se abren y pasan al formato 2 al guardar el primer cambio.

## Diseño

La [nota de investigación](docs/modelo-devonthink.md) recoge el comportamiento documentado de DEVONthink y cómo se traduce en Think Box. La biblioteca y su persistencia se implementan en `Sources/WritingLibrary`. La interfaz macOS y los diálogos de archivos están en `Sources/ThinkBox`.
