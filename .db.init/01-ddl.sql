create table measurements (
    timestamp timestamp primary key,
    active_power int,
    setpoint int
);
copy measurements from '/data/measurements.csv' with (format csv, header);
