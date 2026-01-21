# -*- coding: utf-8 -*-
# /usr/bin/env python
import os
import time
import hashlib
from datetime import datetime
from pathlib import Path
import re
import os

import pandas as pd
import praw
from prawcore.exceptions import RequestException, ResponseException, ServerError, Forbidden, NotFound

# ============== ⚙️ Configuración Excel (fallback si no hay openpyxl) ==============
try:
    import openpyxl   # noqa
    WRITER_ENGINE = "openpyxl"
except ImportError:
    try:
        import xlsxwriter  # noqa
        WRITER_ENGINE = "xlsxwriter"
        print("⚠️ 'openpyxl' no está instalado. Usaré 'xlsxwriter' para escribir .xlsx.")
    except ImportError:
        WRITER_ENGINE = None
        print("❌ No hay motor para escribir .xlsx (instala 'openpyxl' o 'xlsxwriter'). Se guardarán solo CSV.")

# ============== 🔑 Credenciales Reddit ==============
reddit = praw.Reddit(
    client_id="_qzeVBBUQWmuuBJeAMEvnw",
    client_secret="AkC9zJm6w8CPbqFfKsJH3Ltr1q2UsQ",
    user_agent="reddit_scraper_r by u/One_Definition_3989"
)

# ============== 📂 Salidas ==============
downloads_folder = "data/raw"
Path(downloads_folder).mkdir(parents=True, exist_ok=True)

# sufijo solicitado
SUF = "_derecha"

# Excel con 2 hojas (posts y comentarios)
acum_path_excel = os.path.join(downloads_folder, f"reddit_posts_comentarios{SUF}.xlsx")

# Excel flat (post + comentario en la misma fila)
flat_xlsx = os.path.join(downloads_folder, f"reddit_posts_comentarios_flat{SUF}.xlsx")

# CSV separados acumulativos
acum_posts_csv = os.path.join(downloads_folder, f"reddit_posts{SUF}.csv")
acum_comments_csv = os.path.join(downloads_folder, f"reddit_comentarios{SUF}.csv")
acum_posts_parquet = os.path.join(downloads_folder, f"reddit_posts{SUF}.parquet")
acum_comments_parquet = os.path.join(downloads_folder, f"reddit_comentarios{SUF}.parquet")

# ============== 🎯 Subreddit específico (comunidad chilena) ==============
# --- Subreddits (solo comunidades, sin términos) ---
subreddits = [
    "RepublicadeChile",
    "chile"
]

# ============== 🔎 Palabras clave: Kast, Kaiser, Matthei (robusto a acentos) ==============
# Coincide con: "kast", "jose/josé antonio kast", "kaiser", "johannes kaiser",
# "matthei", "evelyn matthei"
NAME_PATTERNS = [
    r"\bj(os[eé])\s*antonio\s*kast\b",        # José/José Antonio Kast
    r"\bkast\b",

    r"\bjohannes\s*kaiser\b",                 # Johannes Kaiser
    r"\bkaiser\b",

    r"\bevelyn\s*matthei\b",                  # Evelyn Matthei
    r"\bmatthei\b",

    r"\bjeann?ette?\s*jara\b",                # Jeannette / Jeanette / Jeanneta Jara
    r"\bjara\b",

    r"\bfranco\s*parisi\b",                   # Franco Parisi
    r"\bparisi\b",

    # --- NUEVOS ---
    r"\bharold\s*mayne[\s-]*nicholls\b",      # Harold Mayne-Nicholls
    r"\bmayne[\s-]*nicholls\b",               # Mayne-Nicholls (solo)
    r"\bnicholls\b",               # Mayne-Nicholls (solo)
    r"\bharold\b",                            # Harold

    r"\bmarco\s+enr[ií]quez[\s-]*ominami\b",  # Marco Enríquez-Ominami
    r"\bmeo\b",                               # MEO

    r"\beduardo\s*art[eé]s\b",                # Eduardo Artés
    r"\bart[eé]s\b",                          # Artés
    r"\bprofe\s*art[eé]s\b"                   # Profe Artés
]


NAMES_REGEX = re.compile("|".join(NAME_PATTERNS), flags=re.IGNORECASE)

def text_matches_politicians(txt: str) -> bool:
    if not isinstance(txt, str) or not txt:
        return False
    return bool(NAMES_REGEX.search(txt))

# ============== ⏱️ Parámetros ==============
posts_limit_por_subreddit = 1000
saltar_stickies = True
max_retries = 4
base_backoff = 1.5

def safe_author(a):
    return str(a) if a is not None else "[deleted]"

def hash_post_id(post_id, created_utc, author, title):
    base = f"{post_id}|{int(created_utc or 0)}|{author}|{(title or '')[:80]}"
    return hashlib.sha256(base.encode("utf-8")).hexdigest()

def hash_comment_id(post_id, comment_id, created_utc, author, body):
    base = f"{post_id}|{comment_id}|{int(created_utc or 0)}|{author}|{(body or '')[:80]}"
    return hashlib.sha256(base.encode("utf-8")).hexdigest()

