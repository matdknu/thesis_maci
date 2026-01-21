# 🗳️ Derecha fragmentada y un enemigo compartido

**Análisis textual longitudinal de la contestación discursiva en las elecciones presidenciales de 2025 en Chile**

[![Universidad de Concepción](https://img.shields.io/badge/Universidad-Concepción-blue)](https://www.udec.cl/)
[![Magíster en Ciencia de Datos](https://img.shields.io/badge/Magíster-Ciencia%20de%20Datos-green)](https://www.udec.cl/)
[![Python](https://img.shields.io/badge/Python-3.9+-blue?logo=python)](https://www.python.org/)
[![R](https://img.shields.io/badge/R-4.0+-276DC3?logo=r)](https://www.r-project.org/)

---

## 👤 Autor

**Matías Deneken**  
Centro de Datos e Inteligencia Artificial  
Universidad de Concepción

**Profesores Guías:**  
Dr. Carlos Navarrete | Dr. Marcela Parada

**Fecha:** Marzo 2026

---

## 📖 Descripción

Este proyecto analiza la fragmentación de la derecha chilena y la construcción de un adversario compartido durante la campaña presidencial de 2025, utilizando técnicas computacionales de análisis de texto y redes sociales.

El análisis examina discusiones políticas en Reddit (`r/chile` y `r/RepublicadeChile`), estudiando cómo diferentes sectores de la derecha construyen identidades políticas fragmentadas mientras convergen en torno a adversarios comunes.

### 🎯 Objetivos

- Analizar patrones de fragmentación discursiva en la derecha chilena
- Identificar construcción de adversarios compartidos en el discurso político
- Aplicar técnicas de NLP y machine learning para clasificación ideológica
- Desarrollar visualizaciones interactivas de datos políticos

---

## 📁 Estructura del Proyecto

```
📦 thesis_final
├── 📚 documents/tesis_book/       # Libro de tesis (Quarto)
│   ├── index.qmd                  # Portada y preliminares
│   ├── 01-introduccion.qmd
│   ├── 02-presentacion-problema.qmd
│   ├── 03-obtencion-datos.qmd
│   ├── 04-depuracion-datos.qmd
│   ├── 05-exploracion-datos.qmd
│   ├── 06-modelado-datos.qmd
│   ├── 07-interpretacion-resultados.qmd
│   ├── 08-conclusion.qmd
│   └── references.qmd
│
├── 🔬 scripts/Tesis/              # Scripts de análisis
│   ├── 01_filtrar_data.R
│   ├── 02_merge_raw_data.py
│   ├── 03_descriptivos_tesis.R
│   ├── 04_visualizaciones_tesis.R
│   ├── 05_analisis_textual_posts.R
│   ├── 10_modelado.R
│   ├── 12_ml_text_analysis.R
│   ├── ORDEN_EJECUCION.md
│   └── scraping_outputs/          # Scripts de web scraping
│
├── 📊 shiny_app/                  # Aplicación interactiva
│   ├── app.R                      # Dashboard Shiny
│   ├── README.md
│   └── www/                       # Assets (imágenes, CSS)
│
├── 📄 informes/                   # Informes intermedios
├── 📚 bibliografia/               # Referencias bibliográficas
└── 📋 requirements.txt            # Dependencias Python

```

> **⚠️ Nota sobre datos:** La carpeta `data/` no está incluida en este repositorio por razones de privacidad. Los datos fueron recopilados de Reddit siguiendo las políticas de la plataforma.

---

## 📖 Ver Libro de Tesis Online

**🌐 Lee el libro completo en:** **[https://matdknu.github.io/thesis_maci/](https://matdknu.github.io/thesis_maci/)**

El libro está publicado en GitHub Pages y se actualiza automáticamente con cada cambio en el repositorio.

---

## 🚀 Inicio Rápido

### 📋 Requisitos Previos

- **Python** 3.9 o superior
- **R** 4.0 o superior  
- **Quarto** 1.3+ (para compilar la tesis)
- **LaTeX** (recomendado: [TinyTeX](https://yihui.org/tinytex/))

### 💾 Instalación

```bash
# Clonar el repositorio
git clone https://github.com/matdknu/thesis_maci.git
cd thesis_maci

# Crear entorno virtual de Python
python -m venv .venv
source .venv/bin/activate  # En Windows: .venv\Scripts\activate

# Instalar dependencias
pip install -r requirements.txt
```

### 📚 Compilar el Libro de Tesis

```bash
cd documents/tesis_book

# Compilar a PDF
quarto render --to pdf

# Compilar a HTML
quarto render --to html
```

El output se generará en `documents/tesis_book/_book/`.

### 🌐 Ejecutar la Aplicación Shiny

```r
# En R o RStudio
library(shiny)
runApp("shiny_app")
```

> **Nota:** La aplicación requiere datos procesados. Consulta `shiny_app/README.md` para más detalles.

---

## 🛠️ Metodología

El análisis combina múltiples enfoques:

| Técnica | Herramientas | Propósito |
|---------|-------------|-----------|
| 🕷️ **Web Scraping** | PRAW, Python | Recopilación de datos de Reddit |
| 📝 **NLP** | spaCy, tidytext | Análisis de sentimientos y entidades |
| 🤖 **Machine Learning** | scikit-learn, caret | Clasificación ideológica |
| 📊 **Visualización** | ggplot2, plotly | Dashboards interactivos |
| 🕸️ **Análisis de Redes** | igraph, networkx | Redes de interacción |

---

## 📊 Aplicación Shiny Interactiva

La aplicación incluye:

- ✅ **Dashboard General** - Resumen de estadísticas clave
- 👥 **Análisis por Candidato** - Visualizaciones individuales
- 📅 **Línea de Tiempo** - Eventos y picos de menciones
- 💭 **Frames Discursivos** - Análisis de narrativas
- ⚖️ **Clasificación Ideológica** - Distribución left-right

**Demo:** La aplicación está desplegada en [shinyapps.io](https://matdknu.shinyapps.io/reddit-politico-chile/)

---

## 📂 Datos

### Fuentes

- **Reddit:** Subreddits `r/chile` y `r/RepublicadeChile`
- **Período:** Campaña presidencial 2025
- **Servel:** Datos electorales oficiales (público)

### Estructura de Datos

```
data/
├── raw/                           # Datos crudos (no versionados)
│   ├── reddit_posts*.parquet
│   └── reddit_comentarios*.parquet
├── processed/                     # Datos procesados
│   └── master_reddit.csv
└── trends/                        # Análisis de tendencias
    └── series/
```

> **🔒 Privacidad:** Los datos no están incluidos en el repositorio. Investigadores interesados pueden contactar al autor.

---

## 📖 Citación

Si utilizas este trabajo en tu investigación, por favor cita:

```bibtex
@mastersthesis{deneken2026derecha,
  title   = {Derecha fragmentada y un enemigo compartido: Análisis textual longitudinal 
             de la contestación discursiva en las elecciones presidenciales de 2025 en Chile},
  author  = {Deneken, Matías},
  year    = {2026},
  school  = {Universidad de Concepción},
  type    = {Tesina de Magíster en Ciencia de Datos}
}
```

---

## 📜 Licencia

Este proyecto es de **uso académico**. Los datos de Reddit están sujetos a las políticas de la plataforma y se utilizan exclusivamente con fines de investigación.

---

## 📞 Contacto

**Matías Deneken**  
📧 Email: [contacto@ejemplo.cl](mailto:contacto@ejemplo.cl)  
🔗 GitHub: [@matdknu](https://github.com/matdknu)  
🏛️ Centro de Datos e Inteligencia Artificial - Universidad de Concepción

---

<div align="center">

**Universidad de Concepción**  
Facultad de Ingeniería  
Centro de Datos e Inteligencia Artificial

🇨🇱 **2026**

</div>
