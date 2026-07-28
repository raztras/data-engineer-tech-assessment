select
    date_trunc('day', "timestamp") as day,
    avg(1 - abs(active_power - setpoint) / 100000.0) as avg_reliability
from measurements
group by 1
order by 1;
