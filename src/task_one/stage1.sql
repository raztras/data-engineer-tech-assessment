-- Task 1, Stage 1: daily average Active Power Reliability for a single site.
-- Site Capacity = 100 MW = 100,000 kW (active_power/setpoint are in kW).

select
    date_trunc('day', "timestamp") as day,
    avg(1 - abs(active_power - setpoint) / 100000.0) as avg_reliability
from measurements
group by 1
order by 1;
