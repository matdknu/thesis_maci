# Procesamiento de Datos del SERVEL

Este documento explica cómo procesar los datos del SERVEL para usar en la app Shiny.

## Pasos

### 1. Colocar archivos CSV en `data/servel/`

Los archivos deben tener una de estas estructuras:

**Formato Wide (recomendado):**
```csv
region,Evelyn Matthei,José Antonio Kast,Jeannette Jara
Metropolitana,62,79,95
Valparaíso,60,79,95
```

**Formato Long:**
```csv
region,candidato,porcentaje
Metropolitana,Kast,79.5
Metropolitana,Jara,95.2
```

### 2. Ejecutar el script de procesamiento

```r
source("shiny_app/procesar_datos_servel.R")
```

### 3. Verificar que se crearon los archivos procesados

El script creará archivos en `data/processed/servel/`:
- `servel_regional.rds` - Datos a nivel regional
- `servel_comunal.rds` - Datos a nivel comunal (si existen)
- `servel_consolidado.csv` - CSV con todos los datos (para inspección)

### 4. Recargar la app Shiny

Los datos procesados se cargarán automáticamente cuando ejecutes la app.

## Notas

- El script detecta automáticamente el formato (wide o long)
- Normaliza los nombres de candidatos automáticamente
- Separa datos regionales y comunales si ambos están presentes
- Los archivos RDS son más rápidos de cargar que CSV