def ensure_datetime_columns(df, columns):
    for col in columns:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], errors="coerce")

def fetch_all_comments(submission):
    submission.comment_limit = None
    submission.comment_sort = "new"
    err = None
    for i in range(max_retries):
        try:
            submission.comments.replace_more(limit=None)
            return submission.comments.list(), None
        except (RequestException, ResponseException, ServerError) as e:
            err = f"{type(e).__name__}: {e}"
            sleep_s = base_backoff ** (i + 1)
            print(f"   🔁 Retry {i+1}/{max_retries} expandiendo {submission.id} -> {err}. Esperando {sleep_s:.1f}s…")
            time.sleep(sleep_s)
        except (Forbidden, NotFound) as e:
            err = f"{type(e).__name__}: {e}"
            break
        except Exception as e:
            err = f"{type(e).__name__}: {e}"
            break
    return (submission.comments.list() if hasattr(submission.comments, "list") else []), err

# ============== 📥 Cargar acumulados previos (si existen) ==============
if os.path.exists(acum_posts_csv):
    df_posts_acum = pd.read_csv(acum_posts_csv, dtype={"post_unique_id": str})
else:
    df_posts_acum = pd.DataFrame()

if os.path.exists(acum_comments_csv):
    df_comments_acum = pd.read_csv(acum_comments_csv, dtype={"comment_unique_id": str})
else:
    df_comments_acum = pd.DataFrame()

# ============== 🚀 Scraping (filtrado por nombres) ==============
run_ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
posts_rows = []
comments_rows = []

print("🚀 Iniciando scraping de r/RepublicadeChile con filtro (Kast/Kaiser/Matthei)…")

for sr in subreddits:
    print(f"📥 Recorriendo r/{sr} (hasta {posts_limit_por_subreddit} posts recientes)…")
    try:
        for submission in reddit.subreddit(sr).new(limit=posts_limit_por_subreddit):
            if saltar_stickies and getattr(submission, "stickied", False):
                continue

            post_created_utc = getattr(submission, "created_utc", None)
            post_author = safe_author(getattr(submission, "author", None))
            post_title = getattr(submission, "title", "") or ""
            post_selftext = getattr(submission, "selftext", "") or ""
            post_url = f"https://reddit.com{submission.permalink}"
            post_subreddit = str(submission.subreddit)
            post_score = getattr(submission, "score", None)
            post_num_comments = getattr(submission, "num_comments", None)
            post_flair = getattr(submission, "link_flair_text", None)

            # -------- filtro por nombres en título o cuerpo del post --------
            post_matches = text_matches_politicians(post_title) or text_matches_politicians(post_selftext)
            if not post_matches:
                # si el post no menciona, no seguimos a comentarios (optimiza tiempo/cupo)
                continue

            post_unique_id = hash_post_id(
                submission.id, post_created_utc, post_author, post_title
            )

            posts_rows.append({
                "post_unique_id": post_unique_id,
                "run_timestamp": run_ts,
                "post_id": submission.id,
                "subreddit": post_subreddit,
                "title": post_title,
                "selftext": post_selftext,
                "author": post_author,
                "permalink": post_url,
                "score": post_score,
                "num_comments": post_num_comments,
                "flair": post_flair,
                "created": datetime.fromtimestamp(post_created_utc) if post_created_utc else None
            })

            # -------- comentarios (solo guardamos los que mencionan los nombres) --------
            comments, err = fetch_all_comments(submission)
            got = len(comments)
            if err:
                print(f"   ⚠️ {submission.id}: {got} comentarios (motivo: {err})")
            else:
                print(f"   ✅ {submission.id}: {got} comentarios descargados, filtrando por nombres…")

            for c in comments:
                c_body = getattr(c, "body", "") or ""
                if not text_matches_politicians(c_body):
                    continue  # solo comentarios que mencionan los nombres

                c_created_utc = getattr(c, "created_utc", None)
                c_author = safe_author(getattr(c, "author", None))
                c_score = getattr(c, "score", None)

                comment_unique_id = hash_comment_id(
                    submission.id, c.id, c_created_utc, c_author, c_body
                )

                comments_rows.append({
                    "comment_unique_id": comment_unique_id,
                    "run_timestamp": run_ts,
                    "post_unique_id": post_unique_id,
                    "post_id": submission.id,
                    "post_subreddit": post_subreddit,
                    "post_title": post_title,
                    "post_url": post_url,
                    "post_author": post_author,
                    "post_selftext": post_selftext,
                    "post_score": post_score,
                    "post_num_comments": post_num_comments,
                    "post_flair": post_flair,
                    "post_created": datetime.fromtimestamp(post_created_utc) if post_created_utc else None,
                    "comment_id": c.id,
                    "comment_author": c_author,
                    "comment_body": c_body,
                    "comment_score": c_score,
                    "comment_created": datetime.fromtimestamp(c_created_utc) if c_created_utc else None
                })

        time.sleep(0.2)

    except Exception as e:
        print(f"⚠️ Error recorriendo r/{sr}: {e}")
        time.sleep(1.0)

