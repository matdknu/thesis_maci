# Solución para Error SSL/TLS al Desplegar en shinyapps.io

## Error
```
SSL connect error [api.shinyapps.io]:
TLS connect error: error:0BFFF065:x509 certificate routines:CRYPTO_internal:cert already in hash table
```

## Soluciones Rápidas

### 1. Actualizar Paquetes (Más Común)
```r
# En R o RStudio
update.packages(c("curl", "httr", "rsconnect"), ask = FALSE)
install.packages("rsconnect", dependencies = TRUE)
```

### 2. Configurar Opciones SSL
```r
options(
  rsconnect.http = "libcurl",
  rsconnect.http.libcurl = TRUE
)
```

### 3. Actualizar Certificados (macOS)
```bash
# En terminal
brew install ca-certificates
brew upgrade curl
```

### 4. Usar Script de Despliegue Corregido
```r
# Ejecuta el script deploy_fixed.R
source("shiny_app/deploy_fixed.R")
```

### 5. Desplegar desde RStudio (Recomendado)
1. Abre RStudio
2. Abre el archivo `shiny_app/app.R`
3. Click en "Publish" (botón azul arriba)
4. Selecciona "Deploy Application"
5. RStudio maneja automáticamente la configuración SSL

## Soluciones Avanzadas

### Si Persiste el Error

#### Opción A: Reinstalar rsconnect
```r
remove.packages("rsconnect")
install.packages("rsconnect", repos = "https://cran.rstudio.com/")
```

#### Opción B: Verificar Versión de curl
```bash
curl --version
# Si es muy antigua, actualiza:
brew upgrade curl  # macOS
# o
sudo apt-get update && sudo apt-get upgrade curl  # Linux
```

#### Opción C: Configurar Certificados Manualmente
```r
# Descargar certificados CA bundle
download.file(
  "https://curl.se/ca/cacert.pem",
  destfile = "cacert.pem"
)

# Configurar
Sys.setenv(CURL_CA_BUNDLE = normalizePath("cacert.pem"))
```

#### Opción D: Usar Método HTTP Alternativo
```r
options(rsconnect.http = "rstudio-http")
# Luego intenta desplegar de nuevo
```

## Verificación

Para verificar que todo está bien:
```r
library(httr)
test <- GET("https://api.shinyapps.io")
status_code(test)  # Debería ser 200
```

## Contacto

Si ninguna solución funciona:
1. Verifica tu conexión a internet
2. Revisa si hay firewall/proxy bloqueando
3. Contacta soporte de shinyapps.io: support@rstudio.com

## Notas

- El error suele ser temporal y se resuelve actualizando paquetes
- RStudio suele manejar mejor la configuración SSL que la línea de comandos
- En macOS, los certificados se actualizan automáticamente con las actualizaciones del sistema










