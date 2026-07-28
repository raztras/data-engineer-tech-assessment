create table multi_site_measurements (
    timestamp timestamp,
    site_id int,
    primary key (timestamp, site_id),
    active_power int,
    setpoint int
);
copy multi_site_measurements from '/data/multi_site_measurements.csv' with (format csv, header);
