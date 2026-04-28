# Scripts (flujo reproducible — medulla)

Este directorio existe para **documentar orden y dependencias** entre etapas (scraping → limpieza → modelado / figuras). Los **datasets extensos** y las **credenciales** no se versionan en GitHub (`data/`, `.env`, claves); el principio público aquí es: **solo código trazable** que, ante datos válidos locales, permite regenerar derivados sin sustituir resultados “a mano”.

## Orden conceptual

```
scrapping/     →  [data/ local, ignorada en .git]  →  analisis/  →  outputs locales y assets copiados a documents/tesis_book/fig_thesis/ cuando la tesina los cita
```

## `scrapping/`

| Ruta | Rol |
|------|-----|
| `01_scrapping_reddit.py` | Captura `r/chile` (candidatos generales) |
| `02_scrapping_derecha.py` | Captura `r/RepublicadeChile` (derecha) |
| `03_scrapping_trends.py` | Google Trends |
| `sondeos_wikipedia_2025/` | Sondeos presidenciales 2025 (Wikipedia; ver `README.md` y `scrap_sondeos_wikipedia_2025.py` + `graficos_tendencia_sondeos.R`) |

## `analisis/`

Scripts R/Python que implementan limpieza, APIs de anotación, modelado y figuras (por ejemplo `01_limpieza.R`, `03_aplicacion_api.py`, `06_analisis_polarizacion.py`, `run_tesis_full.py`, etc.). No hay una única “única línea de comando” obligatoria: el punto de partida depende de qué capítulo o figura se quiera regenerar.

**Regla de buena práctica:** si un resultado entra al PDF o a la web, debe poder asociarse a un script y, cuando aplique, a parámetros fijados en el propio script o en la tesina.
