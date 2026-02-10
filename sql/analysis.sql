# Function to get the distance between PurpleAir and AirNow sensors in miles
DELIMITER $$
CREATE FUNCTION haversine_miles (
    lat1 DOUBLE, lon1 DOUBLE, lat2 DOUBLE, lon2 DOUBLE
)
RETURNS DOUBLE
DETERMINISTIC
BEGIN
    DECLARE earth_radius DOUBLE DEFAULT 3959;
    RETURN earth_radius * 2 * ASIN(SQRT(
        POW(SIN(RADIANS(lat2 - lat1) / 2), 2) +
        COS(RADIANS(lat1)) * COS(RADIANS(lat2)) *
        POW(SIN(RADIANS(lon2 - lon1) / 2), 2)
    ));
END$$
DELIMITER ;

# View that calculates distances between all sensors in each data set
CREATE OR REPLACE VIEW v_pa_airnow_distances AS
SELECT p.sensor_index, a.site_id,
haversine_miles(p.latitude, p.longitude, a.latitude, a.longitude) AS dist_miles
FROM purpleair_sensors p
CROSS JOIN airnow_sites a;

select * from v_pa_to_airnow_nearest;









# Check where PM2.5 values are 0
SELECT SUM(`pm2.5_atm_a` = 0) AS '0_pm2.5_atm_a', SUM(`pm2.5_atm_b` = 0) AS '0_pm2.5_atm_b',
SUM(`pm2.5_cf_1_a` = 0) AS '0_pm2.5_cf_1_a', SUM(`pm2.5_cf_1_b` = 0) AS '0_pm2.5_cf_1_b'
FROM staging_purpleair_sensor_data;

# Check where PM2.5 values are ALL 0 (possibly a reboot value, faulty, etc.)
SELECT sensor_index,
SUM(`pm2.5_atm_a` = 0 AND `pm2.5_atm_b` = 0 AND `pm2.5_cf_1_a` = 0 AND `pm2.5_cf_1_b` = 0) AS all_empty,
COUNT(*) AS total
FROM staging_purpleair_sensor_data
GROUP BY sensor_index
HAVING all_empty > 0
ORDER BY all_empty DESC;

# All sensor PM2.5 values at least 0
SELECT *
FROM staging_purpleair_sensor_data
WHERE `pm2.5_atm_a` < 0 OR `pm2.5_atm_b` < 0 OR `pm2.5_cf_1_a` < 0 OR `pm2.5_cf_1_b` < 0;

# Verified greatest PM2.5 value in the AirNow dataset is
SELECT COUNT(*)
FROM staging_purpleair_sensor_data
WHERE `pm2.5_atm_a` > 300  OR `pm2.5_atm_b` > 300 OR `pm2.5_cf_1_a` > 300 OR `pm2.5_cf_1_b` > 300;

select avg(`pm2.5_atm_a`), avg(`pm2.5_atm_b`), avg(`pm2.5_cf_1_a`), avg(`pm2.5_cf_1_b`)
from staging_purpleair_sensor_data
WHERE `pm2.5_atm_a` < 300  AND `pm2.5_atm_b` < 300 AND `pm2.5_cf_1_a` < 300 AND `pm2.5_cf_1_b` < 300;

select *
from staging_purpleair_sensor_data
WHERE (`pm2.5_atm_a` < 150 AND `pm2.5_atm_a` > 100)
  OR (`pm2.5_atm_b` < 150 AND `pm2.5_atm_b` > 100)
  OR (`pm2.5_cf_1_a` < 150 AND `pm2.5_cf_1_a` > 100) 
  OR (`pm2.5_cf_1_b` < 150 AND `pm2.5_cf_1_b` > 100)
ORDER BY sensor_index, time_stamp;

# Only contains 126 more rows than previous query (64658 above and 64784 here)
SELECT *
FROM staging_purpleair_sensor_data
WHERE ((`pm2.5_atm_a` < 300 AND `pm2.5_atm_b` > 300) OR (`pm2.5_atm_b` < 300 AND `pm2.5_atm_a` > 300))
OR ((`pm2.5_cf_1_a` < 300 AND `pm2.5_cf_1_b` > 300) OR (`pm2.5_cf_1_b` < 300 AND `pm2.5_cf_1_a` > 300));