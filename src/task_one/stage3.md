# Stage 3 — Managing Capacity Changes

## The problem with the existing configuration

'site_capacities' currently stores one row per site: a single, current
'capacity_mw'. If a site is augmented (its MW capacity increased), overwriting
that row would silently apply the *new* capacity to *historical* measurements
too, corrupting every past reliability calculation for that site.

## Data model change

Make 'site_capacities' effective-dated instead of "current state only" — this
is the standard slowly-changing-dimension (SCD Type 2) pattern, and a natural
fit here since augmentations are rare (as per the task, 'no more than once every
couple of years'):

```sql
create table site_capacities (
    site_id         integer   not null,
    capacity_mw     numeric   not null,
    effective_from  timestamp not null,
    effective_to    timestamp,            -- null = currently in effect
    primary key (site_id, effective_from)
);
```

Each row represents one capacity value and the window of time it was valid
for. A site with no augmentations has exactly one row ('effective_to' null).
When a site is augmented:

1. Update the existing 'current' row: set its 'effective_to' to the moment
   the augmentation took effect.
2. Insert a new row for the new capacity, with 'effective_from' set to that
   same moment and 'effective_to' left 'null'.

This preserves every historical capacity value intact and auditable, rather than
a complete overwrite.

One risk worth flagging: closing out the old row and opening the new one are
two separate statements. If someone only runs one of them, or runs them in
the wrong order, we'd end up with two capacity values overlapping in time —
and that would silently corrupt the reliability numbers for that period,
which is exactly the bug we're trying to fix in the first place.

Given how rare and deliberate this change is — the task says once every
couple of years at most — I don't think this needs heavyweight database
machinery to solve. The simplest fix is to stop letting anyone write to
'site_capacities' directly, and instead put both steps behind a single
stored procedure: given a site, its new capacity, and the date it takes
effect, the procedure closes out that site's currently active row and opens
the new one in a single atomic operation. That becomes the only sanctioned
way to record a capacity change.

## Query logic change

The Stage 2 query joined 'multi_site_measurements' to 'site_capacities' on
'site_id' alone — a straightforward equality join, since each site only ever
had one capacity value to match against.

With capacity now effective-dated, the join needs a second condition: not
just "same site" but "this measurement's timestamp falls within this
capacity row's validity window." In practice that means adding a range check
against 'effective_from'/'effective_to' alongside the existing 'site_id'
match, so each measurement gets matched to exactly one capacity row — whichever
one was in effect at that exact moment — rather than potentially matching
several historical rows for the same site.

This is sometimes called a temporal or "as-of" join: instead of joining on
equality, you're joining on "which version of this record was active at this
point in time." Everything downstream of the join — the 'abs()' deviation
calculation, the daily 'avg()', the 'group by' — stays exactly the same as
Stage 2. Only the join condition changes.

## Why this handles the edge cases correctly

- Mid-day augmentation: each measurement joins to whichever capacity was
  valid at its own timestamp, so the daily average naturally blends both
  capacities in proportion — no special-casing needed.
- Backfilling: a one-time migration — set 'effective_from' to each site's
  data start date and 'effective_to' to 'null'.

Example: site 1 is augmented from 100 MW to 120 MW at 14:00 on 2028-03-01.
'site_capacities' now has two rows for that site:

| site_id | capacity_mw | effective_from      | effective_to        |
|---------|-------------|---------------------|---------------------|
| 1       | 100         | 2020-01-01 00:00:00 | 2028-03-01 14:00:00 |
| 1       | 120         | 2028-03-01 14:00:00 | null                |

That day's measurements join to whichever row covers their timestamp:

| timestamp           | active_power | setpoint | matched capacity_mw |
|---------------------|--------------|----------|---------------------|
| 2028-03-01 08:00:00 | 98,500       | 98,000   | 100                 |
| 2028-03-01 12:00:00 | 99,200       | 99,000   | 100                 |
| 2028-03-01 16:00:00 | 118,000      | 119,000  | 120                 |
| 2028-03-01 20:00:00 | 117,500      | 118,000  | 120                 |

The morning readings are scored against 100 MW, the afternoon readings
against 120 MW, and the daily 'avg()' blends both automatically.
