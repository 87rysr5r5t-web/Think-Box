# Think Box

Aplicación personal de escritura para macOS. Reúne borradores, notas, PDF, lienzos JSON Canvas y otros archivos en bases de datos locales.

## Primer uso

1. Escoge una base en **Bases de datos**. Desde el botón **+** puedes crear una base o abrir el JSON de otra biblioteca de Think Box.
2. Crea un grupo con el botón **+** junto a **Grupos**. Puedes escribir en **Entrada** y clasificar el texto más adelante.
3. Pulsa **Nuevo texto Markdown** para escribir o **Importar archivos…** para añadir material de referencia. El inspector permite cambiar el estado, editar etiquetas y asignar el mismo documento a varios grupos.
4. Busca por título, contenido o etiqueta en la vista actual. La consulta `tag:Fuentes tag:"Trabajo de campo"` exige ambas etiquetas. El botón de marcador guarda la búsqueda en la base activa.
5. **Enlaces** permite copiar una referencia Markdown al documento y seguir referencias a otros documentos o fragmentos. Las referencias sobreviven a cambios de título.

## Ajustes

Abre **Ajustes** desde el engranaje de la barra lateral o con `⌘,`. Los cambios de tipografía y aspecto se aplican a la ventana abierta y se recuerdan al reiniciar.

- **Apariencia** permite elegir tema, fuente y tamaños de interfaz y lista, además del ancho y la densidad de la barra lateral.
- **Editor** permite elegir fuente, tamaño, interlineado, ancho, ajuste de líneas y colores, mostrar el recuento de palabras y configurar la corrección y las sustituciones de escritura.
- **Biblioteca** reúne orden, fechas, extensiones, etiquetas y reglas de etiquetado. **Lectura** controla la vista inicial de PDF, el autor de las anotaciones y la cuadrícula y el encuadre del canvas.

