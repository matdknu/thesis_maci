# Solución de Errores en Shiny App

## Error: "An error has occurred" / "exit status 1"

### Problemas Comunes y Soluciones

#### 1. **Rutas con `here()` no funcionan en shinyapps.io**

**Problema:** `here()` puede fallar en producción.

**Solución:** Usar rutas relativas o función `get_data_path()` que creé en el código.

#### 2. **Datos no encontrados**

**Problema:** Los archivos `.rds` no están en el directorio correcto.

**Solución:** 
- Asegúrate de que `data/processed/reddit_filtrado.rds` existe
- En shinyapps.io, los datos deben estar en el directorio de la app o subdirectorios

#### 3. **Paquetes faltantes**

**Problema:** Algunos paquetes no están instalados en shinyapps.io.

**Solución:** 
```r
# Ejecuta esto antes de desplegar
install.packages(c("shiny", "shinydashboard", "shinyWidgets", 
                   "tidyverse", "lubridate", "plotly", "DT", 
                   "here", "leaflet"))
```

#### 4. **Variables no definidas**

**Problema:** Si los datos no cargan, variables como `menciones_fecha` no existen.

**Solución:** Ya corregido en el código - ahora hay validaciones.

### Checklist antes de desplegar

- [ ] Archivo `reddit_filtrado.rds` existe en `data/processed/`
- [ ] Todos los paquetes están instalados
- [ ] La app funciona localmente: `shiny::runApp("shiny_app")`
- [ ] No hay errores en la consola al cargar

### Verificar logs en shinyapps.io

1. Ve a https://www.shinyapps.io/admin/#/applications
2. Selecciona tu app
3. Click en "Logs"
4. Revisa los errores específicos

### Comandos útiles

```r
# Verificar que los datos existen
file.exists("data/processed/reddit_filtrado.rds")

# Probar carga de datos
df <- readRDS("data/processed/reddit_filtrado.rds")
nrow(df)

# Verificar paquetes
required <- c("shiny", "shinydashboard", "shinyWidgets", 
              "tidyverse", "lubridate", "plotly", "DT", 
              "here", "leaflet")
missing <- required[!sapply(required, requireNamespace, quietly = TRUE)]
if (length(missing) > 0) {
  cat("Faltan:", paste(missing, collapse = ", "), "\n")
}
```

### Si el error persiste

1. **Revisa los logs** en shinyapps.io (más arriba)
2. **Simplifica la app** temporalmente para identificar el problema
3. **Verifica el tamaño de los datos** - shinyapps.io tiene límites










