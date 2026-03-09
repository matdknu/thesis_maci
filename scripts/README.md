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
| `01_descriptivos.R` | Estadísticas descriptivas generales |
| `02_visualizaciones.R` | Gráficos para la tesis |
| `03_analisis_textual.R` | Análisis de texto (TF-IDF, n-gramas, etc.) |
| `04_apis.R` | Configuración de APIs (R) |
| `05_aplicacion_api.py` | Clasificación ideológica vía LLM (Python) |
| `06_deepseek_api.py` | Clasificación con DeepSeek API |
| `07_modelado.R` | Topic modeling (LDA/STM) |
| `08_analisis_ideologia.R` | Análisis de scores ideológicos |
| `09_ml_text_analysis.R` | ML supervisado sobre texto |
| `10_ml_ideologia.R` | ML para clasificación ideológica |
| `11_rnn_classifier.py` | Clasificador RNN (PyTorch) |
| `12_evaluacion_modelos.R` | Evaluación y comparación de modelos |
| `13_real_data_plots.py` | Visualizaciones con datos reales (Python) |
| `14_imputar_ideologia.R` | Imputación de ideología para usuarios sin clasificar |
| `15_dea.R` | Análisis de discurso (DEA) |

---

## `no_sirve/`
Scripts descartados, versiones antiguas y experimentos fallidos. No ejecutar.
