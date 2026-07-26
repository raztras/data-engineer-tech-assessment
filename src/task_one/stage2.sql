-- Task 1, Stage 2: daily average Active Power Reliability, per site.

select
    m.site_id,
    date_trunc('day', m."timestamp") as day,
    avg(1 - abs(m.active_power - m.setpoint) / (c.capacity_mw * 1000)) as avg_reliability
from multi_site_measurements m
join site_capacities c on c.site_id = m.site_id
group by m.site_id, date_trunc('day', m."timestamp")
order by m.site_id, day;
