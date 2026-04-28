# ==============================================================================
# ANÁLISIS COMPLETO — REDDIT CHILE 2025
# v5.1 FINAL: marcos Entman, emociones como emociones, target claro
# Desempate por karma | Sin REVISAR | Filtro oct–dic 2025
# ==============================================================================

import os
import re
import csv
import json
import time
import random
import logging
import requests
import pyreadr
import pandas as pd
from pathlib import Path
from tqdm import tqdm

try:
    from dotenv import load_dotenv
except ImportError:  # pragma: no cover
    def load_dotenv(*_, **__) -> None:  # type: ignore
        return None

try:
    _BASE_FOR_ENV = Path(__file__).resolve().parent.parent.parent
except NameError:
    _BASE_FOR_ENV = Path(".").resolve()
load_dotenv(_BASE_FOR_ENV / ".env")

# ==============================================================================
# LOGGING
# ==============================================================================
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler("analisis_completo.log", encoding="utf-8")
    ]
)
log = logging.getLogger(__name__)

# ==============================================================================
# CONFIGURACIÓN — credenciales solo por entorno o archivo `.env` (no versionado)
# ==============================================================================
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "").strip()
DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY", "").strip()

OPENAI_URL = "https://api.openai.com/v1/chat/completions"
DEEPSEEK_URL = "https://api.deepseek.com/v1/chat/completions"

BASE_DIR = _BASE_FOR_ENV

RDS_PATH = BASE_DIR / "data" / "processed" / "reddit_depurado.rds"
if not RDS_PATH.exists():
    RDS_PATH = BASE_DIR / "data" / "processed" / "reddit_filtrado.rds"
    log.warning("reddit_depurado.rds no encontrado, usando reddit_filtrado.rds")

OUT_DIR         = BASE_DIR / "data" / "processed"
CHECKPOINT_PATH = OUT_DIR / "analisis_API.csv"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# ── Filtros de calidad ────────────────────────────────────────────────────────
MIN_TOKENS     = 5
MAX_CHARS_CTX  = 450
MAX_CHARS_BODY = 450

# ── Parámetros API ────────────────────────────────────────────────────────────
TEMPERATURE   = 0.1
MAX_TOKENS_A  = 120
MAX_TOKENS_B  = 120
MAX_RETRIES   = 3
RETRY_DELAY   = 5
RATE_LIMIT    = 0.5

# ── Modo de ejecución ─────────────────────────────────────────────────────────
MODO_PRUEBA            = True
# ← MODIFICADO: subido de 6000 a 8000 para incluir nuevos del período oct–dic
NUM_COMENTARIOS_PRUEBA = 8000
MUESTRA_RANDOM_SEED    = 42

# ── Filtro de fechas (período electoral clave) ────────────────────────────────
# ← ACTIVADO: solo comentarios entre 1 oct y 31 dic 2025
# Para desactivar y usar todo el corpus: comentar las dos líneas de FECHA_*
FECHA_INICIO = "2025-11-15"
FECHA_FIN    = "2025-12-20"

# ── Valores válidos ───────────────────────────────────────────────────────────
SENTIMIENTOS_VALIDOS = {"POSITIVO", "NEGATIVO", "NEUTRO"}
POLARIZACION_VALIDOS = {round(x * 0.1, 1) for x in range(11)}

MARCOS_VALIDOS = {
    "diagnostico",
    "pronostico",
    "motivacional",
    "conflicto",
    "moral",
    "economico",
    "identitario",
    "otro"
}

EMOCIONES_VALIDAS = {
    "indignacion",
    "ira",
    "desprecio",
    "miedo",
    "esperanza",
    "alegria",
    "ironia",
    "ninguna"
}

ESTRATEGIAS_VALIDAS = {
    "deslegitimacion",
    "ridiculizacion",
    "atribucion_oculta",
    "construccion_amenaza",
    "esencializacion",
    "ninguna"
}

FRONTERAS_VALIDAS    = {"inter_bloque", "intra_bloque", "ninguna"}
CANDIDATOS_DERECHA   = {"kast", "kaiser", "matthei"}
CANDIDATOS_IZQUIERDA = {"jara"}

# ==============================================================================
# PROMPTS v5.1
# ==============================================================================
SYSTEM_PROMPT = (
    "Eres un anotador experto en discurso político chileno. "
    "Respondes ÚNICAMENTE con un JSON válido, sin texto adicional ni markdown."
)

