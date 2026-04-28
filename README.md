# 🗳️ Derecha fragmentada y un enemigo compartido

**Análisis textual longitudinal de la contestación discursiva en las elecciones presidenciales de 2025 en Chile**

[![DOI](https://img.shields.io/badge/DOI-10.17605%2FOSF.IO%2FNQB3G-blue)](https://doi.org/10.17605/OSF.IO/NQB3G)
[![OSF](https://img.shields.io/badge/OSF-Project-green)](https://osf.io/nqb3g/)
[![GitHub Pages](https://img.shields.io/badge/GitHub-Pages-orange)](https://matdknu.github.io/thesis_maci/)
[![Shiny App](https://img.shields.io/badge/Shiny-App%20Live-brightgreen?logo=r)](https://matdknu.shinyapps.io/reddit-politico-chile/)
[![Universidad de Concepción](https://img.shields.io/badge/Universidad-Concepción-blue)](https://www.udec.cl/)
[![Magíster en Ciencia de Datos](https://img.shields.io/badge/Magíster-Ciencia%20de%20Datos-green)](https://www.udec.cl/)
[![Python](https://img.shields.io/badge/Python-3.9+-blue?logo=python)](https://www.python.org/)
[![R](https://img.shields.io/badge/R-4.0+-276DC3?logo=r)](https://www.r-project.org/)

---

## 👤 Autor

**Matías Javier Deneken Uribe**  
Centro de Datos e Inteligencia Artificial  
Universidad de Concepción

**Profesores Guías:**  
Dr. Carlos Navarrete | Dr. Marcela Parada

**Fecha:** Abril 2026

---

## Repositorio público: alcance en GitHub vs. OSF

Este repositorio está pensado para **versionar solo lo necesario para leer y reconstruir el libro**: texto Quarto/BibTeX, figuras que cita la tesis, scripts del flujo principal y datos tabulares mínimos auxiliares. **No forma parte del objetivo** subir el corpus Reddit completo, claves API, borradores de revisión, ni duplicados de salidas grandes que pudieran **sustituir** resultados reproducibles desde código sin auditoría (`data/raw/`, parquet/CVS voluminosos, etc.) — esos materiales están documentados o concentrados en el **OSF** (véase DOI enlazado abajo).

- **GitHub (este repo):** estructura de scripts, libro (fuente + `docs/` para GitHub Pages), tablas parametrizadas en Excel cuando aplican (`documents/tesis_book/data/tablas_tesis.xlsx`), figuras bajo `documents/tesis_book/fig_thesis/`.
- **OSF / proyecto ampliado:** datos y materiales voluminosos, copia de respaldo abierta conforme a la práctica habitual de la disciplina.

---

Este proyecto analiza la fragmentación de la derecha chilena y la construcción de un adversario compartido durante la campaña presidencial de 2025, utilizando técnicas computacionales de análisis de texto y redes sociales.

El análisis examina discusiones políticas en Reddit (`r/chile` y `r/RepublicadeChile`), estudiando cómo diferentes sectores de la derecha construyen identidades políticas fragmentadas mientras convergen en torno a adversarios comunes.

### 🎯 Objetivos

- Analizar patrones de fragmentación discursiva en la derecha chilena
- Identificar construcción de adversarios compartidos en el discurso político
- Aplicar técnicas de NLP y machine learning para clasificación ideológica
- Desarrollar visualizaciones interactivas de datos políticos

---

## 📁 Estructura del proyecto (rama medular)

```
thesis_maci/
├── bibliografia/
│   └── bittex.bib                 # BibTeX (la tesina enlaza con rutas relativas)
├── docs/                           # Sitio compilado para GitHub Pages (`quarto render` desde documents/tesis_book)
├── documents/
│   ├── presentacion_proyecto/      # Presentación (Reveal): presentation.qmd
│   └── tesis_book/                 # Libro Quarto (.qmd cap. 01–11, annexos, references)
│       ├── _quarto.yml
│       ├── fig_thesis/             # Figuras/CSV ligados como activos del PDF/HTML
│       ├── includes/               # p. ej. helper de tablas APA
│       └── data/tablas_tesis.xlsx # Tablas parametrizadas (no el corpus Reddit)
├── scripts/
│   ├── README.md                   # Índice: scrapping → análisis
│   ├── analisis/
│   └── scrapping/
├── shiny_app/                     # Dashboard opcional (datos grandes no van al repo público)
└── README.md                      # Este archivo
```

**Qué no se espera aquí:** datos crudos/extensos (`.csv`/`.parquet` bajo rutas definidas por `.gitignore`), claves o tokens (`claves_*`, `.env`), borradores de revisión externa (`revision/`), renders sueltos en la raíz (`Rplots.pdf`). El **OSF** agrupa corpus, respaldos y materiales voluminosos; aquí sólo debe quedar lo que permite auditoría reproducible desde scripts + texto.

> El libro se compila desde `documents/tesis_book/`; la salida publicada suele estar en **`docs/`** (según `_quarto.yml`).

---

## 🖥 Presentación oral (diapositivas)

Esta sección corresponde **solo a la presentación** (defensa/exposición en Reveal).

- Fuente: [`documents/presentacion_proyecto/presentation.qmd`](documents/presentacion_proyecto/presentation.qmd)
- Render: dentro de esa carpeta, `quarto render presentation.qmd` → `presentation.html`.

---

## 📖 Acceder a la Tesis

### 🌐 Libro Online (GitHub Pages)
**📚 Lee el libro completo:** **[https://matdknu.github.io/thesis_maci/](https://matdknu.github.io/thesis_maci/)**

### 📊 Aplicación Interactiva (Shiny)
**🚀 Explora los datos en vivo:** **[https://matdknu.shinyapps.io/reddit-politico-chile/](https://matdknu.shinyapps.io/reddit-politico-chile/)**

Dashboard interactivo con visualizaciones, análisis temporal, frames discursivos y clasificación ideológica.

### 📚 Repositorio OSF
**DOI:** [![DOI](https://img.shields.io/badge/DOI-10.17605%2FOSF.IO%2FNQB3G-blue)](https://doi.org/10.17605/OSF.IO/NQB3G)

**Proyecto completo disponible en OSF:** **[https://osf.io/nqb3g/](https://osf.io/nqb3g/)**

El proyecto en OSF incluye datos, código, documentación completa y materiales suplementarios.

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

El output del libro Quarto está configurado en **`../../docs`** (véase `documents/tesis_book/_quarto.yml`, `project.output-dir`): GitHub Pages apunta habitualmente ahí tras `quarto render`.

**GitHub Pages:** hay que **versionar `docs/site_libs/` por completo** (Bootstrap, `quarto-html`, `quarto-nav`, `quarto-search`, clipboard, etc.). Si en el remoto faltan esas carpetas, el sitio carga el HTML **sin CSS/JS** y se ve “roto”; el `index.html` enlaza a `site_libs/bootstrap/...` y similares — confirma con `git add docs/site_libs/` antes del push.

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

### 🌐 Ver App en Vivo
**Aplicación desplegada:** **[https://matdknu.shinyapps.io/reddit-politico-chile/](https://matdknu.shinyapps.io/reddit-politico-chile/)**

La aplicación interactiva incluye:

- ✅ **Dashboard General** - Resumen de estadísticas clave y evolución temporal
- 👥 **Análisis por Candidato** - Visualizaciones detalladas por personaje político
- 📅 **Eventos Temporales** - Identificación de picos y eventos relevantes
- 💭 **Frames Discursivos** - Análisis de marcos y narrativas
- ⚖️ **Análisis Ideológico** - Distribución left-right mediante IA
- 🗺️ **Resultados Electorales** - Visualización geográfica de datos SERVEL
- 📊 **Explorador de Datos** - Tabla interactiva con búsqueda y filtros

**Datos:** Reddit (r/chile, r/RepublicadeChile) | **Período:** Agosto - Diciembre 2025

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
  author  = {Deneken Uribe, Mat{\'{\i}}as Javier},
  year    = {2026},
  school  = {Universidad de Concepción},
  type    = {Tesina de Magíster en Ciencia de Datos},
  doi     = {10.17605/OSF.IO/NQB3G},
  url     = {https://osf.io/nqb3g/}
}
```

**DOI:** [10.17605/OSF.IO/NQB3G](https://doi.org/10.17605/OSF.IO/NQB3G)

---

## 📜 Licencia

Este proyecto es de **uso académico**. Los datos de Reddit están sujetos a las políticas de la plataforma y se utilizan exclusivamente con fines de investigación.

---

## 📞 Contacto

**Matías Javier Deneken Uribe**  
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
