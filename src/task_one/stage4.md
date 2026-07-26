# Stage 4 — Scaling

## The problem

Years of history, tens of sites, higher-frequency readings, more metrics per
reading. A plain query against the raw table now scans a large and growing
amount of data for even a simple question — the query pattern hasn't
changed, but the data behind it has.

The recommendations below are written with Statera's actual stack in mind —
Snowflake and Databricks — rather than generic or hypothetical tooling.

## Cluster the data by time and site

Snowflake doesn't need manual partitioning the way a traditional database
does — it automatically breaks tables into micro-partitions and tracks
min/max metadata per column on each one. As long as data loads roughly in
time order (which telemetry naturally does), a query filtering by date range
already skips most irrelevant partitions with no setup required.

At this scale it's worth being deliberate about it anyway: defining an
explicit clustering key on `(site_id, timestamp)` — the two columns nearly
every query filters or groups by — keeps Snowflake actively maintaining
partition layout around that access pattern as new data lands, rather than
relying purely on load order. That costs ongoing background compute
(re-clustering credits), which is worth it here because the access pattern
is consistent and the table is large enough for pruning to actually matter.

One trap to watch for: the min/max metadata is held against the raw column,
so wrapping the timestamp in a function inside a `WHERE` clause stops
Snowflake matching the filter to that metadata and it falls back to scanning
everything. The query still returns the right answer — it just costs far
more to get it. Keep filters as plain range comparisons on the raw column,
and save the transformations for `SELECT`/`GROUP BY`.

## Precompute the aggregates people actually query

Dashboards want daily/hourly trends, not raw readings. Define those rollups
as Snowflake Dynamic Tables (or materialized views) — declarative,
incrementally refreshed as new base data arrives — so a dashboard query hits
a small pre-summarized table instead of aggregating raw telemetry every
time. Heavier transformation logic that's impractical in plain SQL can live
in Databricks instead, writing its output back into Snowflake as the same
kind of rollup table.

Raw telemetry lands in Snowflake first, and the transformation work on the
Databricks side follows a medallion architecture, implemented as a Delta
Live Tables pipeline: DLT ingests the raw landing table as-is into a Bronze
layer, cleans and conforms it (deduplicated, typed, joined against site
metadata) into a Silver layer — with DLT's built-in data quality
"expectations" catching bad rows before they propagate — and computes the
daily/hourly reliability rollups as a Gold layer, which is written back into
Snowflake as the curated serving layer. DLT manages the dependency graph
between these layers automatically, so a change upstream correctly triggers
recomputation downstream without the pipeline order having to be hand-wired.
Each layer still acts as a checkpoint: if a rollup turns out wrong, it can be
recomputed from Silver without re-ingesting or re-cleaning raw telemetry
from scratch.

Because the raw landing table lives in Snowflake, feeding this pipeline
incrementally is a change-tracking problem rather than a full-reprocessing
one: Snowflake Streams (Snowflake's native change-tracking mechanism) on
that landing table tells DLT exactly which rows have arrived or changed
since the last run, and DLT's own incremental processing model (built on
Structured Streaming under the hood) means each run only touches that new
data instead of an expensive full reprocess.

If the rollups ever need to be fresher than a scheduled run allows, the same
DLT pipeline can run in continuous mode instead of triggered mode — reading
new data as it lands and keeping Snowflake up to date continuously rather
than on a fixed interval. Daily reliability rollups don't need that though;
triggered/scheduled is the simpler, cheaper default, and continuous mode is
only worth reaching for if a future requirement genuinely needs sub-hour
freshness.

## Size compute independently of storage

Snowflake separates storage from compute, so recent vs. historical doesn't
need two different databases — it can mean two differently-sized virtual
warehouses pointing at the same underlying tables:

|               | Recent / operational                           | Historical / analytical                            |
|---------------|------------------------------------------------|----------------------------------------------------|
| Storage       | Snowflake                                      | Snowflake                                          |
| Optimized for | Low-latency via a small/always-on warehouse    | Cheap bulk scans via a larger, on-demand warehouse |
| Compute       | Snowflake (small warehouse)                    | Databricks (transform) → Snowflake (serve/query)   |

A small warehouse serving frequent, low-latency queries against recent data
costs relatively little to keep running. A much larger warehouse for
infrequent historical bulk scans only needs to spin up on demand and
auto-suspend when idle, so it isn't costing anything the rest of the time.
Same underlying data throughout — the split is in how compute is
provisioned against it, not in where the data physically lives.

## Rethink the schema as more metrics get added

Avoid both extremes: endless new columns (mostly-null once not every site
reports every metric) and a fully generic key-value metrics table (flexible,
but every query becomes a pivot/join). Keep fixed columns for the metrics
every site always reports, and only add a column once a new metric proves
genuinely universal — not the moment it first appears anywhere.
