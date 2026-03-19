# Function to get the distance between PurpleAir and AirNow sensors in miles
DROP FUNCTION IF EXISTS haversine_miles;
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
CREATE OR REPLACE VIEW sensor_distances AS
SELECT p.sensor_index, a.site_id,
ROUND(haversine_miles(p.latitude, p.longitude, a.latitude, a.longitude),2) AS dist_miles
FROM purpleair_sensors p
CROSS JOIN airnow_sites a;

# Procedure to group each PM2.5 values in their corresponding AQI group
DROP PROCEDURE IF EXISTS pm25_averages;
DELIMITER //
CREATE PROCEDURE pm25_averages (IN pm25col VARCHAR(64), IN which_table VARCHAR(64))
BEGIN
	SET @colquer = CONCAT('
    SELECT AQI, COUNT(*) AS row_count,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
	FROM (
		SELECT CASE WHEN ', pm25col, ' <= 50 THEN "Good"
		WHEN ', pm25col, ' BETWEEN 50.1 AND 100 THEN "Moderate"
		WHEN ', pm25col, ' BETWEEN 100.1 AND 150 THEN "Unhealthy for Sensitive Groups"
		WHEN ', pm25col, ' BETWEEN 150.1 AND 200 THEN "Unhealthy"
		WHEN ', pm25col, ' BETWEEN 200.1 AND 300 THEN "Very Unhealthy"
		ELSE "Hazardous" END AS AQI
		FROM ', which_table,'
		) i
	GROUP BY AQI
    ORDER BY FIELD(AQI, "Good","Moderate","Unhealthy for Sensitive Groups",
    "Unhealthy","Very Unhealthy","Hazardous"
)
    ');
	PREPARE getavg FROM @colquer;
    EXECUTE getavg;
    DEALLOCATE PREPARE getavg;
END //
DELIMITER ;

# All column categories in both datasets show that vast majority of their observations
# are in the "Good" AQI need for concern category (all 97%+)
# A noticable difference in the PurpleAir and AirNow percentages is that the hazardous
# category (the most extreme) is the second most populated in all columns for
# PurpleAir, with the other ascendingly extreme categories tapering off in volume 
CALL pm25_averages('pm25_atm_a', 'purpleair_sensor_data');
CALL pm25_averages('pm25_atm_b', 'purpleair_sensor_data');
CALL pm25_averages('pm25_cf_1_a', 'purpleair_sensor_data');
CALL pm25_averages('pm25_cf_1_b', 'purpleair_sensor_data');
CALL pm25_averages('pm25_nowcast_value', 'airnow_sensor_data');
CALL pm25_averages('pm25_raw_concentration', 'airnow_sensor_data');

DROP PROCEDURE IF EXISTS correlation;
DELIMITER //
CREATE PROCEDURE correlation (IN x VARCHAR(11), IN y VARCHAR(11), 
IN which_table VARCHAR(64))
BEGIN
	SET @corrquer = CONCAT(
        'SELECT ', x, ', ', y, ',
        (AVG(', x, ' * ', y, ') - 
         AVG(', x, ') * AVG(', y, ')) /
        (
         SQRT(AVG(', x, ' * ', x, ') - POW(AVG(', x, '), 2)) *
         SQRT(AVG(', y, ' * ', y, ') - POW(AVG(', y, '), 2))
        ) AS correlation_coefficient
        FROM ', which_table
    );

    PREPARE getcorr FROM @corrquer;
    EXECUTE getcorr;
    DEALLOCATE PREPARE getcorr;
END //
DELIMITER ;

CALL correlation('pm25_atm_a', 'pm25_atm_b', 'purpleair_sensor_data');

select * from purpleair_sensor_data limit 10;






select * from airnow_sites;

select * from airnow_sensor_data limit 50;




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