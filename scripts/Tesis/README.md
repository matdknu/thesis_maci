# Scripts de Tesis

Esta carpeta contiene **únicamente** los scripts relacionados con scraping y procesamiento de datos reales para la tesis.

**Incluye:**
- Scripts de scraping (en `scraping_outputs/`)
- Scripts de procesamiento de datos scraped
- Todo lo que ha emanado del scraping (análisis, visualizaciones, modelado, etc.)
- **NO incluye:** scripts de test, simulaciones (ABM), o scripts auxiliares (están en `../no_sirve/`)

## 📋 Orden de Ejecución

Los scripts están numerados en orden lógico de ejecución:

### 01-02: Preparación de Datos
- **`01_filtrar_data.R`**: Filtrado y preparación de datos crudos
- **`02_merge_raw_data.py`**: Merge de datos de diferentes fuentes

### 03-04: Análisis Descriptivo y Visualizaciones
- **`03_descriptivos_tesis.R`**: Análisis descriptivo para la tesis
- **`04_visualizaciones_tesis.R`**: Visualizaciones académicas (APA style)

### 05: Análisis Textual
- **`05_analisis_textual_posts.R`**: Análisis textual de posts

### 06-09: Análisis con APIs
- **`06_apis.R`**: Análisis con APIs (OpenAI, Gemini)
- **`08_aplicacion_api.py`**: Aplicación de APIs para análisis (procesa datos scraped)
- **`09_deepseek_api.py`**: Análisis con DeepSeek API (procesa datos scraped)

**Nota:** Scripts de test (07_test_*.py) movidos a `../no_sirve/`

### 10-14: Modelado y Machine Learning
- **`10_modelado.R`**: Modelado estadístico
- **`11_analisis_ideologia.R`**: Análisis de ideología
- **`12_ml_text_analysis.R`**: Machine Learning para análisis textual
- **`13_ml_ideologia.R`**: Machine Learning para ideología
- **`14_rnn_classifier.py`**: Clasificador RNN

### 15-18: Evaluación y Análisis Complementarios
- **`15_evaluacion_modelos.R`**: Evaluación de modelos
- **`16_real_data_plots.py`**: Gráficos con datos reales
- **`17_imputar_ideologia.R`**: Imputación de ideología
- **`18_dea.R`**: Análisis exploratorio de datos (DEA)

---

## 📊 Outputs

Los outputs generados por estos scripts se guardan en:
- `outputs/Tesis/real/` - Resultados con datos reales
- `outputs/Tesis/thesis_figures/` - Figuras para la tesis
- `outputs/Tesis/tables/` - Tablas para la tesis
- `outputs/Tesis/reports/` - Reportes compilados
- `outputs/Tesis/abm/` - Resultados del modelo basado en agentes (simulación)

---

## 🔧 Requisitos

### R Scripts
- Requieren R con el paquete `pacman`
- Los paquetes se instalan automáticamente via `pacman::p_load()`
- Paquete `jtools` para temas APA: `install.packages("jtools")`

### Python Scripts
- Requieren Python 3.x
- Instalar dependencias: `pip install -r requirements.txt`
- Para scripts de API, configurar API keys como variables de entorno

---

## 📝 Notas

- **Todos estos scripts se utilizan para la tesis final**
- Los outputs de estos scripts se usan en `documents/reporte_auto.qmd`
- Mantener este orden de ejecución para reproducibilidad
- Si se modifica algún script, actualizar esta documentación

---

## 🚀 Ejecución Rápida

```bash
# Ejecutar pipeline completo (R scripts)
cd scripts/Tesis
for script in *.R; do Rscript "$script"; done

# Ejecutar scripts Python individualmente
python 02_merge_raw_data.py
python 07_test_api.py
python 08_aplicacion_api.py
python 09_deepseek_api.py
python 14_rnn_classifier.py
python 16_real_data_plots.py
```

---

## 📁 Scripts de Scraping

Los scripts originales de scraping están en:
- `scraping_outputs/` - Scripts de scraping de Reddit y trends

**Nota:** El scraping ya está completado. Estos scripts son para referencia histórica.

---

## 📚 Documentación Adicional

- **`ORDEN_EJECUCION.md`**: Guía detallada de ejecución del pipeline completo

---

## ⚠️ Scripts Movidos

Los siguientes scripts **NO** están en esta carpeta (movidos a `../no_sirve/`):
- Scripts de test (07_test_*.py)
- Modelo basado en agentes (19_abm_simulacion.R, ABM_PARAMETROS.md)
- Utilidades temporales (fix_interactive.py)

---

**Última actualización**: 2025-01-19
