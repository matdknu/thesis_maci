# Presentación del proyecto (estilo wiki-chile / COMPTEXT)

Réplica del formato de  
`/social-data-science/wiki-chile_project/presentation-comptext/`  
adaptada a la **tesis MACI** (Reddit, NLP, UdeC).

## Archivos

| Archivo | Rol |
|---------|-----|
| **`presentation.qmd`** | Diapositivas principales (Reveal.js) |
| **`comptext-theme.css`** | Tema visual (portada dividida, tablas, thank-you slide) |
| **`chile-candidatos.webp`** | Imagen de portada / cierre (panel izquierdo o derecho) |

> Si cambias el nombre de la imagen, actualiza las URLs en `comptext-theme.css` (`url("…")`).

## Compilar

```bash
cd documents/presentacion_proyecto
quarto render presentation.qmd
```

Salida: **`presentation.html`** (abrir en el navegador). Misma configuración Reveal que `presentation-comptext/presentation.qmd` (tema `simple`, `margin: 0.2`, etc.).

## Figuras embebidas

Las slides usan gráficos desde `../../outputs/thesis_figures/`. Ejecuta antes los scripts de análisis si esas rutas aún no existen.

## Versión anterior

`presentacion_proyecto.qmd` era la presentación genérica; el flujo recomendado es **`presentation.qmd`**.
