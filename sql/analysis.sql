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
CREATE PROCEDURE correlation (IN x VARCHAR(64), IN y VARCHAR(64), 
IN which_table VARCHAR(64), IN where_clause VARCHAR(999))
BEGIN
	SET @corrquer = CONCAT(
        'SELECT 
        (AVG(', x, ' * ', y, ') - 
         AVG(', x, ') * AVG(', y, ')) /
        (
         NULLIF(
			(
				SQRT(AVG(',x,' * ',x,') - POW(AVG(',x,'), 2)) *
				SQRT(AVG(',y,' * ',y,') - POW(AVG(',y,'), 2))
			), 0
		)
        ) AS correlation_coefficient
        FROM ', which_table, ' ', where_clause
    );

    PREPARE getcorr FROM @corrquer;
    EXECUTE getcorr;
    DEALLOCATE PREPARE getcorr;
END //
DELIMITER ;

SELECT * FROM purpleair_sensor_data;

# Near perfect correlation for a->a and b->b conversions which is expected as a formula conversion,
# but both a/b comparisons have extremely small (~-0.0157) coefficients
CALL correlation('pm25_atm_a', 'pm25_atm_b', 'purpleair_sensor_data', '');
CALL correlation('pm25_atm_a', 'pm25_cf_1_a', 'purpleair_sensor_data', '');
CALL correlation('pm25_atm_a', 'pm25_cf_1_b', 'purpleair_sensor_data', '');
CALL correlation('pm25_atm_b', 'pm25_cf_1_a', 'purpleair_sensor_data', '');
CALL correlation('pm25_atm_b', 'pm25_cf_1_b', 'purpleair_sensor_data', '');
CALL correlation('pm25_cf_1_a', 'pm25_cf_1_b', 'purpleair_sensor_data', '');

# Find the max PM2.5 value in the AirNow dataset
SELECT MAX(pm25_nowcast_value) FROM airnow_sensor_data;

# Limit PurpleAir dataset to data that falls below the max value appearance in the AirNow dataset
CREATE OR REPLACE VIEW minimal_purpleair AS
SELECT * FROM purpleair_sensor_data WHERE pm25_atm_a <= 202.1 AND pm25_atm_b <= 202.1 AND
pm25_cf_1_a <= 202.1 AND pm25_cf_1_b <= 202.1;

CALL correlation('pm25_atm_a', 'pm25_atm_b', 'minimal_purpleair', '');
CALL correlation('pm25_atm_a', 'pm25_cf_1_a', 'minimal_purpleair', '');
CALL correlation('pm25_atm_a', 'pm25_cf_1_b', 'minimal_purpleair', '');
CALL correlation('pm25_atm_b', 'pm25_cf_1_a', 'minimal_purpleair', '');
CALL correlation('pm25_atm_b', 'pm25_cf_1_b', 'minimal_purpleair', '');
CALL correlation('pm25_cf_1_a', 'pm25_cf_1_b', 'minimal_purpleair', '');

SELECT *
FROM purpleair_sensor_data
WHERE (`pm25_atm_a` > 300) OR (`pm25_atm_b` > 300) OR (`pm25_cf_1_a` > 300) OR (`pm25_cf_1_b` > 300)
ORDER BY sensor_index, datetime_timestamp;

SELECT AVG(pm25_atm_a) FROM purpleair_sensor_data WHERE pm25_atm_a > 300
UNION ALL
SELECT AVG(pm25_atm_b) FROM purpleair_sensor_data WHERE pm25_atm_b > 300
UNION ALL
SELECT AVG(pm25_cf_1_a) FROM purpleair_sensor_data WHERE pm25_cf_1_a > 300
UNION ALL
SELECT AVG(pm25_cf_1_b) FROM purpleair_sensor_data WHERE pm25_cf_1_b > 300;

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
SELECT sensor_index, site_id, dist_miles
FROM
	(SELECT p.sensor_index, a.site_id,
	ROUND(haversine_miles(p.latitude, p.longitude, a.latitude, a.longitude),2) AS dist_miles,
    ROW_NUMBER() OVER(PARTITION BY p.sensor_index 
    ORDER BY haversine_miles(p.latitude, p.longitude, a.latitude, a.longitude) ASC) AS dist_rank
	FROM purpleair_sensors p
	CROSS JOIN airnow_sites a) o
