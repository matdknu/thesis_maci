# Scripts de la Tesis

Workflow de ejecución en orden:

```
scrapping/ → procesamiento/ → analisis/
```

---

## 1. `scrapping/`
Recolección de datos desde Reddit y Google Trends.

| Script | Descripción |
|--------|-------------|
| `01_scrapping_reddit.py` | Scraping de r/chile (candidatos generales) |
| `02_scrapping_derecha.py` | Scraping de r/RepublicadeChile (Kast, Kaiser, Matthei) |
| `03_scrapping_trends.py` | Descarga de Google Trends para los candidatos |

**Output:** archivos CSV en `data/raw/`

---

## 2. `procesamiento/`
Limpieza y unificación de los datos crudos.

| Script | Descripción |
|--------|-------------|
| `01_filtrar_data.R` | Filtrado y normalización de comentarios/posts |
| `02_merge_raw_data.py` | Merge de archivos de reddit general + derecha |

**Output:** datasets limpios en `data/processed/`

---

## 3. `analisis/`
Análisis descriptivo, textual y modelado.

| Script | Descripción |
|--------|-------------|
| `01_limpieza.R` | Punto de entrada: ejecuta `procesamiento/01_filtrar_data.R` |
| `02_descriptivos.R` | Descriptivos + figuras (español, a color); `outputs/thesis_figures/` |
| `02_visualizaciones.R` | Alias: ejecuta `02_descriptivos.R` |
| `03_modelado_api.R` | Configuración de APIs (R) |
| `03_aplicacion_api.py` | Clasificación ideológica vía LLM (Python) |
| `03_deepseek_api.py` | Clasificación con DeepSeek API |
| `04_analisis_textual.R` | Análisis textual: diccionario temático, LDA/STM, sentimiento, etc. |
| `05_modelado.R` | Topic modeling (LDA/STM) |
| `06_analisis_ideologia.R` | Análisis de scores ideológicos |
| `07_ml_text_analysis.R` | ML supervisado sobre texto |
| `08_ml_ideologia.R` | ML para clasificación ideológica |
| `09_rnn_classifier.py` | Clasificador RNN (PyTorch) |
| `10_evaluacion_modelos.R` | Evaluación y comparación de modelos |
| `11_real_data_plots.py` | Visualizaciones con datos reales (Python) |
| `12_imputar_ideologia.R` | Imputación de ideología para usuarios sin clasificar |
| `13_dea.R` | Análisis de discurso (DEA) |

---

## `no_sirve/`
Scripts descartados, versiones antiguas y experimentos fallidos. No ejecutar.
