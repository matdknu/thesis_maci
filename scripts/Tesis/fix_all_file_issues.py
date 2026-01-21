#!/usr/bin/env python3
"""
Script para corregir automáticamente todos los problemas de __file__ en scripts.
Para usar en IPython: exec(open('scripts/Tesis/fix_all_file_issues.py').read())
"""

import os
import re
from pathlib import Path

def fix_file_issue(file_path):
    """Corrige problemas de __file__ en un script Python."""
    try:
        content = file_path.read_text()
        
        # Buscar patrones problemáticos
        patterns_to_fix = [
            # Pattern 1: BASE_DIR = Path(__file__).parent...
            (r'BASE_DIR\s*=\s*Path\(__file__\)\.parent', 
             r'''# Definir BASE_DIR: funciona tanto en script como en IPython/Jupyter
try:
    # En scripts normales, usar __file__
    BASE_DIR = Path(__file__).parent.parent.parent
except NameError:
    # En IPython/Jupyter, __file__ no existe, usar ruta absoluta
    BASE_DIR = Path("/Users/matdknu/Dropbox/MACI-UDEC/thesis_final")
    # Alternativa: BASE_DIR = Path(os.getcwd())'''),
            
            # Pattern 2: os.chdir(Path(__file__).parent)
            (r'os\.chdir\(Path\(__file__\)\.parent\)',
             r'''# Definir directorio del script: funciona tanto en script como en IPython/Jupyter
try:
    # En scripts normales, usar __file__
    SCRIPT_DIR = Path(__file__).parent
except NameError:
    # En IPython/Jupyter, __file__ no existe, usar ruta absoluta
    SCRIPT_DIR = Path("/Users/matdknu/Dropbox/MACI-UDEC/thesis_final/scripts/Tesis")
    # Alternativa: SCRIPT_DIR = Path(os.getcwd()) / "scripts" / "Tesis"

os.chdir(SCRIPT_DIR)'''),
            
            # Pattern 3: BASE_DIR = os.path.dirname(os.path.abspath(__file__))
            (r'BASE_DIR\s*=\s*os\.path\.dirname\(os\.path\.dirname\(os\.path\.dirname\(os\.path\.abspath\(__file__\)\)\)\)',
             r'''# Definir BASE_DIR: funciona tanto en script como en IPython/Jupyter
try:
    # En scripts normales, usar __file__
    BASE_DIR = Path(__file__).parent.parent.parent
except NameError:
    # En IPython/Jupyter, __file__ no existe, usar ruta absoluta
    BASE_DIR = Path("/Users/matdknu/Dropbox/MACI-UDEC/thesis_final")
    # Alternativa: BASE_DIR = Path(os.getcwd())
BASE_DIR = Path(BASE_DIR)  # Asegurar que sea Path object'''),
        ]
        
        # Verificar si ya está corregido
        if 'except NameError:' in content:
            return False, "Ya está corregido"
        
        # Aplicar correcciones
        modified = False
        for pattern, replacement in patterns_to_fix:
            if re.search(pattern, content):
                content = re.sub(pattern, replacement, content)
                modified = True
        
        if modified:
            file_path.write_text(content)
            return True, "Corregido"
        
        return False, "No se encontró patrón a corregir"
        
    except Exception as e:
        return False, f"Error: {e}"

# Ejecutar correcciones
if __name__ == "__main__" or "__file__" not in globals():
    print("=" * 70)
    print("CORRECCIÓN AUTOMÁTICA DE PROBLEMAS DE __file__")
    print("=" * 70)
    
    # Buscar todos los scripts Python en scripts/Tesis
    base_dir = Path("/Users/matdknu/Dropbox/MACI-UDEC/thesis_final")
    scripts_dir = base_dir / "scripts" / "Tesis"
    
    python_files = list(scripts_dir.glob("*.py"))
    
    print(f"\n📁 Verificando {len(python_files)} scripts en scripts/Tesis/...\n")
    
    fixed_count = 0
    already_ok_count = 0
    
    for script in python_files:
        if script.name == "fix_all_file_issues.py":
            continue
        
        fixed, message = fix_file_issue(script)
        if fixed:
            print(f"✅ {script.name}: {message}")
            fixed_count += 1
        elif "Ya está corregido" in message:
            already_ok_count += 1
    
    print(f"\n{'='*70}")
    print(f"✅ Scripts corregidos: {fixed_count}")
    print(f"✅ Scripts ya correctos: {already_ok_count}")
    print(f"✅ Total: {len(python_files)}")
    print(f"{'='*70}")