WHERE dist_rank = 1;

# See how many PurpleAir sensors have their closest AirNow sensor under a certain distance in miles
SELECT
SUM(dist_miles <= 0.1) AS `Under 0.1`,
SUM(dist_miles <= 0.3) AS `Under 0.3`,
SUM(dist_miles <= 0.5) AS `Under 0.5`,
SUM(dist_miles <= 1.0) AS `Under 1.0`,
SUM(dist_miles <= 5.0) AS `Under 5.0`
FROM sensor_distances;

# Match corresponding rows from each data set based on the closest sensor
CREATE OR REPLACE VIEW data_matched AS
SELECT p.*, s.site_id, s.dist_miles, a.pm25_nowcast_value, a.pm25_raw_concentration
FROM purpleair_sensor_data p
JOIN sensor_distances s
ON p.sensor_index = s.sensor_index
JOIN airnow_sensor_data a
ON s.site_id = a.site_id AND p.datetime_timestamp = a.datetime_timestamp;

CREATE OR REPLACE VIEW minimal_data_matched AS
SELECT p.*, s.site_id, s.dist_miles, a.pm25_nowcast_value, a.pm25_raw_concentration
FROM purpleair_sensor_data p
JOIN sensor_distances s
ON p.sensor_index = s.sensor_index
JOIN airnow_sensor_data a
ON s.site_id = a.site_id AND p.datetime_timestamp = a.datetime_timestamp
WHERE pm25_atm_a <= 202.1 AND pm25_atm_b <= 202.1 AND
pm25_cf_1_a <= 202.1 AND pm25_cf_1_b <= 202.1;

# Get the % of rows in PurpleAir dataset that are greater than the max appearence in AirNow dataset
WITH max_airnow AS (
	SELECT MAX(pm25_raw_concentration) AS the_max FROM airnow_sensor_data
)
SELECT ROUND(SUM(CASE WHEN pm25_cf_1_b > max_airnow.the_max 
OR pm25_atm_a > max_airnow.the_max 
OR pm25_atm_b > max_airnow.the_max 
OR pm25_cf_1_b > max_airnow.the_max 
THEN 1 ELSE 0 END)/COUNT(*)*100.0,2) AS '%'
FROM purpleair_sensor_data CROSS JOIN max_airnow;

DROP PROCEDURE IF EXISTS get_correlation;
DELIMITER //
CREATE PROCEDURE get_correlation(IN purpleair_col VARCHAR(64), IN airnow_col VARCHAR(64),
IN table_name VARCHAR(64), IN where_clause VARCHAR(500))
BEGIN
    SET @sql = CONCAT(
        'SELECT CASE
            WHEN ', airnow_col, ' <= 5 THEN ''0–5''
            WHEN ', airnow_col, ' <= 10 THEN ''5–10''
            WHEN ', airnow_col, ' <= 25 THEN ''10–25''
            WHEN ', airnow_col, ' <= 50 THEN ''25–50''
            WHEN ', airnow_col, ' <= 100 THEN ''50–100''
            ELSE ''100+''
         END AS `range`,
         (
            AVG(', purpleair_col, ' * ', airnow_col, ')
            - AVG(', purpleair_col, ') * AVG(', airnow_col, ')
         )
         /
         NULLIF(
            SQRT(AVG(', purpleair_col, ' * ', purpleair_col, ') - POW(AVG(', purpleair_col, '), 2))
            *
            SQRT(AVG(', airnow_col, ' * ', airnow_col, ') - POW(AVG(', airnow_col, '), 2)),
            0
         ) AS correlation
         FROM ', table_name, ' '
    );
    IF where_clause IS NOT NULL AND where_clause != ''
    THEN SET @sql = CONCAT(@sql, ' WHERE ', where_clause);
    END IF;
    SET @sql = CONCAT(@sql, ' GROUP BY `range` ORDER BY MIN(', airnow_col, ')');
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END //
DELIMITER ;