PROMPT_A = """Analiza este comentario de Reddit chileno en contexto electoral.

El hilo trata sobre: {candidatos_mencionados}

━━━ CONTEXTO DEL HILO ━━━
{contexto}

━━━ COMENTARIO ━━━
{comentario}

━━━ KARMA: {comment_score} ━━━
(positivo = comunidad lo apoya | negativo = comunidad lo rechaza)

(A) SENTIMIENTO hacia cada candidato del hilo — clasifica POR SEPARADO:

REGLAS DE TARGET (importante):
1. Clasifica solo si el comentario evalúa DIRECTAMENTE al candidato
   o lo hace de forma implícita pero clara.
2. Si critica a sus VOTANTES como extensión del candidato → NEGATIVO.
3. Si critica una IDEOLOGÍA o partido en abstracto sin nombrar al candidato → NEUTRO.
4. Si el comentario solo describe hechos o resultados electorales sin evaluar → NEUTRO.
5. Elogio irónico = NEGATIVO | Crítica irónica que defiende = POSITIVO.
6. Si mezcla positivo y negativo → elige el tono dominante.

(B) POLARIZACIÓN — intensidad afectiva del comentario (0.0 a 1.0):
0.0–0.1 = Neutral, informativo, sin carga emocional
0.2–0.3 = Opinión moderada, leve sesgo
0.4–0.5 = Crítica directa, sarcasmo, ironía política
0.6–0.7 = Ataque personal, descalificación fuerte
0.8–0.9 = Insulto grave, hostilidad explícita, humillación
1.0     = Amenaza, violencia verbal, deshumanización

USA TODO EL RANGO. No concentres en 0.4.
El karma orienta: score negativo → probablemente más hostil.

Ejemplos:
"Kast fundó el Partido Republicano en un guiño a la política de EEUU" karma=3
→ {{"kast":"NEUTRO","polarizacion":0.1}}

"Los comunistas no llegan al poder con democracia, asúmanlo" karma=3
→ {{"jara":"NEGATIVO","polarizacion":0.5}}

"ese wn es un peligro para el país" karma=45
→ {{"kast":"NEGATIVO","polarizacion":0.4}}

"vago de mierda que nunca ha hecho nada" karma=-5
→ {{"kast":"NEGATIVO","polarizacion":0.8}}

"Ojalá se hubiesen violado a tu vieja :)" karma=2
→ {{"kast":"NEGATIVO","polarizacion":1.0}}

Solo los candidatos del hilo. Sin texto extra.
{{"candidato": "SENTIMIENTO", "polarizacion": X.X}}
"""

PROMPT_B = """Analiza este comentario de Reddit chileno en contexto electoral.

━━━ CONTEXTO ━━━
{contexto}

━━━ COMENTARIO ━━━
{comentario}

━━━ CANDIDATOS EN EL HILO ━━━
{candidatos_mencionados}
Bloques: Kast/Kaiser/Matthei = derecha | Jara = izquierda

Clasifica en cuatro dimensiones:

━━━ (A) MARCO INTERPRETATIVO (Entman 1993) ━━━
diagnostico   → define un problema o señala causas
pronostico    → propone solución o alternativa
motivacional  → llama a actuar, movilizarse, cambiar algo
conflicto     → enfatiza disputa o choque entre actores políticos
moral         → juicio ético, corrupción, bien/mal, valores
economico     → propuestas económicas, cifras, impacto material
identitario   → cultura, ideología, inmigración, estilo de vida
otro          → no encaja claramente con ninguno anterior

━━━ (B) EMOCIÓN PREDOMINANTE ━━━
indignacion  → rabia moral ante algo injusto
ira          → agresión directa, hostilidad abierta, insulto
desprecio    → desdén, superioridad, humillación del otro
miedo        → percepción de amenaza, riesgo, incertidumbre
esperanza    → expectativa positiva, confianza en un cambio
alegria      → entusiasmo, celebración, satisfacción
ironia       → sarcasmo, burla implícita, humor político
ninguna      → comentario informativo sin emoción dominante

Distinción clave:
- desprecio ≠ ira: desprecio es frío y distante; ira es caliente y directa
- ironia ≠ alegria: ironía tiene intención crítica implícita
- indignacion ≠ ira: indignación tiene base moral; ira es más visceral

━━━ (C) ESTRATEGIA DE CONSTRUCCIÓN DEL ADVERSARIO ━━━
deslegitimacion      → niega competencia, seriedad o autoridad del candidato
ridiculizacion       → lo hace quedar en ridículo o lo burla
atribucion_oculta    → le imputa intenciones escondidas o conspirativas
construccion_amenaza → lo presenta como peligro para el país o la sociedad
esencializacion      → reduce al candidato/sus votantes a un rasgo negativo fijo
ninguna              → no hay estrategia adversarial identificable

━━━ (D) FRONTERA POLÍTICA ━━━
inter_bloque  → enfrenta derecha vs izquierda (Kast/Kaiser/Matthei vs Jara)
intra_bloque  → enfrenta candidatos del MISMO bloque de derecha entre sí
ninguna       → no hay confrontación entre bloques identificable

REGLA ESTRICTA:
→ NUNCA pongas inter_bloque si el hilo tiene SOLO candidatos de derecha
→ Si compara Kast vs Kaiser o Kast vs Matthei → intra_bloque
→ Si enfrenta candidato de derecha con Jara → inter_bloque
→ Si no hay confrontación clara → ninguna

{{"marco": "...", "emocion": "...", "estrategia": "...", "frontera": "..."}}
"""

