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

DROP PROCEDURE IF EXISTS get_corr;
DELIMITER //
CREATE PROCEDURE get_corr(IN x_col VARCHAR(64), IN y_col VARCHAR(64),
IN table_name VARCHAR(64), IN where_clause VARCHAR(999))
BEGIN
    SET @sql = CONCAT(
        'SELECT ',
        QUOTE(table_name), ' AS source_table, ',
        QUOTE(x_col), ' AS x_column, ',
        QUOTE(y_col), ' AS y_column, ',
        'COUNT(*) AS matched_rows, ',
        '(',
            '(AVG(', x_col, ' * ', y_col, ') - AVG(', x_col, ') * AVG(', y_col, ')) / ',
            'NULLIF(',
                'SQRT(AVG(', x_col, ' * ', x_col, ') - POW(AVG(', x_col, '), 2)) * ',
                'SQRT(AVG(', y_col, ' * ', y_col, ') - POW(AVG(', y_col, '), 2))',
            ', 0)',
        ') AS correlation ',
        'FROM ', table_name, ' ',
        'WHERE ', x_col, ' IS NOT NULL ',
        'AND ', y_col, ' IS NOT NULL ' , where_clause
    );
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

SELECT * FROM minimal_data_matched;

CALL get_corr('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', '');
CALL get_corr('pm25_atm_b', 'pm25_nowcast_value', 'minimal_data_matched', '');
CALL get_corr('pm25_cf_1_a', 'pm25_nowcast_value', 'minimal_data_matched', '');
CALL get_corr('pm25_cf_1_b', 'pm25_nowcast_value', 'minimal_data_matched', '');

CALL get_corr('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'AND dist_miles < 0.5');
CALL get_corr('pm25_atm_b', 'pm25_nowcast_value', 'minimal_data_matched', 'AND dist_miles < 0.5');
CALL get_corr('pm25_cf_1_a', 'pm25_nowcast_value', 'minimal_data_matched', 'AND dist_miles < 0.5');
CALL get_corr('pm25_cf_1_b', 'pm25_nowcast_value', 'minimal_data_matched', 'AND dist_miles < 0.5');

CALL get_corr('pm25_atm_a', 'pm25_nowcast_value', 'data_matched', ' AND pm25_atm_a < 202.1');
CALL get_corr('pm25_atm_b', 'pm25_nowcast_value', 'data_matched', 'AND pm25_atm_b < 202.1');
CALL get_corr('pm25_cf_1_a', 'pm25_nowcast_value', 'data_matched', 'AND pm25_cf_1_a < 202.1');
CALL get_corr('pm25_cf_1_b', 'pm25_nowcast_value', 'data_matched', 'AND pm25_cf_1_b < 202.1');

DROP PROCEDURE IF EXISTS get_mae;
DELIMITER //
CREATE PROCEDURE get_mae(IN x_col VARCHAR(64), IN y_col VARCHAR(64),
IN table_name VARCHAR(64)
)
BEGIN
    SET @sql = CONCAT(
        'SELECT ',
        QUOTE(table_name), ' AS source_table, ',
        QUOTE(x_col), ' AS x_column, ',
        QUOTE(y_col), ' AS y_column, ',
        'COUNT(*) AS matched_rows, ',
        'AVG(ABS(', x_col, ' - ', y_col, ')) AS mae ',
        'FROM ', table_name, ' ',
        'WHERE ', x_col, ' IS NOT NULL ',
        'AND ', y_col, ' IS NOT NULL'
    );
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END //
DELIMITER ;

CALL get_mae('pm25_atm_a', 'pm25_nowcast_value', 'data_matched');
CALL get_mae('pm25_atm_b', 'pm25_nowcast_value', 'data_matched');
CALL get_mae('pm25_cf_1_a', 'pm25_nowcast_value', 'data_matched');
CALL get_mae('pm25_cf_1_b', 'pm25_nowcast_value', 'data_matched');

CALL get_mae('pm25_atm_a', 'pm25_nowcast_value', 'data_matched');
CALL get_mae('pm25_atm_b', 'pm25_nowcast_value', 'data_matched');
CALL get_mae('pm25_cf_1_a', 'pm25_nowcast_value', 'data_matched');
CALL get_mae('pm25_cf_1_b', 'pm25_nowcast_value', 'data_matched');

SELECT MAX(pm25_atm_a) FROM temp_purpleair_cleaned_wo_outliers;
SELECT MAX(pm25_atm_b) FROM temp_purpleair_cleaned_wo_outliers;
SELECT MAX(pm25_cf_1_a) FROM temp_purpleair_cleaned_wo_outliers;
SELECT MAX(pm25_cf_1_b) FROM temp_purpleair_cleaned_wo_outliers;

SELECT MAX(pm25_nowcast_value) FROM airnow_sensor_data