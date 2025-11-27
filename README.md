
# Reddit Project (Simple)

Two folders: **scripts/** and **data/** (with `raw/`, `proc_data/`, `insights/` and a reorganized `trends/` subtree).
One command appends everything into a single flat file with posts + comments.

## Run

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

cp .env.example .env  # add your keys
python scripts/scrape_and_append.py --subs chile RepublicadeChile --limit 100
```

Outputs:
- `data/raw/snapshot_YYYYMMDD-HHMMSS.csv`  (raw posts-only snapshot)
- `data/raw/reddit_posts*.parquet` and `data/raw/reddit_comentarios*.parquet` (binary backups of the scraped Reddit tables, including `_derecha` variants)
- `data/proc_data/master_reddit.csv`        (flat master, post+comment)
- `data/proc_data/master_reddit.xlsx`       (same, one sheet)
- `data/insights/daily_posts_from_raw.png`  (key visualizations)
- `data/trends/series/trends_candidatos_daily.csv` (combined series used across scripts)
- `data/trends/series/trends_candidatos_daily.parquet` (serialized backup of the same series)
- `data/trends/figures/fig_comparativo_ma7.png` and `fig_small_multiples_90d.png` (prebuilt trend plots)