Think Box incluye iA Writer Quattro, de Information Architects, para la interfaz y JetBrains Mono Light para el editor. Las dos fuentes y sus licencias SIL Open Font License se distribuyen con la app. [iA Writer Quattro](https://github.com/iaolo/iA-Fonts/tree/master/iA%20Writer%20Quattro) · [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono/tree/v2.304).

## Navegación rápida

- **⇧⌘P** abre la paleta de comandos. Escribe unas letras de la acción y pulsa Intro. Las flechas cambian la selección.
- **⌘P** busca documentos y grupos por nombre en todas las bases abiertas e indica la base de cada resultado.
- **⌘O** abre otra base de Think Box. La barra lateral y el selector de la ruta muestran la base activa.
- **⇧⌘L** muestra u oculta la barra lateral. **⌘F** vuelve al campo de búsqueda de la biblioteca.

## Plegar paneles con el trackpad

- Sobre **Navegación** o la **lista de documentos**, desliza dos dedos a la izquierda para plegar. Sobre el **inspector**, deslízalos a la derecha.
- Para desplegar, parte del borde del panel cerrado y desliza hacia el centro. El borde de la lista queda junto a la barra de navegación cuando está abierta. En disposición vertical, parte de la franja superior del visor para recuperar la lista.
- Si la cascada está activa, sobre la mitad izquierda del visor de texto se pliega primero Navegación y luego la lista. En la dirección inversa se recuperan en orden contrario. Sobre la mitad derecha del visor se controla el inspector.
- En **Ajustes → Gestos** puedes desactivar los gestos, invertir la dirección, desactivar la cascada y ajustar el recorrido y el ancho de la zona del borde.

Consulta el [registro de atajos](docs/ATAJOS.md) y el [inventario de paridad](docs/PARIDAD_DEVONTHINK.md).

## Vista de página

- Abre un texto Markdown o de texto plano y usa el selector **Editor**, **Previsualización** o **Dividido**. El botón con forma de hoja de cada panel activa su paginación de forma independiente. Puedes guardar valores iniciales distintos en **Ajustes → Página**.
- **Formato → Configurar página…** permite elegir el papel, la orientación, los márgenes, las columnas para la salida y los encabezados y pies. El botón de regla del editor paginado muestra los márgenes arrastrables.
- **⌘↩** inserta un salto de página. El archivo de texto guarda el marcador `<div style="page-break-after: always"></div>` en su propia línea. Los saltos dentro de bloques de código Markdown se muestran como código.
- Los menús de zoom permiten ajustar el ancho, mostrar una hoja completa o elegir un porcentaje. La previsualización ofrece páginas enfrentadas y miniaturas. Pulsa el contador del pie para saltar a otra página.
- **Exportar a PDF…** e **Imprimir…** usan la composición de la previsualización paginada. **Exportar documento…** guarda el formato de origen.
- Markdown admite tablas de separadores verticales, imágenes locales en su propia línea y notas con la sintaxis `[^id]` y `[^id]: Texto de la nota`. Las definiciones se muestran al pie de la página de la referencia. Al importar Markdown se copian las imágenes relativas que estén en la carpeta del archivo o dentro de ella.
- Abre **Ir → Espacios de trabajo** para guardar y recuperar la base y selección de las pestañas, la disposición, los paneles y las ventanas de documento.

## Etiquetas y fragmentos

- Escribe `Fuentes/Archivo/Cartas` para crear una rama de etiquetas. Al abrir `Fuentes` aparecen los resultados de sus subetiquetas. Puedes mover una rama, cambiarle el nombre o asignar etiquetas arrastrando un resultado sobre ellas.
- En Markdown, selecciona una cita y abre **Selección**. **Etiquetar fragmento** indexa la selección. **Copiar enlace al fragmento** genera una URL `thinkbox://` que puedes pegar en cualquier texto. En el visor PDF también puedes enlazar páginas y posiciones de anotaciones.
- Desde **Acciones de biblioteca → Reglas de etiquetado** puedes activar etiquetas derivadas de grupos, herencia de etiquetas del grupo, hashtags en líneas independientes, intercambio con Finder y palabras clave de PDF. El menú contextual del grupo permite editar sus etiquetas o excluirlo de las reglas dinámicas.

## PDF, otros archivos y canvas

- **PDF.** Miniaturas, índice, panel de anotaciones, búsqueda en el documento, zoom, modos de página, resaltado, subrayado, tachado, notas, giro, formularios compatibles, impresión y exportación de la página actual. Las anotaciones y el giro modifican la copia de la biblioteca. El OCR en español e inglés añade texto a la búsqueda de la biblioteca. La selección y la búsqueda dentro de un PDF dependen de su capa de texto.
- **Otros formatos.** Vista previa mediante Quick Look, según los formatos y extensiones disponibles en macOS. Los archivos con texto extraíble ofrecen también la vista **Texto** para buscar y etiquetar fragmentos.
- **JSON Canvas.** Importa un `.canvas` o crea uno con **Acciones de biblioteca → Nuevo canvas**. Admite tarjetas Markdown, archivos, enlaces y grupos, además de conexiones editables. Usa doble clic para abrir una tarjeta, arrastra para moverla y usa la esquina para redimensionarla. Puedes vincular la carpeta raíz de la bóveda para resolver archivos relativos o exportar el lienzo editado como `.canvas`.

Usa el clic secundario sobre una fila y elige **Mover a la papelera**. En **Papelera**, el menú contextual ofrece **Restaurar de la papelera** y recupera las pertenencias a grupos y las etiquetas.

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

La base predeterminada se guarda en `~/Library/Application Support/Think Box/Biblioteca.json` y los archivos importados en la carpeta contigua `Biblioteca.assets`. Para usar una base de prueba independiente, inicia el ejecutable con `THINKBOX_LIBRARY_PATH` apuntando a otro archivo. Cierra la app y copia ambos como respaldo. Las bibliotecas de la primera versión se abren y pasan al formato 2 al guardar el primer cambio.

## Diseño

La [nota de investigación](docs/modelo-devonthink.md) recoge el comportamiento documentado de DEVONthink y cómo se traduce en Think Box. La biblioteca y su persistencia se implementan en `Sources/WritingLibrary`. La interfaz macOS y los diálogos de archivos están en `Sources/ThinkBox`.
