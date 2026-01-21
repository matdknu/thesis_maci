# Orden de Ejecución de Scripts de Tesis

## 📋 Pipeline Completo

### Fase 1: Preparación de Datos (01-02)
```bash
# 1. Filtrar y preparar datos crudos
Rscript 01_filtrar_data.R

# 2. Merge de datos de diferentes fuentes
python 02_merge_raw_data.py
```

**Outputs:**
- `data/processed/reddit_filtrado.rds`
- Datos combinados en `data/processed/`

---

### Fase 2: Análisis Descriptivo (03-04)
```bash
# 3. Análisis descriptivo para tesis
Rscript 03_descriptivos_tesis.R

# 4. Visualizaciones académicas
Rscript 04_visualizaciones_tesis.R
```

**Outputs:**
- `outputs/Tesis/thesis_figures/` - Figuras para tesis
- `outputs/Tesis/tables/` - Tablas descriptivas

---

### Fase 3: Análisis Textual (05)
```bash
# 5. Análisis textual de posts
Rscript 05_analisis_textual_posts.R
```

**Outputs:**
- `outputs/Tesis/tables/` - Tablas de análisis textual

---

### Fase 4: Análisis con APIs (06-09)
```bash
# 6. Análisis con APIs (configurar keys primero)
export OPENAI_API_KEY="tu_key"
export GEMINI_API_KEY="tu_key"
Rscript 06_apis.R

# 7. Probar APIs
python 07_test_api.py

# 8. Aplicar APIs para análisis
python 08_aplicacion_api.py

# 9. Análisis con DeepSeek (configurar key)
export DEEPSEEK_API_KEY="tu_key"
python 09_deepseek_api.py
```

**Outputs:**
- `outputs/Tesis/real/analisis_api/` - Resultados de análisis con APIs
- `data/processed/analisis_discurso/` - Datos procesados con APIs

---

### Fase 5: Modelado y ML (10-14)
```bash
# 10. Modelado estadístico
Rscript 10_modelado.R

# 11. Análisis de ideología
Rscript 11_analisis_ideologia.R

# 12. ML para análisis textual
Rscript 12_ml_text_analysis.R

# 13. ML para ideología
Rscript 13_ml_ideologia.R

# 14. Clasificador RNN
python 14_rnn_classifier.py
```

**Outputs:**
- `outputs/Tesis/tables/` - Tablas de resultados de modelos
- `outputs/Tesis/thesis_figures/` - Figuras de modelos

---

### Fase 6: Evaluación y Análisis Complementarios (15-18)
```bash
# 15. Evaluación de modelos
Rscript 15_evaluacion_modelos.R

# 16. Gráficos con datos reales
python 16_real_data_plots.py

# 17. Imputación de ideología
Rscript 17_imputar_ideologia.R

# 18. Análisis exploratorio (DEA)
Rscript 18_dea.R
```

**Outputs:**
- `outputs/Tesis/tables/` - Tablas de evaluación
- `outputs/Tesis/real/` - Gráficos finales

---

## 🚀 Ejecución Rápida (Todo el Pipeline)

### Script R para ejecutar todo:
```r
# ejecutar_todo.R
scripts <- c(
  "01_filtrar_data.R",
  "03_descriptivos_tesis.R",
  "04_visualizaciones_tesis.R",
  "05_analisis_textual_posts.R",
  "06_apis.R",
  "10_modelado.R",
  "11_analisis_ideologia.R",
  "12_ml_text_analysis.R",
  "13_ml_ideologia.R",
  "15_evaluacion_modelos.R",
  "17_imputar_ideologia.R",
  "18_dea.R"
)

for (script in scripts) {
  cat("\n=== Ejecutando:", script, "===\n")
  source(script)
}
```

### Script Bash para Python:
```bash
#!/bin/bash
# ejecutar_python.sh

python 02_merge_raw_data.py
python 07_test_api.py
python 08_aplicacion_api.py
python 09_deepseek_api.py
python 14_rnn_classifier.py
python 16_real_data_plots.py
```

---

## ⚠️ Notas Importantes

1. **Dependencias**: Los scripts deben ejecutarse en orden, ya que cada uno depende de los outputs de los anteriores

2. **API Keys**: Los scripts 06-09 requieren API keys configuradas como variables de entorno

3. **Tiempo**: El pipeline completo puede tardar varias horas, especialmente los scripts de API

4. **Datos**: Asegúrate de tener los datos en `data/raw/` antes de ejecutar el pipeline

5. **Outputs**: Todos los outputs se guardan en `outputs/Tesis/` para mantener organización

---

**Última actualización**: 2025-01-19
