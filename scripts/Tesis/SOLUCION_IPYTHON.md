# Solución para Problemas de __file__ en IPython/Positron

## 🔧 Problema

En IPython/Jupyter/Positron, `__file__` no está definido porque los scripts no se ejecutan como archivos sino dentro del entorno interactivo.

## ✅ Solución Aplicada

Todos los scripts en `scripts/Tesis/` ahora usan:

```python
# Definir BASE_DIR: funciona tanto en script como en IPython/Jupyter
try:
    # En scripts normales, usar __file__
    BASE_DIR = Path(__file__).parent.parent.parent
except NameError:
    # En IPython/Jupyter, __file__ no existe, usar ruta absoluta
    BASE_DIR = Path("/Users/matdknu/Dropbox/MACI-UDEC/thesis_final")
    # Alternativa: BASE_DIR = Path(os.getcwd())
```

## 📋 Scripts Corregidos

Todos los scripts principales en `scripts/Tesis/` están corregidos:

1. ✅ `02_merge_raw_data.py`
2. ✅ `08_aplicacion_api.py`
3. ✅ `09_deepseek_api.py`
4. ✅ `14_rnn_classifier.py`
5. ✅ `16_real_data_plots.py` (no usa __file__, usa rutas relativas)

## 🚀 Uso en IPython/Positron

### Opción 1: Ejecutar directamente

```python
# Ejecutar script completo
exec(open('scripts/Tesis/08_aplicacion_api.py').read())
```

### Opción 2: Importar funciones

```python
# Si el script tiene funciones, puedes importarlas
import sys
sys.path.insert(0, 'scripts/Tesis')
# Luego importar y usar funciones específicas
```

### Opción 3: Usar rutas absolutas manualmente

Si necesitas ejecutar código manualmente en IPython:

```python
from pathlib import Path
BASE_DIR = Path("/Users/matdknu/Dropbox/MACI-UDEC/thesis_final")
RDS_PATH = BASE_DIR / "data" / "processed" / "reddit_filtrado.rds"
# ... resto del código
```

## ⚠️ Nota Importante

Los scripts en `scripts/no_usar/` y `scripts/no_sirve/` **pueden** tener problemas de `__file__`, pero **NO se usan** para la tesis. Estos scripts ya están organizados en carpetas separadas.

## 🔍 Verificar si un Script Está Corregido

```python
# Verificar si un script tiene try/except
with open('scripts/Tesis/nombre_script.py') as f:
    content = f.read()
    if '__file__' in content and 'except NameError:' in content:
        print("✅ Script está corregido")
    elif '__file__' in content:
        print("❌ Script necesita corrección")
    else:
        print("ℹ️  Script no usa __file__")
```

---

**Última actualización**: 2025-01-19