# ==============================================================================
# PREPARACIÓN DEL CORPUS
# ==============================================================================
def es_texto_valido(texto: str) -> bool:
    return len(re.findall(r"\b\w{2,}\b", texto)) >= MIN_TOKENS


def preparar_corpus(df: pd.DataFrame) -> pd.DataFrame:
    log.info("Preparando corpus...")
    col_body = "comment_body_clean" if "comment_body_clean" in df.columns else "comment_body"

    df = df[
        df["comment_author"].notna() &
        ~df["comment_author"].isin(["[deleted]", "AutoModerator", "RemindMeBot"]) &
        df[col_body].notna() &
        (df[col_body].str.strip() != "") &
        ~df[col_body].isin(["[deleted]", "[removed]"])
    ].copy()
    log.info(f"  Tras filtro básico: {len(df):,}")

    candidatos_cols = [c for c in ["kast", "kaiser", "matthei", "jara"] if c in df.columns]
    df = df[df[candidatos_cols].max(axis=1) == 1].copy()
    log.info(f"  Tras filtro candidato en hilo: {len(df):,}")

    df["candidatos_hilo"] = df[candidatos_cols].apply(
        lambda row: [c for c in candidatos_cols if row[c] == 1], axis=1)
    df["candidatos_str"]  = df["candidatos_hilo"].apply(lambda lst: ", ".join(lst))
    df["n_candidatos"]    = df["candidatos_hilo"].apply(len)

    def tipo_frontera_hilo(cands):
        tiene_derecha   = bool(set(cands) & CANDIDATOS_DERECHA)
        tiene_izquierda = bool(set(cands) & CANDIDATOS_IZQUIERDA)
        if tiene_derecha and tiene_izquierda:
            return "mixto"
        elif tiene_derecha and len(set(cands) & CANDIDATOS_DERECHA) > 1:
            return "solo_derecha_multiple"
        elif tiene_derecha:
            return "solo_derecha"
        else:
            return "solo_izquierda"

    df["tipo_hilo"] = df["candidatos_hilo"].apply(tipo_frontera_hilo)

    titulo   = df["post_title"].fillna("").str.strip()
    selftext = df["post_selftext"].fillna("").str.strip() if "post_selftext" in df.columns \
               else pd.Series("", index=df.index)
    df["contexto_hilo"]     = (titulo + " " + selftext).str.strip().str[:MAX_CHARS_CTX]
    df["comentario_limpio"] = df[col_body].str.strip()

    df = df[df["comentario_limpio"].apply(es_texto_valido)].copy()
    log.info(f"  Tras filtro longitud ({MIN_TOKENS} palabras): {len(df):,}")

    df["comentario_api"] = df["comentario_limpio"].str[:MAX_CHARS_BODY]

    # ── Filtro de fecha (período electoral clave) ─────────────────────────────
    # ← Para usar todo el corpus sin filtro de fecha: comentar el bloque de abajo
    #    poniendo "#" al inicio de cada línea (FECHA_INICIO y FECHA_FIN también)
    if "fecha" in df.columns:
        df["fecha"] = pd.to_datetime(df["fecha"], errors="coerce")
        df = df[
            (df["fecha"] >= FECHA_INICIO) &   # ← comentar para sin filtro
            (df["fecha"] <= FECHA_FIN)         # ← comentar para sin filtro
        ].copy()
        log.info(f"  Tras filtro {FECHA_INICIO} → {FECHA_FIN}: {len(df):,}")
    # ─────────────────────────────────────────────────────────────────────────

    log.info(f"  1 candidato: {(df['n_candidatos']==1).sum():,} | 2+: {(df['n_candidatos']>1).sum():,}")
    log.info(f"  Hilos mixtos: {(df['tipo_hilo']=='mixto').sum():,}")
    log.info(f"  Solo derecha múltiple: {(df['tipo_hilo']=='solo_derecha_multiple').sum():,}")

    cols_keep = ["post_id", "comment_author", "comment_score", "fecha",
                 "candidatos_str", "n_candidatos", "tipo_hilo",
                 "contexto_hilo", "comentario_api",
                 "comentario_limpio"] + candidatos_cols
    return df[[c for c in cols_keep if c in df.columns]].reset_index(drop=True)


