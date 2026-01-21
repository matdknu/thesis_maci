# Datos en Shiny App

## Estructura de Datos

Los datos están duplicados dentro de `shiny_app/data/` para que estén disponibles en producción (shinyapps.io):

```
shiny_app/
├── data/
│   ├── processed/
│   │   ├── reddit_filtrado.rds          # ✅ Datos principales (115 MB)
│   │   └── imputacion_ideologia/       # ✅ Datos de ideología (si existen)
│   └── servel/                          # ✅ Datos SERVEL (si existen)
└── app.R
```

## ¿Por qué duplicar los datos?

En **shinyapps.io**, la app solo tiene acceso a archivos dentro del directorio `shiny_app/`. Los datos fuera de este directorio no están disponibles en producción.

## Actualizar Datos

Antes de desplegar, ejecuta uno de estos scripts para copiar los datos más recientes:

### Opción 1: Script R
```r
source("shiny_app/copiar_datos.R")
```

### Opción 2: Script Bash
```bash
bash shiny_app/copiar_datos.sh
```

### Opción 3: Manual
```bash
mkdir -p shiny_app/data/processed
cp data/processed/reddit_filtrado.rds shiny_app/data/processed/
```

## Verificación

Para verificar que los datos están en su lugar:

```r
# Verificar que existe
file.exists("shiny_app/data/processed/reddit_filtrado.rds")

# Ver tamaño
file.info("shiny_app/data/processed/reddit_filtrado.rds")$size / (1024^2)  # MB
```

## Nota sobre Tamaño

- `reddit_filtrado.rds`: ~115 MB
- shinyapps.io tiene límites de tamaño según el plan
- Si el despliegue falla por tamaño, considera:
  - Filtrar los datos antes de copiar
  - Usar un plan de shinyapps.io con más espacio
  - Comprimir los datos

## Orden de Búsqueda de Datos

La app busca datos en este orden:

1. **`shiny_app/data/processed/`** ← PRIORIDAD (producción)
2. `data/processed/` (desarrollo local)
3. Rutas calculadas con `here()` (último recurso)

Esto asegura que funcione tanto en desarrollo como en producción.










