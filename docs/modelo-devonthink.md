# Modelo de trabajo de DEVONthink aplicado a Think Box

Estudio funcional para una herramienta personal de escritura. La referencia es DEVONthink 4.4.2, identificado en el paquete instalado en este Mac. Las observaciones proceden de la documentación del fabricante y del diccionario público de AppleScript de esa versión (`Contents/Resources/DEVONthink.sdef`).

| Comportamiento documentado | Implementación en Think Box |
| --- | --- |
| Una base contiene registros. Los grupos organizan esos registros y un replicante representa el mismo registro en otro grupo. | Una biblioteca local contiene proyectos y textos. Un texto guarda su pertenencia a varios proyectos y se edita siempre por su identificador. Los textos sin proyecto aparecen en Entrada. |
| Los UUID son persistentes y permiten identificar un registro en un enlace. | Cada texto tiene un UUID y un enlace `thinkbox://document/…`. El enlace sigue funcionando al cambiar el título o los proyectos. |
| Los grupos inteligentes muestran los registros que cumplen una consulta. | Una búsqueda guardada se evalúa contra los textos activos. Cada término debe aparecer en el título, en el contenido o en alguna etiqueta. |
| La escritura y la organización conviven en la biblioteca. DEVONthink admite Markdown y la importación y exportación de registros. | El texto Markdown se edita con guardado automático. El estado, las etiquetas y los proyectos se gestionan desde el propio documento. Los archivos Markdown se importan y exportan de forma individual. |

## Decisiones de la primera versión

- **Interfaz.** Navegación y resultados comparten un panel de biblioteca. El resto de la ventana se dedica a escribir. Los detalles y enlaces se abren junto al pie del editor.
- **Persistencia.** El archivo de biblioteca reúne contenido y metadatos y se reemplaza atómicamente. La búsqueda recorre la biblioteca en memoria. Una biblioteca grande requerirá almacenamiento por documento y un índice de texto completo.
- **Etiquetas y destinos.** La biblioteca usa rutas jerárquicas por etiqueta. Las reglas dinámicas se evalúan al consultar. Los destinos de fragmentos conservan un UUID dentro de la ficha del documento, además de texto y contexto o posición en PDF. [Etiquetas de DEVONthink](https://download.devontechnologies.com/download/devonthink/3.8.2/DEVONthink.help/Contents/Resources/pgs/gettingstarted-tagging.html) · [Enlaces a selecciones](https://www.devontechnologies.com/blog/devonthink-39).
- **Archivos.** Los PDF y otros originales se copian a `Biblioteca.assets`. Para verlos se usan PDFKit y Quick Look. Los canvas se guardan como JSON Canvas y se exportan con los campos de extensión que estuvieran presentes. Los archivos enlazados se resuelven dentro de la carpeta asociada al canvas. [PDFKit](https://developer.apple.com/documentation/pdfkit/pdfview) · [JSON Canvas 1.0](https://jsoncanvas.org/spec/1.0/).

## Fuentes de referencia

- Biblioteca, organización y edición. [Presentación oficial de DEVONthink](https://www.devontechnologies.com/apps/devonthink).
- Replicantes y grupos inteligentes. [Glosario de DEVONthink](https://download.devontechnologies.com/download/devonthink/3.8.2/DEVONthink.help/Contents/Resources/pgs/appendix-glossary.html).
- Enlaces de elemento y referencias cruzadas. [Your Knowledge Base](https://www.devontechnologies.com/apps/devonthink/linking).
- API de automatización consultada en el diccionario instalado. `database` y `record`, `uuid`, `reference URL`, `replicate`, `get record with uuid`, `search predicates`, `import path` y `export`.