def _cuotas_proporcionales(n_total: int, sizes: list) -> list:
    total = sum(sizes)
    if total == 0 or n_total <= 0:
        return [0] * len(sizes)
    raw = [n_total * s / total for s in sizes]
    out = [int(r) for r in raw]
    resto = n_total - sum(out)
    frac = sorted(((raw[i] - out[i], i) for i in range(len(sizes))), reverse=True)
    for k in range(resto):
        out[frac[k][1]] += 1
    return out


def muestra_proporcional_intercalada(
    df_corpus: pd.DataFrame,
    n_objetivo: int,
    rng: random.Random,
) -> pd.DataFrame:
    candidatos_cols = ["kast", "kaiser", "matthei", "jara"]
    estratos, nombres = [], []
    for col in candidatos_cols:
        disp = df_corpus[
            (df_corpus["n_candidatos"] == 1)
            & df_corpus["candidatos_str"].str.contains(col, regex=False, na=False)
        ]
        estratos.append(disp)
        nombres.append(f"1×{col}")

    disp_mul = df_corpus[df_corpus["n_candidatos"] > 1]
    estratos.append(disp_mul)
    nombres.append("multi")

    sizes  = [len(e) for e in estratos]
    cuotas = _cuotas_proporcionales(n_objetivo, sizes)

    muestras = []
    for pool, q, nombre in zip(estratos, cuotas, nombres):
        n_tomar = min(q, len(pool))
        if n_tomar <= 0:
            muestras.append(pool.iloc[0:0].copy())
            log.info(f"  Estrato {nombre}: disponible={len(pool):,} → tomados=0")
            continue
        m = pool.sample(n_tomar, random_state=rng.randint(0, 2**31 - 1))
        muestras.append(m)
        log.info(f"  Estrato {nombre}: disponible={len(pool):,} → tomados={n_tomar}")

    entradas = []
    for si, mdf in enumerate(muestras):
        n = len(mdf)
        if n == 0:
            continue
        for j in range(n):
            pos = (j + 1) / (n + 1) + rng.random() * 1e-6 + si * 1e-9
            entradas.append((pos, mdf.iloc[j]))

    entradas.sort(key=lambda x: x[0])
    out = pd.DataFrame([t[1] for t in entradas]).reset_index(drop=True)
    out = out.drop_duplicates(subset=["post_id", "comment_author"])

    if len(out) < n_objetivo:
        faltan = n_objetivo - len(out)
        ya = set(zip(out["post_id"].astype(str), out["comment_author"].astype(str)))
        mask = ~df_corpus.apply(
            lambda r: (str(r["post_id"]), str(r["comment_author"])) in ya, axis=1
        )
        pool_extra = df_corpus.loc[mask]
        if len(pool_extra) > 0:
            extra = pool_extra.sample(
                min(faltan, len(pool_extra)),
                random_state=rng.randint(0, 2**31 - 1),
            )
            out = pd.concat([out, extra], ignore_index=True)
            out = out.drop_duplicates(subset=["post_id", "comment_author"])

    return out.head(n_objetivo).reset_index(drop=True)


# ==============================================================================
# DESEMPATE POR KARMA
# ==============================================================================
def resolver_consenso(oa_val, ds_val, pol_oa, pol_ds, comment_score: int):
    """
    Acuerdo  → ese valor.
    Desacuerdo → karma decide:
      score > 0  → gana el modelo con MENOS polarización (moderado)
      score < 0  → gana el modelo con MÁS polarización (hostil)
      score = 0  → gana DS (mejor kappa validado)
    """
    if oa_val == ds_val:
        return oa_val

    pol_oa = pol_oa or 0.5
    pol_ds = pol_ds or 0.5

    if comment_score > 0:
        ganador = "oa" if pol_oa <= pol_ds else "ds"
    elif comment_score < 0:
        ganador = "oa" if pol_oa >= pol_ds else "ds"
    else:
        ganador = "ds"

    return oa_val if ganador == "oa" else ds_val