# ============== 🧹 Sanitizar para Excel (caracteres no imprimibles) ==============
def clean_excel_string(val):
    if isinstance(val, str):
        return re.sub(r"[\x00-\x08\x0B-\x0C\x0E-\x1F]", "", val)
    return val

# ============== 🧱 DataFrames nuevos & acumulación ==============
df_posts_new = pd.DataFrame(posts_rows)
df_comments_new = pd.DataFrame(comments_rows)

# Acumular posts
if not df_posts_new.empty:
    if os.path.exists(acum_posts_csv):
        df_posts_final = pd.concat([df_posts_acum, df_posts_new], ignore_index=True)
    else:
        df_posts_final = df_posts_new.copy()
    df_posts_final.drop_duplicates(subset=["post_unique_id"], inplace=True)
else:
    df_posts_final = df_posts_acum.copy()

# Acumular comentarios
if not df_comments_new.empty:
    if os.path.exists(acum_comments_csv):
        df_comments_final = pd.concat([df_comments_acum, df_comments_new], ignore_index=True)
    else:
        df_comments_final = df_comments_new.copy()
    df_comments_final.drop_duplicates(subset=["comment_unique_id"], inplace=True)
else:
    df_comments_final = df_comments_acum.copy()

# ============== 🔢 Asegurar tipos numéricos ==============
numeric_cols_posts = ["score", "num_comments"]
for col in numeric_cols_posts:
    if col in df_posts_final.columns:
        df_posts_final[col] = pd.to_numeric(df_posts_final[col], errors="coerce")
        df_posts_final[col] = df_posts_final[col].astype("Int64")  # enteros con NA

numeric_cols_comments = ["post_score", "post_num_comments", "comment_score"]
for col in numeric_cols_comments:
    if col in df_comments_final.columns:
        df_comments_final[col] = pd.to_numeric(df_comments_final[col], errors="coerce")
        df_comments_final[col] = df_comments_final[col].astype("Int64")  # enteros con NA

# ============== 📅 Asegurar tipos de fecha ==============
ensure_datetime_columns(df_posts_final, ["created"])
ensure_datetime_columns(df_comments_final, ["post_created", "comment_created"])

# ============== 💾 Guardar CSVs ==============
df_posts_final.to_csv(acum_posts_csv, index=False)
df_comments_final.to_csv(acum_comments_csv, index=False)

# Guardar Parquet (opcional, requiere pyarrow o fastparquet)
try:
    df_posts_final.to_parquet(acum_posts_parquet, index=False)
    df_comments_final.to_parquet(acum_comments_parquet, index=False)
    parquet_saved = True
except ImportError as e:
    print(f"⚠️ Parquet omitido: {e}")
    parquet_saved = False
except Exception as e:
    print(f"⚠️ Error guardando Parquet: {e}")
    parquet_saved = False

# ============== 📘 Guardar Excel (si hay motor disponible) ==============
df_posts_final = df_posts_final.map(clean_excel_string)
df_comments_final = df_comments_final.map(clean_excel_string)

if WRITER_ENGINE:
    with pd.ExcelWriter(acum_path_excel, engine=WRITER_ENGINE) as writer:
        df_posts_final.to_excel(writer, sheet_name="posts", index=False)
        df_comments_final.to_excel(writer, sheet_name="comentarios", index=False)

    with pd.ExcelWriter(flat_xlsx, engine=WRITER_ENGINE) as writer:
        # Flat = comentarios (filtrados) con variables del post
        df_comments_final.to_excel(writer, sheet_name="posts_comentarios", index=False)
else:
    print("ℹ️ Excel omitido por falta de motor. Mantuvimos CSVs.")

# ============== 🧾 Resumen ==============
print("\n✅ Resumen de la corrida (r/RepublicadeChile, filtro derecha)")
print(f"   • Nuevos posts en esta corrida (mencionan nombres):      {len(df_posts_new)}")
print(f"   • Nuevos comentarios en esta corrida (mencionan nombres): {len(df_comments_new)}")
print(f"   • Total posts acumulados:            {len(df_posts_final)}")
print(f"   • Total comentarios acumulados:      {len(df_comments_final)}")
print(f"💾 CSV posts:        {acum_posts_csv}")
print(f"💾 CSV comentarios:  {acum_comments_csv}")
if parquet_saved:
    print(f"📦 Parquet posts:    {acum_posts_parquet}")
    print(f"📦 Parquet comentarios: {acum_comments_parquet}")
if WRITER_ENGINE:
    print(f"📘 Excel (2 sheets): {acum_path_excel}")
    print(f"📘 Excel (flat 1 sheet): {flat_xlsx}")

print("Fin del scraping")
