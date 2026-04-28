# Scraping sondeos Wikipedia 2025

Este script descarga y procesa tablas de:

- Primera vuelta
- Segunda vuelta

desde la pagina:

- https://es.wikipedia.org/wiki/Anexo:Sondeos_de_intenci%C3%B3n_de_voto_para_la_elecci%C3%B3n_presidencial_de_Chile_de_2025

## Uso

Desde la raiz del proyecto:

```bash
python scripts/scrapping/sondeos_wikipedia_2025/scrap_sondeos_wikipedia_2025.py
```

Para generar graficos de tendencia con `ggplot2`:

```bash
Rscript scripts/scrapping/sondeos_wikipedia_2025/graficos_tendencia_sondeos.R
```

## Salidas

Se crean en `data/raw/sondeos_wikipedia_2025/`:

- `tablas_raw/*.csv`: cada tabla individual extraida.
- `consolidado/primera_vuelta.csv`
- `consolidado/segunda_vuelta.csv`
- `consolidado/*.parquet` (si el entorno tiene soporte parquet).
- `resumen_extraccion.json`

Y para graficos:

- `graficos/tendencia_primera_vuelta_ggplot2.png`
- `graficos/tendencia_segunda_vuelta_kast_jara_ggplot2.png`
