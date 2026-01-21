#!/usr/bin/env python3
"""
Script para unir datos raw de project_reddit y thesis_reddit,
eliminando duplicados y manteniendo las versiones más completas.
"""

import pandas as pd
import os
from pathlib import Path
import shutil
from datetime import datetime

# Definir directorio del script: funciona tanto en script como en IPython/Jupyter
try:
    # En scripts normales, usar __file__
    SCRIPT_DIR = Path(__file__).parent
except NameError:
    # En IPython/Jupyter, __file__ no existe, usar ruta absoluta o cwd
    SCRIPT_DIR = Path("/Users/matdknu/Dropbox/MACI-UDEC/thesis_final/scripts/Tesis")
    # Alternativa: SCRIPT_DIR = Path(os.getcwd()) / "scripts" / "Tesis"

# Cambiar al directorio del script
os.chdir(SCRIPT_DIR)

# Rutas (relativas al script)
project_reddit_raw = Path("../../project_reddit/raw_data")
thesis_reddit_raw = Path("../../thesis_reddit/data/raw")
thesis_final_raw = Path("../data/raw")

# Archivos CSV a procesar
csv_files = [
    "reddit_comentarios.csv",
    "reddit_comentarios_derecha.csv",
    "reddit_posts.csv",
    "reddit_posts_derecha.csv",
    "reddit_filtrados.csv"
]

def merge_csv_files(filename):
    """Une dos archivos CSV eliminando duplicados"""
    pr_path = project_reddit_raw / filename
    tr_path = thesis_reddit_raw / filename
    output_path = thesis_final_raw / filename
    
    pr_exists = pr_path.exists()
    tr_exists = tr_path.exists()
    
    if not pr_exists and not tr_exists:
        print(f"⚠️  {filename}: No existe en ninguna carpeta")
        return False
    
    if pr_exists and not tr_exists:
        print(f"✅ {filename}: Solo en project_reddit, copiando...")
        shutil.copy2(pr_path, output_path)
        return True
    
    if tr_exists and not pr_exists:
        print(f"✅ {filename}: Solo en thesis_reddit, copiando...")
        shutil.copy2(tr_path, output_path)
        return True
    
    # Ambos existen, comparar y unir
    print(f"\n📊 {filename}: Uniendo datos...")
    
    try:
        # Leer ambos archivos
        print(f"  Leyendo project_reddit ({pr_path.stat().st_size / 1024 / 1024:.1f} MB)...")
        pr_df = pd.read_csv(pr_path, low_memory=False)
        print(f"    Filas: {len(pr_df):,}")
        
        print(f"  Leyendo thesis_reddit ({tr_path.stat().st_size / 1024 / 1024:.1f} MB)...")
        tr_df = pd.read_csv(tr_path, low_memory=False)
        print(f"    Filas: {len(tr_df):,}")
        
        # Identificar columnas comunes para detectar duplicados
        common_cols = set(pr_df.columns) & set(tr_df.columns)
        if not common_cols:
            print(f"  ⚠️  No hay columnas comunes, usando el más reciente")
            pr_date = pr_path.stat().st_mtime
            tr_date = tr_path.stat().st_mtime
            if pr_date > tr_date:
                shutil.copy2(pr_path, output_path)
                print(f"  ✅ Usando project_reddit (más reciente)")
            else:
                shutil.copy2(tr_path, output_path)
                print(f"  ✅ Usando thesis_reddit (más reciente)")
            return True
        
        # Intentar identificar columna única (id, permalink, etc.)
        id_cols = ['id', 'permalink', 'name', 'link_id', 'parent_id']
        id_col = None
        for col in id_cols:
            if col in common_cols:
                id_col = col
                break
        
        if id_col:
            print(f"  Usando '{id_col}' para detectar duplicados...")
            # Unir y eliminar duplicados
            merged_df = pd.concat([pr_df, tr_df], ignore_index=True)
            print(f"  Total después de concatenar: {len(merged_df):,} filas")
            
            # Eliminar duplicados basados en id_col
            before_dedup = len(merged_df)
            merged_df = merged_df.drop_duplicates(subset=[id_col], keep='last')
            after_dedup = len(merged_df)
            print(f"  Después de eliminar duplicados: {after_dedup:,} filas ({before_dedup - after_dedup:,} duplicados eliminados)")
        else:
            # Sin columna ID, usar todas las columnas comunes
            print(f"  No se encontró columna ID única, usando todas las columnas para detectar duplicados...")
            merged_df = pd.concat([pr_df, tr_df], ignore_index=True)
            before_dedup = len(merged_df)
            merged_df = merged_df.drop_duplicates(keep='last')
            after_dedup = len(merged_df)
            print(f"  Después de eliminar duplicados: {after_dedup:,} filas ({before_dedup - after_dedup:,} duplicados eliminados)")
        
        # Guardar resultado
        print(f"  Guardando en {output_path}...")
        merged_df.to_csv(output_path, index=False)
        print(f"  ✅ Guardado: {len(merged_df):,} filas, {output_path.stat().st_size / 1024 / 1024:.1f} MB")
        return True
        
    except Exception as e:
        print(f"  ❌ Error procesando {filename}: {e}")
        # En caso de error, usar el más reciente
        pr_date = pr_path.stat().st_mtime
        tr_date = tr_path.stat().st_mtime
        if pr_date > tr_date:
            shutil.copy2(pr_path, output_path)
            print(f"  ✅ Copiado project_reddit como respaldo")
        else:
            shutil.copy2(tr_path, output_path)
            print(f"  ✅ Copiado thesis_reddit como respaldo")
        return False

