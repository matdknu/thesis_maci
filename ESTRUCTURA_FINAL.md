# Estructura Final del Proyecto

## 📁 Organización Completada

### ✅ Scripts de Tesis
**Ubicación:** `scripts/Tesis/`

Todos los scripts utilizados para la tesis están numerados en orden lógico de ejecución:

1. `01_filtrar_data.R` - Filtrado y preparación de datos
2. `02_merge_raw_data.py` - Merge de datos
3. `03_descriptivos_tesis.R` - Análisis descriptivo
4. `04_visualizaciones_tesis.R` - Visualizaciones
5. `05_analisis_textual_posts.R` - Análisis textual
6. `06_apis.R` - Análisis con APIs
7. `07_test_api.py` - Prueba de APIs
8. `08_aplicacion_api.py` - Aplicación de APIs
9. `09_deepseek_api.py` - DeepSeek API
10. `10_modelado.R` - Modelado estadístico
11. `11_analisis_ideologia.R` - Análisis de ideología
12. `12_ml_text_analysis.R` - ML análisis textual
13. `13_ml_ideologia.R` - ML ideología
14. `14_rnn_classifier.py` - Clasificador RNN
15. `15_evaluacion_modelos.R` - Evaluación de modelos
16. `16_real_data_plots.py` - Gráficos reales
17. `17_imputar_ideologia.R` - Imputación de ideología
18. `18_dea.R` - Análisis exploratorio

**Documentación:**
- `scripts/Tesis/README.md` - Documentación general
- `scripts/Tesis/ORDEN_EJECUCION.md` - Guía de ejecución

---

### ⚠️ Scripts No Usados
**Ubicación:** `scripts/no_usar/`

Contiene todos los scripts que NO se utilizan en la tesis final:
- Scripts de simulación
- Scripts de ejemplo (redes, etc.)
- Scripts de scraping (ya completados)
- Scripts de desarrollo y pruebas

---

### ✅ Outputs de Tesis
**Ubicación:** `outputs/Tesis/`

Contiene todos los outputs generados por los scripts de tesis:
- `outputs/Tesis/real/` - Resultados con datos reales
- `outputs/Tesis/thesis_figures/` - Figuras para la tesis
- `outputs/Tesis/tables/` - Tablas para la tesis
- `outputs/Tesis/report/` - Reportes compilados

---

### ⚠️ Outputs No Usados
**Ubicación:** `outputs/no_usar/`

Contiene todos los outputs que NO se usan en la tesis:
- Outputs de simulación
- Outputs de desarrollo
- Outputs de prueba

---

## 🚀 Uso Rápido

### Ejecutar Scripts de Tesis
```bash
# Ver orden de ejecución
cat scripts/Tesis/ORDEN_EJECUCION.md

# Ejecutar todos los scripts R
cd scripts/Tesis
for script in *.R; do Rscript "$script"; done

# Ejecutar todos los scripts Python
cd scripts/Tesis
for script in *.py; do python "$script"; done
```

### Ver Documentación
```bash
# Documentación general
cat scripts/Tesis/README.md

# Orden de ejecución detallado
cat scripts/Tesis/ORDEN_EJECUCION.md
```

---

## 📝 Notas Importantes

1. **Solo scripts en `scripts/Tesis/` se usan para la tesis**
2. **Todos los scripts están numerados en orden lógico**
3. **Los outputs de tesis van a `outputs/Tesis/`**
4. **Todo lo demás está en `scripts/no_usar/` y `outputs/no_usar/`**

---

**Última actualización**: 2025-01-19
