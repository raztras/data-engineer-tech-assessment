--## Stage 1 - Calculate Daily Reliability

--The database `measurements` table contains telemetry data for a single site at 30-minute intervals.

--### Telemetry

--| Column | Description |
--| --- | --- |
--| `timestamp` | Measurement timestamp |
--| `active_power` | Measured active power (kW) |
--| `setpoint` | Requested active power (kW) |

--The Site Capacity is given as `100 MW`.
--
--### Task
--
--Write the SQL to calculate the daily average Active Power Reliability.

select
    date_trunc('day', "timestamp") as day,
    avg(1 - abs(active_power - setpoint) / 100000.0) as avg_reliability
from measurements
group by day
order by day;