def merge_trends():
    """Une los archivos de trends"""
    print("\n" + "="*60)
    print("PROCESANDO TRENDS")
    print("="*60)
    
    trends_files = [
        "trends_candidatos_daily.csv",
        "trends_candidatos_daily_right.csv"
    ]
    
    for trend_file in trends_files:
        pr_path = Path("../../project_reddit/trends") / trend_file
        tr_path = Path("../../thesis_reddit/data/trends/series") / trend_file
        output_path = Path("../data/trends/series") / trend_file
        
        pr_exists = pr_path.exists()
        tr_exists = tr_path.exists()
        
        if not pr_exists and not tr_exists:
            print(f"⚠️  {trend_file}: No existe en ninguna carpeta")
            continue
        
        if pr_exists and not tr_exists:
            print(f"✅ {trend_file}: Solo en project_reddit, copiando...")
            output_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(pr_path, output_path)
            continue
        
        if tr_exists and not pr_exists:
            print(f"✅ {trend_file}: Solo en thesis_reddit, copiando...")
            output_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(tr_path, output_path)
            continue
        
        # Ambos existen, unir
        print(f"\n📊 {trend_file}: Uniendo datos...")
        try:
            pr_df = pd.read_csv(pr_path)
            tr_df = pd.read_csv(tr_path)
            
            print(f"  project_reddit: {len(pr_df):,} filas")
            print(f"  thesis_reddit:  {len(tr_df):,} filas")
            
            # Para trends, unir por fecha y mantener la más reciente
            if 'date' in pr_df.columns and 'date' in tr_df.columns:
                merged_df = pd.concat([pr_df, tr_df], ignore_index=True)
                merged_df['date'] = pd.to_datetime(merged_df['date'])
                merged_df = merged_df.sort_values('date')
                merged_df = merged_df.drop_duplicates(subset=['date'], keep='last')
                merged_df = merged_df.sort_values('date')
                
                print(f"  Después de unir y eliminar duplicados: {len(merged_df):,} filas")
                
                output_path.parent.mkdir(parents=True, exist_ok=True)
                merged_df.to_csv(output_path, index=False)
                print(f"  ✅ Guardado en {output_path}")
            else:
                # Sin columna date, usar el más reciente
                pr_date = pr_path.stat().st_mtime
                tr_date = tr_path.stat().st_mtime
                output_path.parent.mkdir(parents=True, exist_ok=True)
                if pr_date > tr_date:
                    shutil.copy2(pr_path, output_path)
                    print(f"  ✅ Usando project_reddit (más reciente)")
                else:
                    shutil.copy2(tr_path, output_path)
                    print(f"  ✅ Usando thesis_reddit (más reciente)")
        except Exception as e:
            print(f"  ❌ Error: {e}")
            # Usar el más reciente como respaldo
            pr_date = pr_path.stat().st_mtime
            tr_date = tr_path.stat().st_mtime
            output_path.parent.mkdir(parents=True, exist_ok=True)
            if pr_date > tr_date:
                shutil.copy2(pr_path, output_path)
            else:
                shutil.copy2(tr_path, output_path)

if __name__ == "__main__":
    print("="*60)
    print("UNIENDO DATOS RAW DE PROJECT_REDDIT Y THESIS_REDDIT")
    print("="*60)
    
    # Asegurar que el directorio de salida existe
    thesis_final_raw.mkdir(parents=True, exist_ok=True)
    
    # Procesar archivos CSV
    for csv_file in csv_files:
        merge_csv_files(csv_file)
    
    # Procesar trends
    merge_trends()
    
    print("\n" + "="*60)
    print("✅ PROCESO COMPLETADO")
    print("="*60)

