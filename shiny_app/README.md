# Shiny App - Análisis Interactivo de Reddit Político

Aplicación Shiny interactiva para visualizar y analizar datos políticos de Reddit.

## Características

- 📊 **Dashboard General**: Resumen de estadísticas y visualizaciones principales
- 👥 **Personajes**: Análisis individual por personaje político (Kast, Kaiser, Matthei, Jara, etc.)
- 📅 **Eventos**: Visualización de eventos y picos de menciones en el tiempo
- 🏷️ **Frames**: Análisis de frames discursivos (pendiente de implementación completa)
- ⚖️ **Ideología**: Visualización de resultados de imputación de ideología left-right
- 💾 **Datos**: Tabla interactiva de datos crudos

## Instalación

### 1. Instalar dependencias de R

```r
source("shiny_app/requirements.R")
```

O instalar manualmente:

```r
install.packages(c("shiny", "shinydashboard", "shinyWidgets", 
                   "tidyverse", "lubridate", "plotly", "DT", "here"))
```

### 2. Agregar imágenes de personajes

Coloca las imágenes de los personajes en `shiny_app/www/images/` con estos nombres:

- `kast.png` - José Antonio Kast
- `kaiser.png` - Johannes Kaiser
- `matthei.png` - Evelyn Matthei
- `jara.png` - Jeannette Jara
- `parisi.png` - Franco Parisi
- `sichel.png` - Sebastián Sichel

**Nota:** Por defecto se incluyen imágenes placeholder que puedes reemplazar con fotos reales.

### 3. Verificar datos

La app requiere:
- `data/processed/reddit_filtrado.rds` (requerido)
- `data/processed/imputacion_ideologia/[fecha]/imputacion_ideologia_*.csv` (opcional, para análisis de ideología)

## Ejecución

Desde el directorio raíz del proyecto:

```r
library(shiny)
runApp("shiny_app")
```

O desde RStudio:
1. Abrir `shiny_app/app.R`
2. Clic en "Run App"

## Estructura

```
shiny_app/
├── app.R                    # Aplicación principal
├── requirements.R           # Dependencias
├── README.md               # Este archivo
└── www/
    └── images/             # Imágenes de personajes
        ├── kast.png
        ├── kaiser.png
        ├── matthei.png
        ├── jara.png
        ├── parisi.png
        └── sichel.png
```

## Pestañas de la App

### 1. Dashboard
- Resumen de estadísticas (total comentarios, menciones, período, usuarios)
- Evolución temporal de menciones
- Distribución de menciones por candidato
- Top 10 usuarios más activos

### 2. Personajes
- Card con información y foto del personaje
- Evolución temporal de menciones
- Menciones por día de la semana
- Menciones por hora del día

### 3. Eventos
- Gráfico interactivo de eventos en el tiempo
- Filtros por rango de fechas y candidatos
- Tabla de eventos destacados

### 4. Frames
- Análisis de frames discursivos (pendiente de implementación completa)
- Frames por candidato
- Evolución de frames

### 5. Ideología
- Distribución de labels de ideología (si hay datos)
- Distribución de scores left-right
- Requiere ejecutar `scripts/analisis/03_aplicacion_api.py` primero

### 6. Datos
- Tabla interactiva con todos los datos
- Filtros y búsqueda
- Exportación a CSV

## Personalización

### Colores de personajes

Edita en `app.R` la sección `personajes_info`:

```r
personajes_info <- tibble(
  nombre = c("Kast", "Kaiser", ...),
  color = c("#1f77b4", "#ff7f0e", ...)  # Colores hexadecimales
)
```

### Estilos CSS

Los estilos están en la sección `tags$head(tags$style(...))` del UI. Modifica ahí para cambiar colores, tamaños, etc.

## Notas

- Las imágenes se cargan desde `www/images/`. Si no existen, se usa un placeholder.
- La app busca automáticamente el directorio más reciente de imputación de ideología.
- Algunas visualizaciones pueden tardar unos segundos en cargar dependiendo del tamaño de los datos.

## Troubleshooting

**Error: "Datos de Reddit no disponibles"**
- Verifica que `data/processed/reddit_filtrado.rds` existe
- Ejecuta `01_filtrado.R` primero

**Error: "Datos de ideología no disponibles"**
- Normal si no has ejecutado `03_aplicacion_api.py`
- La pestaña de Ideología mostrará un mensaje informativo

**Las imágenes no aparecen**
- Verifica que los archivos están en `www/images/`
- Revisa que los nombres coinciden exactamente (kast.png, kaiser.png, etc.)
- La app usará placeholders si no encuentra las imágenes

**La app es lenta**
- Considera filtrar los datos en el script de carga
- Reducir el tamaño de las tablas (ej: head(1000))











