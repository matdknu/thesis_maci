# Ajuste visual Quarto -> estilo gitbook

Este ajuste mantiene la infraestructura Quarto intacta y solo modifica la capa visual.

## Cambios realizados

- Se reemplazó `custom.scss` para emular un look tipo `bookdown::gitbook`:
  - columna central de lectura (`max-width: 800px`);
  - sidebar izquierdo jerárquico y sobrio;
  - TOC derecho minimalista;
  - tipografía académica serif en contenido y sans-serif en navegación;
  - bloques de código, tablas, citas, figuras, callouts y paginación inferior con estilo sobrio.
- Se ajustó `_quarto.yml` con cambios mínimos:
  - `theme: [cosmo, custom.scss]`;
  - `book.sidebar.style: docked`;
  - `page-layout: article`;
  - `toc-location: right`;
  - `number-sections: true` (se mantiene activo);
  - título de capítulos en español (`section-title-chapter: "Capítulo"`).
- Se mantuvo `project.output-dir: ../../docs` para GitHub Pages.

## Render local

Desde `documents/tesis_book/`:

```bash
quarto render
```

## Verificación de assets para GitHub Pages

1. Confirmar que existen archivos en `../../docs/site_libs/`.
2. Verificar que `.gitignore` no excluya `site_libs` ni `docs/site_libs`.

## Publicación

Desde la raíz del repo:

```bash
git add docs/
git add documents/tesis_book/_quarto.yml documents/tesis_book/custom.scss documents/tesis_book/README_estilo_gitbook.md
git commit -m "Ajusta estilo Quarto a look gitbook sobrio"
git push
```

Luego esperar 1-2 minutos para el refresh de GitHub Pages.
