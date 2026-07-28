create table site_capacities (
    site_id int primary key,
    capacity_mw int
);
copy site_capacities from '/data/site_capacities.csv' with (format csv, header);
