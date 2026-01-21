#!/bin/bash
# Script para copiar datos a shiny_app antes de desplegar
# Ejecutar: bash shiny_app/copiar_datos.sh

echo "📦 Copiando datos a shiny_app para despliegue..."

# Crear directorios
mkdir -p shiny_app/data/processed
mkdir -p shiny_app/data/servel

# Copiar datos principales
if [ -f "data/processed/reddit_filtrado.rds" ]; then
  cp data/processed/reddit_filtrado.rds shiny_app/data/processed/
  echo "✅ reddit_filtrado.rds copiado ($(du -h data/processed/reddit_filtrado.rds | cut -f1))"
else
  echo "⚠️ reddit_filtrado.rds no encontrado"
fi

# Copiar datos de ideología si existen
if [ -d "data/processed/imputacion_ideologia" ]; then
  cp -r data/processed/imputacion_ideologia shiny_app/data/processed/
  echo "✅ Datos de ideología copiados"
fi

# Copiar datos SERVEL si existen
if [ -d "data/servel" ]; then
  cp -r data/servel/* shiny_app/data/servel/ 2>/dev/null
  echo "✅ Datos SERVEL copiados"
fi

echo ""
echo "✅ Proceso completado. Los datos están en shiny_app/data/"
echo "📊 Tamaño total: $(du -sh shiny_app/data | cut -f1)"