# Get correlation coefficicient for all data
CALL get_corr('pm25_atm_a', 'pm25_nowcast_value', 'data_matched', '');
CALL get_corr('pm25_atm_b', 'pm25_nowcast_value', 'data_matched', '');
CALL get_corr('pm25_cf_1_a', 'pm25_nowcast_value', 'data_matched', '');
CALL get_corr('pm25_cf_1_b', 'pm25_nowcast_value', 'data_matched', '');

# Moderate/strong correlation for all data under 202.1 PM2.5 (~0.65)
CALL get_corr('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', '');
CALL get_corr('pm25_atm_b', 'pm25_nowcast_value', 'minimal_data_matched', '');
CALL get_corr('pm25_cf_1_a', 'pm25_nowcast_value', 'minimal_data_matched', '');
CALL get_corr('pm25_cf_1_a', 'pm25_nowcast_value', 'minimal_data_matched', '');

# Stronger correlation when limiting it to sensors within 1/10 of a mile
# R^2 value jumps from 0.36 to 0.49 (a 36% improvement)
# So 49% of the variation in PurpleAir readings is explained by AirNow readings
CALL get_corr('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'AND dist_miles <= 0.1');
CALL get_corr('pm25_atm_b', 'pm25_nowcast_value', 'minimal_data_matched', 'AND dist_miles <= 0.1');
CALL get_corr('pm25_cf_1_a', 'pm25_nowcast_value', 'minimal_data_matched', 'AND dist_miles <= 0.1');
CALL get_corr('pm25_cf_1_a', 'pm25_nowcast_value', 'minimal_data_matched', 'AND dist_miles <= 0.1');

# Similar / slightly greater correlation for sensors within 0.5 miles (likely due to greater
# sample size (approximately double) giving a more accurate sampling)
CALL get_corr('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'AND dist_miles <= 0.5');
CALL get_corr('pm25_atm_b', 'pm25_nowcast_value', 'minimal_data_matched', 'AND dist_miles <= 0.5');
CALL get_corr('pm25_cf_1_a', 'pm25_nowcast_value', 'minimal_data_matched', 'AND dist_miles <= 0.5');
CALL get_corr('pm25_cf_1_b', 'pm25_nowcast_value', 'minimal_data_matched', 'AND dist_miles <= 0.5');

DROP PROCEDURE IF EXISTS get_mae;
DELIMITER //
CREATE PROCEDURE get_mae(IN purpleair_col VARCHAR(64), IN airnow_col VARCHAR(64),
IN table_name VARCHAR(64), IN where_clause VARCHAR(500))
BEGIN
    SET @sql = CONCAT(
        'SELECT CASE
            WHEN ', airnow_col, ' <= 5 THEN ''0–5''
            WHEN ', airnow_col, ' <= 10 THEN ''5–10''
            WHEN ', airnow_col, ' <= 25 THEN ''10–25''
            WHEN ', airnow_col, ' <= 50 THEN ''25–50''
            WHEN ', airnow_col, ' <= 100 THEN ''50–100''
            ELSE ''100+''
         END AS `range`,
         AVG(ABS(', purpleair_col, ' - ', airnow_col, ')) AS mae
         FROM ', table_name, ' '
    );
    IF where_clause IS NOT NULL AND where_clause != ''
    THEN SET @sql = CONCAT(@sql, ' WHERE ', where_clause);
    END IF;
    SET @sql = CONCAT(@sql, ' GROUP BY `range` ORDER BY MIN(', airnow_col, ')');
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END //
DELIMITER ;

CALL get_mae('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles < 0.1');
CALL get_mae('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles < 0.5');
CALL get_mae('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles < 1.0');

CALL get_mae('pm25_cf_1_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles < 0.1');
CALL get_mae('pm25_cf_1_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles < 0.5');
CALL get_mae('pm25_cf_1_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles < 1.0');

# ATM and CF1 values are nearly identical at low thresholds, with CF1 making huge jumps in comparative
# readings above 25 ug/m^3
SELECT CASE
    WHEN pm25_nowcast_value <= 5 THEN '0–5'
    WHEN pm25_nowcast_value <= 10 THEN '5–10'
    WHEN pm25_nowcast_value <= 25 THEN '10–25'
    WHEN pm25_nowcast_value <= 50 THEN '25–50'
    WHEN pm25_nowcast_value <= 100 THEN '50–100'
    ELSE '100+'
  END AS `range`,
  AVG(pm25_cf_1_a - pm25_atm_a) AS avg_cf1_minus_atm, AVG(pm25_atm_a) AS avg_atm_a,
  AVG(pm25_cf_1_a) AS avg_cf1_a, AVG(pm25_nowcast_value) AS avg_airnow
FROM minimal_data_matched
WHERE dist_miles < 0.5
GROUP BY `range`
ORDER BY MIN(pm25_nowcast_value);

SELECT ROUND(100 * AVG(ABS(pm25_atm_a - pm25_nowcast_value) / NULLIF(pm25_nowcast_value, 0)),2) AS mape
FROM minimal_data_matched;

DROP PROCEDURE IF EXISTS get_bias;
DELIMITER //
CREATE PROCEDURE get_bias(IN purpleair_col VARCHAR(64), IN airnow_col VARCHAR(64),
IN table_name VARCHAR(64), IN where_clause VARCHAR(500))
BEGIN
    SET @sql = CONCAT(
        'SELECT CASE
            WHEN ', airnow_col, ' <= 5 THEN ''0–5''
            WHEN ', airnow_col, ' <= 10 THEN ''5–10''
            WHEN ', airnow_col, ' <= 25 THEN ''10–25''
            WHEN ', airnow_col, ' <= 50 THEN ''25–50''
            WHEN ', airnow_col, ' <= 100 THEN ''50–100''
            ELSE ''100+''
         END AS `range`,
         AVG(', purpleair_col, ' - ', airnow_col, ') AS bias
         FROM ', table_name, ' '
    );
    IF where_clause IS NOT NULL AND where_clause != ''
    THEN SET @sql = CONCAT(@sql, ' WHERE ', where_clause);
    END IF;
    SET @sql = CONCAT(@sql, ' GROUP BY `range` ORDER BY MIN(', airnow_col, ')');
	PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END //
DELIMITER ;

CALL get_bias('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.1');
CALL get_bias('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.5');
CALL get_bias('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 1.0');

CALL get_bias('pm25_cf_1_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.1');
CALL get_bias('pm25_cf_1_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.5');
CALL get_bias('pm25_cf_1_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 1.0');

SELECT CASE
    WHEN pm25_nowcast_value <= 5 THEN '0–5'
    WHEN pm25_nowcast_value <= 10 THEN '5–10'
    WHEN pm25_nowcast_value <= 25 THEN '10–25'
    WHEN pm25_nowcast_value <= 50 THEN '25–50'
	WHEN pm25_nowcast_value <= 100 THEN '50-100'
    ELSE '100+'
  END AS `range`,
AVG(pm25_cf_1_a - pm25_nowcast_value) AS bias
FROM minimal_data_matched
GROUP BY `range`
ORDER BY MIN(pm25_nowcast_value);

SELECT CASE
    WHEN pm25_nowcast_value <= 5 THEN '0–5'
    WHEN pm25_nowcast_value <= 10 THEN '5–10'
    WHEN pm25_nowcast_value <= 25 THEN '10–25'
    WHEN pm25_nowcast_value <= 50 THEN '25–50'
    WHEN pm25_nowcast_value <= 100 THEN '50-100'
    ELSE '100+' END AS `range`,
  AVG(ABS(pm25_atm_a - pm25_nowcast_value)) AS mae
FROM minimal_data_matched
GROUP BY `range`
ORDER BY MIN(pm25_nowcast_value);

SELECT COUNT(*) 
FROM minimal_data_matched
WHERE pm25_nowcast_value > 50;