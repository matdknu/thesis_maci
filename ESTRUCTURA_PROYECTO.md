# 📁 Estructura del Proyecto - Resumen Visual

## 🎯 Organización por Tipo de Datos

### ✅ DATOS REALES (Usar para análisis final)
- **Scripts**: `scripts/analysis/real/`
- **Outputs**: `outputs/real/`
- **Datos**: `data/raw/`, `data/processed/`

### ⚠️ DATOS SIMULADOS (Solo para desarrollo/pruebas)
- **Scripts**: `scripts/simulation/`
- **Outputs**: `outputs/simulation/`
- **Datos**: `data/simulation/`

---

## 📂 Estructura Detallada

```
thesis_final/
│
├── 📄 README.md                          # Documentación principal
├── 📄 ESTRUCTURA_PROYECTO.md             # Este archivo
├── 📄 requirements.txt                   # Dependencias Python
│
├── 📁 data/
│   ├── raw/                              # ✅ DATOS REALES - Crudos
│   │   ├── reddit_comentarios_derecha.csv
│   │   └── reddit_posts_derecha.csv
│   ├── processed/                        # ✅ DATOS REALES - Procesados
│   └── trends/                           # Tendencias
│
├── 📁 scripts/
│   │
│   ├── ⚠️ simulation/                    # SCRIPTS SIMULADOS
│   │   ├── simulate_pipeline.py
│   │   ├── simulate_pipeline_v2.py
│   │   ├── simulated_analysis_realistic.py
│   │   └── generate_realistic_outputs.py
│   │
│   ├── ✅ analysis/
│   │   ├── real/                         # SCRIPTS DATOS REALES
│   │   │   └── real_data_plots.py
│   │   │
│   │   └── api/                          # SCRIPTS DE APIs
│   │       ├── deepseek_api.py          # 🆕 DeepSeek API
│   │       ├── 04_test_api.py
│   │       ├── 05_aplicacion_api.py
│   │       └── README_API.md
│   │
│   ├── 📊 network/                       # Scripts de redes
│   │   ├── analyze_reddit_thread.py
│   │   ├── analyze_thread_polarization.py
│   │   └── analyze_thread_short.py
│   │
│   └── 🔍 scraping/                      # Scripts de scraping
│       └── ...
│
├── 📁 outputs/
│   │
│   ├── ⚠️ simulation/                    # OUTPUTS SIMULADOS
│   │   ├── edgelist.csv
│   │   ├── graph.gexf
│   │   ├── reply_network.gexf
│   │   └── simulacion_redes_polarizacion/
│   │
│   ├── ✅ real/                          # OUTPUTS REALES
│   │   ├── figures/                      # Figuras con datos reales
│   │   ├── tables/                       # Tablas con datos reales
│   │   └── analisis_api/                 # Resultados de APIs
│   │
│   └── report/                           # Reportes compilados
│
├── 📁 documents/                         # DOCUMENTOS PRINCIPALES
│   ├── reporte_auto.qmd                  # ⭐ Documento principal
│   ├── reporte_auto.pdf
│   ├── reporte_auto.docx
│   └── sample/                           # Template Cambridge
│       └── reporte_cambridge.qmd
│
├── 📁 archive/                           # Archivos antiguos/duplicados
├── 📁 bibliografia/                      # Referencias
└── 📁 informes/                          # Informes intermedios
```

---

## 🚀 Scripts Principales por Categoría

### 📊 Análisis de Datos Reales
| Script | Ubicación | Descripción |
|--------|-----------|-------------|
| `real_data_plots.py` | `scripts/analysis/real/` | Genera gráficos con datos reales |

### ⚠️ Simulación (Desarrollo)
| Script | Ubicación | Descripción |
|--------|-----------|-------------|
| `simulate_pipeline.py` | `scripts/simulation/` | Pipeline de simulación |
| `simulate_pipeline_v2.py` | `scripts/simulation/` | Versión mejorada |
| `simulated_analysis_realistic.py` | `scripts/simulation/` | Análisis realista |
| `generate_realistic_outputs.py` | `scripts/simulation/` | Genera outputs simulados |

### 🌐 Análisis de Redes
| Script | Ubicación | Descripción |
|--------|-----------|-------------|
| `analyze_reddit_thread.py` | `scripts/network/` | Red usuario-reply básica |
| `analyze_thread_polarization.py` | `scripts/network/` | Análisis de polarización |
| `analyze_thread_short.py` | `scripts/network/` | Visualización con etiquetas cortas |

### 🤖 APIs
| Script | Ubicación | Descripción |
|--------|-----------|-------------|
| `deepseek_api.py` | `scripts/analysis/api/` | 🆕 Análisis con DeepSeek |
| `04_test_api.py` | `scripts/analysis/api/` | Prueba de APIs |
| `05_aplicacion_api.py` | `scripts/analysis/api/` | Aplicación de APIs |

---

## 🔑 Convenciones de Nomenclatura

### Prefijos para Identificar Tipo
- ✅ **Datos reales**: Archivos en `data/raw/`, `data/processed/`, `outputs/real/`
- ⚠️ **Datos simulados**: Archivos en `outputs/simulation/`, scripts en `scripts/simulation/`

### Nombres de Archivos
- Scripts de simulación: `simulate_*`, `simulated_*`
- Scripts de datos reales: `real_*`, o sin prefijo especial
- Scripts de red: `analyze_*`, `*_network`
- Scripts de API: `*_api.py`

---

## 📝 Notas Importantes

1. **⚠️ Siempre verifica la fuente**: Antes de usar cualquier output, verifica si es simulado o real
2. **✅ Usa datos reales para análisis final**: Los datos simulados son solo para desarrollo
3. **📊 Outputs organizados**: Los outputs están claramente separados por tipo
4. **🔧 Scripts organizados**: Cada tipo de script tiene su carpeta correspondiente

---

## 🆕 Nuevo: DeepSeek API

Para usar el nuevo script de DeepSeek:

```bash
# 1. Configurar API key
export DEEPSEEK_API_KEY="tu_api_key"

# 2. Ejecutar
python scripts/analysis/api/deepseek_api.py

# 3. Resultados en:
# data/processed/analisis_discurso_deepseek/
```

Ver `scripts/analysis/api/README_API.md` para más detalles.

---

**Última actualización**: 2025-01-19