# ==============================================================================
# PARSEO
# ==============================================================================
def _limpiar_json(content: str) -> str:
    content = content.strip()
    if "```" in content:
        for parte in content.split("```"):
            if "{" in parte:
                content = parte.replace("json", "").strip()
                break
    content = content.replace('\\"', '"')
    inicio  = content.find("{")
    fin     = content.rfind("}") + 1
    if inicio != -1 and fin > inicio:
        content = content[inicio:fin]
    return content


def parsear_prompt_a(content: str, modelo: str, candidatos: list) -> dict:
    resultado = {"polarizacion": 0.3, "parse_ok_a": False}
    for c in candidatos:
        resultado[f"sent_{c}"] = "NEUTRO"
    try:
        parsed = json.loads(_limpiar_json(content))
        pol = parsed.get("polarizacion", 0.3)
        try:
            pol = round(float(pol), 1)
            if pol not in POLARIZACION_VALIDOS:
                pol = round(min(POLARIZACION_VALIDOS, key=lambda x: abs(x - pol)), 1)
        except (TypeError, ValueError):
            pol = 0.3
        resultado["polarizacion"] = pol
        for c in candidatos:
            val = str(parsed.get(c, "")).strip().upper()
            if val not in SENTIMIENTOS_VALIDOS:
                val = next((s for s in SENTIMIENTOS_VALIDOS if s in val), "NEUTRO")
            resultado[f"sent_{c}"] = val
        resultado["parse_ok_a"] = True
    except json.JSONDecodeError:
        log.warning(f"[{modelo}/A] JSON inválido")
    return resultado


def parsear_prompt_b(content: str, modelo: str) -> dict:
    resultado = {"marco": "otro", "emocion": "ninguna",
                 "estrategia": "ninguna", "frontera": "ninguna",
                 "parse_ok_b": False}
    try:
        parsed = json.loads(_limpiar_json(content))
        resultado["marco"]      = str(parsed.get("marco",      "")).lower()
        resultado["emocion"]    = str(parsed.get("emocion",    "")).lower()
        resultado["estrategia"] = str(parsed.get("estrategia", "")).lower()
        resultado["frontera"]   = str(parsed.get("frontera",   "")).lower()
        if resultado["marco"]      not in MARCOS_VALIDOS:      resultado["marco"]      = "otro"
        if resultado["emocion"]    not in EMOCIONES_VALIDAS:   resultado["emocion"]    = "ninguna"
        if resultado["estrategia"] not in ESTRATEGIAS_VALIDAS: resultado["estrategia"] = "ninguna"
        if resultado["frontera"]   not in FRONTERAS_VALIDAS:   resultado["frontera"]   = "ninguna"
        resultado["parse_ok_b"] = True
    except json.JSONDecodeError:
        log.warning(f"[{modelo}/B] JSON inválido")
    return resultado


# ==============================================================================
# LLAMADAS A LA API
# ==============================================================================
def _call_api(url: str, headers: dict, payload: dict,
              modelo: str, max_tok: int) -> tuple:
    payload["max_tokens"] = max_tok
    for intento in range(1, MAX_RETRIES + 1):
        try:
            r = requests.post(url, headers=headers, json=payload, timeout=60)
            if r.status_code == 429:
                time.sleep(RETRY_DELAY * intento)
                continue
            if r.status_code != 200:
                log.error(f"[{modelo}] HTTP {r.status_code}")
                return None, 0, True
            data = r.json()
            return data["choices"][0]["message"]["content"], \
                   data.get("usage", {}).get("total_tokens", 0), False
        except requests.exceptions.Timeout:
            log.warning(f"[{modelo}] Timeout (intento {intento})")
            if intento < MAX_RETRIES:
                time.sleep(RETRY_DELAY)
        except Exception as e:
            log.error(f"[{modelo}] {e}")
            return None, 0, True
    return None, 0, True


