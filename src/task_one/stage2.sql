--## Stage 2 - Supporting Multiple Sites
--The platform has now expanded to support multiple sites.
--Telemetry now includes a `site_id` field, and site capacities are stored in a separate table:

--`multi_site_measurements`
--| Column | Description |
--| --- | --- |
--| `timestamp` | Measurement timestamp |
--| `site_id` | Site identifier |
--| `active_power` | Measured active power (kW) |
--| `setpoint` | Requested active power (kW) |

--`site_capacities`
--| Column | Description |
--| --- | --- |
--| `site_id` | Site identifier |
--| `capacity_mw` | Installed site capacity (MW) |

--### Task
--Write the SQL to calculate the daily average reliabilities for each site.

select
    m.site_id,
    date_trunc('day', m."timestamp") as day,
    avg(1 - abs(m.active_power - m.setpoint) / (c.capacity_mw * 1000.0)) as avg_reliability
from multi_site_measurements m
join site_capacities c on c.site_id = m.site_id
group by m.site_id, date_trunc('day', m."timestamp")
order by m.site_id, day;
