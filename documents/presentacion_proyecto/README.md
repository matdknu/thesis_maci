# Presentación del proyecto (estilo wiki-chile / COMPTEXT)

Réplica del formato de  
`/social-data-science/wiki-chile_project/presentation-comptext/`  
adaptada a la **tesis MACI** (Reddit, NLP, UdeC).

**Enlace directo a la presentación:**  
[https://matdknu.github.io/thesis_maci/documents/presentacion_proyecto/presentation.html](https://matdknu.github.io/thesis_maci/documents/presentacion_proyecto/presentation.html)

## Versión en línea (GitHub Pages)

GitHub Pages solo publica lo que está en **`docs/`** en la rama que uses para Pages. La presentación se **mantiene sincronizada automáticamente** allí de dos maneras:

1. Al renderizar la propia presentación:

```bash
cd documents/presentacion_proyecto
quarto render presentation.qmd
```

Eso dispara `sync-presentation-to-docs.sh` mediante `documents/presentacion_proyecto/_quarto.yml` y actualiza la copia publicada en `docs/documents/presentacion_proyecto/`.

2. Al renderizar el libro Quarto:

```bash
cd documents/tesis_book
quarto render
```

Eso ejecuta `copy-presentation-to-docs.sh` (`project.post-render` en `_quarto.yml`): vuelve a renderizar `presentation.qmd` y sincroniza **`docs/documents/presentacion_proyecto/`** (`presentation.html`, `presentation_files/`, `comptext-theme.css`, `images/`, etc.).

URL pública (tras **`git add docs/`** y push):

[**https://matdknu.github.io/thesis_maci/documents/presentacion_proyecto/presentation.html**](https://matdknu.github.io/thesis_maci/documents/presentacion_proyecto/presentation.html)

Fuente: [`documents/presentacion_proyecto/presentation.qmd`](https://github.com/matdknu/thesis_maci/blob/main/documents/presentacion_proyecto/presentation.qmd).

Si quieres forzar la sincronización sin renderizar el libro:

```bash
documents/presentacion_proyecto/sync-presentation-to-docs.sh
```

## Archivos

| Archivo | Rol |
|---------|-----|
| **`presentation.qmd`** | Diapositivas principales (Reveal.js) |
| **`comptext-theme.css`** | Tema visual (portada dividida, tablas, thank-you slide) |
| **`chile-candidatos.webp`** | Imagen de portada / cierre (panel izquierdo o derecho) |
| **`export-presentation-pdf.sh`** | Script para generar **`presentation.pdf`** vía Decktape (misma apariencia que el HTML) |

> Si cambias el nombre de la imagen de portada, actualiza las URLs en `comptext-theme.css` (`url("…")`).

## Compilar

```bash
cd documents/presentacion_proyecto
quarto render presentation.qmd
```

Salida: **`presentation.html`** (abrir en el navegador). Misma configuración Reveal que `presentation-comptext/presentation.qmd` (tema `simple`, `margin: 0.2`, etc.).

### Exportar PDF (captura slide a slide)

```bash
./export-presentation-pdf.sh
```

Genera **`presentation.pdf`** en esta carpeta (requiere Node/`npx` para Decktape). El script elige un puerto HTTP local libre automáticamente.

## Figuras embebidas

Las slides usan gráficos desde `../../outputs/thesis_figures/`. Ejecuta antes los scripts de análisis si esas rutas aún no existen.

## Versión anterior

`presentacion_proyecto.qmd` era la presentación genérica; el flujo recomendado es **`presentation.qmd`**.