def hacer_llamadas(contexto: str, comentario: str,
                   candidatos_str: str, candidatos: list,
                   comment_score: int) -> dict:
    h_oa = {"Authorization": f"Bearer {OPENAI_API_KEY}", "Content-Type": "application/json"}
    h_ds = {"Authorization": f"Bearer {DEEPSEEK_API_KEY}", "Content-Type": "application/json"}
    cfg_oa = {"model": "gpt-4o-mini",   "temperature": TEMPERATURE,
              "response_format": {"type": "json_object"}}
    cfg_ds = {"model": "deepseek-chat", "temperature": TEMPERATURE,
              "response_format": {"type": "json_object"}}

    def msgs(prompt_template, **kwargs):
        return [{"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user",   "content": prompt_template.format(**kwargs)}]

    res = {}

    c, t, e = _call_api(OPENAI_URL, h_oa,
        {**cfg_oa, "messages": msgs(PROMPT_A,
            candidatos_mencionados=candidatos_str,
            contexto=contexto, comentario=comentario,
            comment_score=comment_score)},
        "OA/A", MAX_TOKENS_A)
    time.sleep(RATE_LIMIT)
    res["oa_a"] = {**(parsear_prompt_a(c, "OA", candidatos) if not e and c
                      else {"polarizacion": None, "parse_ok_a": False,
                            **{f"sent_{x}": "ERROR" for x in candidatos}}),
                   "tokens": t, "error": e}

    c, t, e = _call_api(DEEPSEEK_URL, h_ds,
        {**cfg_ds, "messages": msgs(PROMPT_A,
            candidatos_mencionados=candidatos_str,
            contexto=contexto, comentario=comentario,
            comment_score=comment_score)},
        "DS/A", MAX_TOKENS_A)
    time.sleep(RATE_LIMIT)
    res["ds_a"] = {**(parsear_prompt_a(c, "DS", candidatos) if not e and c
                      else {"polarizacion": None, "parse_ok_a": False,
                            **{f"sent_{x}": "ERROR" for x in candidatos}}),
                   "tokens": t, "error": e}

    c, t, e = _call_api(OPENAI_URL, h_oa,
        {**cfg_oa, "messages": msgs(PROMPT_B,
            contexto=contexto, comentario=comentario,
            candidatos_mencionados=candidatos_str)},
        "OA/B", MAX_TOKENS_B)
    time.sleep(RATE_LIMIT)
    res["oa_b"] = {**(parsear_prompt_b(c, "OA") if not e and c
                      else {"marco": "ERROR", "emocion": "ERROR",
                            "estrategia": "ERROR", "frontera": "ERROR",
                            "parse_ok_b": False}),
                   "tokens": t, "error": e}

    c, t, e = _call_api(DEEPSEEK_URL, h_ds,
        {**cfg_ds, "messages": msgs(PROMPT_B,
            contexto=contexto, comentario=comentario,
            candidatos_mencionados=candidatos_str)},
        "DS/B", MAX_TOKENS_B)
    time.sleep(RATE_LIMIT)
    res["ds_b"] = {**(parsear_prompt_b(c, "DS") if not e and c
                      else {"marco": "ERROR", "emocion": "ERROR",
                            "estrategia": "ERROR", "frontera": "ERROR",
                            "parse_ok_b": False}),
                   "tokens": t, "error": e}

    return res


# ==============================================================================
# CONSTRUIR FILA
# ==============================================================================
def construir_fila(row: pd.Series, res: dict) -> dict:
    candidatos = row["candidatos_str"].split(", ")
    oa_a, ds_a = res["oa_a"], res["ds_a"]
    oa_b, ds_b = res["oa_b"], res["ds_b"]
    score      = int(row.get("comment_score", 0) or 0)

    pol_oa = oa_a.get("polarizacion")
    pol_ds = ds_a.get("polarizacion")
    pol_consenso = round((pol_oa + pol_ds) / 2, 2) \
                   if (pol_oa is not None and pol_ds is not None) \
                   else (pol_oa or pol_ds)

    def r(a, b):
        return resolver_consenso(a, b, pol_oa, pol_ds, score)

    fila = {
        "post_id":               row.get("post_id"),
        "comment_author":        row.get("comment_author"),
        "comment_score":         score,
        "fecha":                 row.get("fecha"),
        "candidatos":            row["candidatos_str"],
        "n_candidatos":          row["n_candidatos"],
        "tipo_hilo":             row.get("tipo_hilo", ""),
        "contexto_hilo":         str(row.get("contexto_hilo", ""))[:200]
                                 .replace("\n", " ").replace("\r", " "),
        "comentario_texto":      str(row.get("comentario_api", ""))
                                 .replace("\n", " ").replace("\r", " "),
        "oa_polarizacion":       pol_oa,
        "ds_polarizacion":       pol_ds,
        "polarizacion_consenso": pol_consenso,
        "oa_marco":              oa_b.get("marco"),
        "ds_marco":              ds_b.get("marco"),
        "marco_final":           r(oa_b.get("marco"), ds_b.get("marco")),
        "oa_emocion":            oa_b.get("emocion"),
        "ds_emocion":            ds_b.get("emocion"),
        "emocion_final":         r(oa_b.get("emocion"), ds_b.get("emocion")),
        "oa_estrategia":         oa_b.get("estrategia"),
        "ds_estrategia":         ds_b.get("estrategia"),
        "estrategia_final":      r(oa_b.get("estrategia"), ds_b.get("estrategia")),
        "oa_frontera":           oa_b.get("frontera"),
        "ds_frontera":           ds_b.get("frontera"),
        "frontera_final":        r(oa_b.get("frontera"), ds_b.get("frontera")),
        "tokens_oa_a":           oa_a.get("tokens", 0),
        "tokens_ds_a":           ds_a.get("tokens", 0),
        "tokens_oa_b":           oa_b.get("tokens", 0),
        "tokens_ds_b":           ds_b.get("tokens", 0),
        "tokens_total":          sum([oa_a.get("tokens", 0), ds_a.get("tokens", 0),
                                      oa_b.get("tokens", 0), ds_b.get("tokens", 0)]),
        "error_oa_a":            oa_a.get("error", False),
        "error_ds_a":            ds_a.get("error", False),
        "error_oa_b":            oa_b.get("error", False),
        "error_ds_b":            ds_b.get("error", False),
        "notas":                 "",
    }

    for c in ["kast", "kaiser", "matthei", "jara"]:
        if c in candidatos:
            oa_s = oa_a.get(f"sent_{c}", "ERROR")
            ds_s = ds_a.get(f"sent_{c}", "ERROR")
            fila[f"oa_sent_{c}"]    = oa_s
            fila[f"ds_sent_{c}"]    = ds_s
            fila[f"sent_final_{c}"] = r(oa_s, ds_s)
        else:
            fila[f"oa_sent_{c}"]    = None
            fila[f"ds_sent_{c}"]    = None
            fila[f"sent_final_{c}"] = None

    return fila


# ==============================================================================
# CLASIFICACIÓN CON CHECKPOINT
# ==============================================================================
def clasificar_con_checkpoint(df: pd.DataFrame) -> None:
    ya_procesados = set()
    if CHECKPOINT_PATH.exists():
        try:
            df_prev = pd.read_csv(CHECKPOINT_PATH, on_bad_lines="skip")
            df_prev = df_prev[df_prev["post_id"] != "post_id"]
            if {"post_id", "comment_author"}.issubset(df_prev.columns):
                ya_procesados = set(zip(
                    df_prev["post_id"].astype(str),
                    df_prev["comment_author"].astype(str)
                ))
                log.info(f"Retomando: {len(ya_procesados):,} ya procesados")
        except Exception as e:
            log.warning(f"No se pudo leer checkpoint: {e}")

    pendientes = df[
        ~df.apply(lambda r: (str(r["post_id"]), str(r["comment_author"])) in ya_procesados,
                  axis=1)
    ].copy()

    log.info(f"Pendientes: {len(pendientes):,}")
    if len(pendientes) == 0:
        log.info("✅ Todo ya procesado.")
        return

    tokens_sesion = 0
    primera_fila  = not CHECKPOINT_PATH.exists() or len(ya_procesados) == 0

    for idx, row in tqdm(pendientes.iterrows(), total=len(pendientes), desc="Clasificando"):
        score = int(row.get("comment_score", 0) or 0)
        res   = hacer_llamadas(
            str(row.get("contexto_hilo", "")),
            str(row.get("comentario_api", "")),
            row["candidatos_str"],
            row["candidatos_str"].split(", "),
            score,
        )
        fila = construir_fila(row, res)

        pd.DataFrame([fila]).to_csv(
            CHECKPOINT_PATH, mode="a", header=primera_fila, index=False,
            quoting=csv.QUOTE_ALL)
        primera_fila   = False
        tokens_sesion += fila.get("tokens_total", 0)

        log.info(
            f"  [{idx}] Marco={fila.get('marco_final')} | "
            f"Emoción={fila.get('emocion_final')} | "
            f"Frontera={fila.get('frontera_final')} | "
            f"Pol={fila.get('polarizacion_consenso')} | "
            f"Costo=~${tokens_sesion/1_000_000*0.15:.4f} USD"
        )

    log.info(f"Sesión OK. Tokens: {tokens_sesion:,} | "
             f"Costo: ~${tokens_sesion/1_000_000*0.15:.4f} USD")


# ==============================================================================
# REPORTE
# ==============================================================================
def reportar() -> None:
    if not CHECKPOINT_PATH.exists():
        print("No hay datos.")
        return

    df = pd.read_csv(CHECKPOINT_PATH, on_bad_lines="skip")
    df = df[df["post_id"] != "post_id"].copy()

    print("\n" + "=" * 70)
    print("✅ REPORTE v5.1")
    print("=" * 70)
    print(f"{'Comentarios procesados':.<45} {len(df):,}")

    pol = pd.to_numeric(df["polarizacion_consenso"], errors="coerce")
    print(f"\n── Polarización ─────────")
    print(f"  Media: {pol.mean():.3f} | SD: {pol.std():.3f} | "
          f"Min: {pol.min():.1f} | Max: {pol.max():.1f}")

    print(f"\n── Marco (Entman) ──────")
    if "marco_final" in df.columns:
        print(df["marco_final"].value_counts().to_string())

    print(f"\n── Emoción ─────────────")
    if "emocion_final" in df.columns:
        print(df["emocion_final"].value_counts().to_string())

    print(f"\n── Estrategia ──────────")
    if "estrategia_final" in df.columns:
        print(df["estrategia_final"].value_counts().to_string())

    print(f"\n── Frontera ────────────")
    if "frontera_final" in df.columns:
        print(df["frontera_final"].value_counts().to_string())

    print(f"\n── Sentimiento ─────────")
    for c in ["kast", "kaiser", "matthei", "jara"]:
        col = f"sent_final_{c}"
        if col in df.columns:
            sub = df[df["candidatos"].str.contains(c, na=False)]
            if len(sub):
                print(f"  {c} (n={len(sub)}): {sub[col].value_counts().to_dict()}")

    print(f"\n── Costo ───────────────")
    try:
        tok_oa = (
            pd.to_numeric(df["tokens_oa_a"], errors="coerce").fillna(0).sum() +
            pd.to_numeric(df["tokens_oa_b"], errors="coerce").fillna(0).sum()
        )
        tok_ds = (
            pd.to_numeric(df["tokens_ds_a"], errors="coerce").fillna(0).sum() +
            pd.to_numeric(df["tokens_ds_b"], errors="coerce").fillna(0).sum()
        )
        print(f"  OpenAI:   {int(tok_oa):,} tokens → ~${tok_oa/1_000_000*0.15:.4f} USD")
        print(f"  DeepSeek: {int(tok_ds):,} tokens")
    except Exception as e:
        print(f"  (No se pudo calcular costo: {e})")

    print(f"\n💾 {CHECKPOINT_PATH}")


# ==============================================================================
# MAIN
# ==============================================================================
if __name__ == "__main__":

    if not OPENAI_API_KEY:
        log.error(
            "OPENAI_API_KEY no configurada. export OPENAI_API_KEY=... "
            "o añádela a un archivo `.env` en la raíz del repositorio (ver .env.example)."
        )
        raise SystemExit(1)
    if not DEEPSEEK_API_KEY:
        log.error(
            "DEEPSEEK_API_KEY no configurada. export DEEPSEEK_API_KEY=... "
            "o añádela a `.env` en la raíz del repositorio (ver .env.example)."
        )

    print("=" * 70)
    print("🚀 ANÁLISIS COMPLETO — REDDIT CHILE 2025 v5.1")
    print(f"   Período: {FECHA_INICIO} → {FECHA_FIN}")
    print(f"   Muestra objetivo: {NUM_COMENTARIOS_PRUEBA} comentarios")
    print(f"   Checkpoint activo: no sobreescribe procesados")
    print("=" * 70)

    log.info(f"Cargando {RDS_PATH} ...")
    try:
        rds    = pyreadr.read_r(str(RDS_PATH))
        df_raw = next(iter(rds.values()))
        log.info(f"Filas: {len(df_raw):,} | Columnas: {list(df_raw.columns)}")
    except Exception as e:
        log.error(f"Error cargando datos: {e}")
        raise SystemExit(1)

    df_corpus = preparar_corpus(df_raw)

    if MODO_PRUEBA:
        log.info(f"MODO PRUEBA: {NUM_COMENTARIOS_PRUEBA} comentarios")
        rng        = random.Random(MUESTRA_RANDOM_SEED)
        df_muestra = muestra_proporcional_intercalada(df_corpus, NUM_COMENTARIOS_PRUEBA, rng)
        log.info(f"  Muestra final: {len(df_muestra)} comentarios")
        for col in ["kast", "kaiser", "matthei", "jara"]:
            n = df_muestra["candidatos_str"].str.contains(col).sum()
            log.info(f"    {col}: {n}")
        log.info(f"    co-menciones: {(df_muestra['n_candidatos']>1).sum()}")
        log.info(f"    mixtos: {(df_muestra['tipo_hilo']=='mixto').sum()}")
    else:
        log.info(f"MODO COMPLETO: {len(df_corpus):,} comentarios")
        df_muestra = df_corpus

    clasificar_con_checkpoint(df_muestra)
    reportar()