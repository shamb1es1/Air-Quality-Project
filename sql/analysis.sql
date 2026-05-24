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

# Procedure for calculating correlation between columns
DROP PROCEDURE IF EXISTS get_correlation;
DELIMITER //
CREATE PROCEDURE get_correlation(IN x_col VARCHAR(64), IN y_col VARCHAR(64),
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
        'FROM ', table_name, ' ');
        IF where_clause IS NOT NULL AND where_clause != '' THEN
		SET @sql = CONCAT(@sql, ' WHERE ', where_clause);
		END IF;
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END //
DELIMITER ;

# Near perfect correlation for a->a and b->b conversions which is expected as a formula conversion,
# but both a/b comparisons have extremely small (~-0.0157) coefficients
CALL get_correlation('pm25_atm_a', 'pm25_atm_b', 'purpleair_sensor_data', '');
CALL get_correlation('pm25_atm_a', 'pm25_atm_b', 'purpleair_sensor_data', '');
CALL get_correlation('pm25_atm_a', 'pm25_cf_1_a', 'purpleair_sensor_data', '');
CALL get_correlation('pm25_atm_a', 'pm25_cf_1_b', 'purpleair_sensor_data', '');
CALL get_correlation('pm25_atm_b', 'pm25_cf_1_a', 'purpleair_sensor_data', '');
CALL get_correlation('pm25_atm_b', 'pm25_cf_1_b', 'purpleair_sensor_data', '');
CALL get_correlation('pm25_cf_1_a', 'pm25_cf_1_b', 'purpleair_sensor_data', '');

# Find the max PM2.5 value in the AirNow dataset (202.1)
SELECT MAX(pm25_nowcast_value) FROM airnow_sensor_data;

# Limit PurpleAir dataset to data that falls below the max value appearance in the AirNow dataset
CREATE OR REPLACE VIEW minimal_purpleair AS
SELECT * FROM purpleair_sensor_data WHERE pm25_atm_a <= 202.1 AND pm25_atm_b <= 202.1 AND
pm25_cf_1_a <= 202.1 AND pm25_cf_1_b <= 202.1;

CALL get_correlation('pm25_atm_a', 'pm25_atm_b', 'minimal_purpleair', '');
CALL get_correlation('pm25_atm_a', 'pm25_cf_1_a', 'minimal_purpleair', '');
CALL get_correlation('pm25_atm_a', 'pm25_cf_1_b', 'minimal_purpleair', '');
CALL get_correlation('pm25_atm_b', 'pm25_cf_1_a', 'minimal_purpleair', '');
CALL get_correlation('pm25_atm_b', 'pm25_cf_1_b', 'minimal_purpleair', '');
CALL get_correlation('pm25_cf_1_a', 'pm25_cf_1_b', 'minimal_purpleair', '');

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

# Calculates distances between all sensors in each data set
# Performs cross join to get all distances as some timestamps in PurpleAir dataset don't exist at
# the same time at the site of their closest match
DROP TABLE IF EXISTS sensor_distances;
CREATE TABLE sensor_distances AS
SELECT sensor_index, site_id, dist_miles, dist_rank
FROM (
  SELECT p.sensor_index, a.site_id, ROUND(haversine_miles(p.latitude, p.longitude, a.latitude, 
  a.longitude), 2) AS dist_miles, ROW_NUMBER() OVER (PARTITION BY p.sensor_index ORDER BY 
  haversine_miles(p.latitude, p.longitude, a.latitude, a.longitude)) AS dist_rank
  FROM purpleair_sensors p
  CROSS JOIN airnow_sites a
) ranked
WHERE dist_miles <= 5.00;

# Indexes for sensor_distances
CALL drop_index_if_exists('sensor_distances', 'idx_ssd_sensor_site');
CALL drop_index_if_exists('sensor_distances', 'idx_ssd_sensor_dist');
CALL drop_index_if_exists('sensor_distances', 'idx_ssd_site');
CALL drop_index_if_exists('sensor_distances', 'idx_ssd_site_sensor_dist');
CALL drop_index_if_exists('sensor_distances', 'idx_ssd_sensor_site_dist');
CREATE INDEX idx_ssd_sensor_site
ON sensor_distances(sensor_index, site_id);
CREATE INDEX idx_ssd_sensor_dist
ON sensor_distances(sensor_index, dist_miles);
CREATE INDEX idx_ssd_site
ON sensor_distances(site_id);
CREATE INDEX idx_ssd_site_sensor_dist
ON sensor_distances(site_id, sensor_index, dist_miles);
CREATE INDEX idx_ssd_sensor_site_dist
ON sensor_distances(sensor_index, site_id, dist_miles);

# Indexes for purpleair_sensor_data and airnow_sensor_data
CALL drop_index_if_exists('purpleair_sensor_data', 'idx_purpleair_sensor_time');
CALL drop_index_if_exists('purpleair_sensor_data', 'idx_purpleair_time');
CALL drop_index_if_exists('airnow_sensor_data', 'idx_airnow_time_site');
CALL drop_index_if_exists('airnow_sensor_data', 'idx_airnow_site_time');
CREATE INDEX idx_purpleair_sensor_time
ON purpleair_sensor_data(sensor_index, datetime_timestamp);
CREATE INDEX idx_purpleair_time
ON purpleair_sensor_data(datetime_timestamp);
CREATE INDEX idx_airnow_time_site
ON airnow_sensor_data(datetime_timestamp, site_id);
CREATE INDEX idx_airnow_site_time
ON airnow_sensor_data(site_id, datetime_timestamp);

# Match PurpleAir rows to their matching AirNow rows based on their closest site (not all will be
# matched)
DROP TABLE IF EXISTS data_matched;
CREATE TABLE data_matched AS
SELECT p.sensor_index, d.site_id, d.dist_miles, p.datetime_timestamp, p.humidity, p.temperature,
p.pm25_atm_a, p.pm25_atm_b, p.pm25_cf_1_a, p.pm25_cf_1_b, a.pm25_nowcast_value, a.pm25_raw_concentration
FROM purpleair_sensor_data p
JOIN sensor_distances d
ON p.sensor_index = d.sensor_index
JOIN airnow_sensor_data a
ON a.site_id = d.site_id AND a.datetime_timestamp = p.datetime_timestamp;

# Only look at data below the max value found in AirNow dataset
DROP TABLE IF EXISTS minimal_data_matched;
CREATE TABLE minimal_data_matched AS
SELECT *
FROM data_matched
WHERE pm25_atm_a <= 202.1 AND pm25_atm_b <= 202.1 AND pm25_cf_1_a <= 202.1 AND pm25_cf_1_b <= 202.1;

# See how many PurpleAir sensors have their closest AirNow sensor under a certain distance in miles
SELECT
SUM(dist_miles <= 0.1) AS `Under 0.1`,
SUM(dist_miles <= 0.3) AS `Under 0.3`,
SUM(dist_miles <= 0.5) AS `Under 0.5`,
SUM(dist_miles <= 1.0) AS `Under 1.0`,
SUM(dist_miles <= 5.0) AS `Under 5.0`
FROM sensor_distances
WHERE dist_rank = 1;

# Get the % of rows in PurpleAir dataset that are greater than the max appearence in AirNow dataset
# That being 3.44%
WITH max_airnow AS (
	SELECT MAX(pm25_raw_concentration) AS the_max FROM airnow_sensor_data
)
SELECT ROUND(SUM(CASE WHEN pm25_cf_1_b > max_airnow.the_max 
OR pm25_atm_a > max_airnow.the_max 
OR pm25_atm_b > max_airnow.the_max 
OR pm25_cf_1_b > max_airnow.the_max 
THEN 1 ELSE 0 END)/COUNT(*)*100.0,2) AS '%'
FROM purpleair_sensor_data CROSS JOIN max_airnow;

# Get correlation coefficicient for all data
# Essentially no correlation when allowing data above the 202.1 mark (heavy skewing by the 3.44% of 
# rows that follow above it
CALL get_correlation('pm25_atm_a', 'pm25_nowcast_value', 'data_matched', '');
CALL get_correlation('pm25_atm_b', 'pm25_nowcast_value', 'data_matched', '');
CALL get_correlation('pm25_cf_1_a', 'pm25_nowcast_value', 'data_matched', '');
CALL get_correlation('pm25_cf_1_b', 'pm25_nowcast_value', 'data_matched', '');

select * from data_matched;

# Strong correlation for all data under 202.1 PM2.5 (~0.64) and having sensors within 0.1 miles of each other
CALL get_correlation('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.1');
CALL get_correlation('pm25_atm_b', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.1');
CALL get_correlation('pm25_cf_1_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.1');
CALL get_correlation('pm25_cf_1_b', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.1');

SELECT p.*
FROM purpleair_sensor_data p
LEFT JOIN (
    SELECT DISTINCT sensor_index, datetime_timestamp
    FROM data_matched
) d
ON p.sensor_index = d.sensor_index
AND p.datetime_timestamp = d.datetime_timestamp
WHERE d.sensor_index IS NULL;

# Similar correlation for sensors within 0.5 miles
CALL get_correlation('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.5');
CALL get_correlation('pm25_atm_b', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.5');
CALL get_correlation('pm25_cf_1_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.5');
CALL get_correlation('pm25_cf_1_b', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.5');

# ATM and CF1 values are nearly identical at low thresholds, with CF1 making huge jumps in comparative
# readings above 25 ug/m^3
# The ATM column is the one generally recommended to look at for indoor sensors (proprietary
# formula), so henceforth this is the one that will be looked at
SELECT CASE
    WHEN pm25_nowcast_value <= 5 THEN '0–5'
    WHEN pm25_nowcast_value <= 10 THEN '5–10'
    WHEN pm25_nowcast_value <= 25 THEN '10–25'
    WHEN pm25_nowcast_value <= 50 THEN '25–50'
    WHEN pm25_nowcast_value <= 100 THEN '50–100'
    ELSE '100+'
  END AS `range`,
  AVG(pm25_cf_1_a - pm25_atm_a) AS avg_cf1_a_minus_atm_a, AVG(pm25_atm_a) AS avg_atm_a,
  AVG(pm25_cf_1_a) AS avg_cf1_a, AVG(pm25_cf_1_b - pm25_atm_b) AS avg_cf1_b_minus_atm_b,
  AVG(pm25_atm_b) AS avg_atm_b, AVG(pm25_nowcast_value) AS avg_airnow
FROM minimal_data_matched
WHERE dist_miles < 0.5
GROUP BY `range`
ORDER BY MIN(pm25_nowcast_value);

# Procedure for calculating MAE between columns
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

# Increased MAE as readings rise
CALL get_mae('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.1');
CALL get_mae('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.5');
CALL get_mae('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 1.0');
CALL get_mae('pm25_atm_b', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.1');
CALL get_mae('pm25_atm_b', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.5');
CALL get_mae('pm25_atm_b', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles < 1.0');

# Greater error between sensors as readings increase
CALL get_mae('pm25_atm_a', 'pm25_atm_b', 'minimal_data_matched', 'dist_miles < 0.1');
CALL get_mae('pm25_atm_a', 'pm25_atm_b', 'minimal_data_matched', 'dist_miles < 0.5');
CALL get_mae('pm25_atm_a', 'pm25_atm_b', 'minimal_data_matched', 'dist_miles < 1.0');


# Procedure for calculating bias between columns
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

# In small to moderate distance concentrations, PurpleAir overestimates PM2.5 values, and
# underestimates them at larger ones
CALL get_bias('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.1');
CALL get_bias('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.5');
CALL get_bias('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 1.0');
CALL get_bias('pm25_atm_b', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.1');
CALL get_bias('pm25_atm_b', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.5');
CALL get_bias('pm25_atm_b', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 1.0');

# Channel A has slight tendency to overestimate at lower concentrations, and begins to underestimate as
# concentrations rise
CALL get_bias('pm25_atm_a', 'pm25_atm_b', 'minimal_data_matched', 'dist_miles <= 0.1');
CALL get_bias('pm25_atm_a', 'pm25_atm_b', 'minimal_data_matched', 'dist_miles <= 0.5');
CALL get_bias('pm25_atm_a', 'pm25_atm_b', 'minimal_data_matched', 'dist_miles <= 1.0');

# Symmetric percent difference between PM2.5 readings
DROP PROCEDURE IF EXISTS get_symmetric_pct_diff;
DELIMITER //
CREATE PROCEDURE get_symmetric_pct_diff(IN purpleair_col VARCHAR(64), IN airnow_col VARCHAR(64),
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
         AVG(
             100 * ABS(', purpleair_col, ' - ', airnow_col, ') /
             NULLIF((', purpleair_col, ' + ', airnow_col, ') / 2, 0)
         ) AS symmetric_pct_diff
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

# Relative error highest at low PM2.5 values due to the sensitivity of % based calculations, especially
# with MAE showing larger variation as values increase
CALL get_symmetric_pct_diff('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.1');
CALL get_symmetric_pct_diff('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.5');
CALL get_symmetric_pct_diff('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 1.0');
CALL get_symmetric_pct_diff('pm25_atm_b', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.1');
CALL get_symmetric_pct_diff('pm25_atm_b', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.5');
CALL get_symmetric_pct_diff('pm25_atm_b', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 1.0');
# Weighted percent difference between PM2.5 readings
DROP PROCEDURE IF EXISTS get_weighted_pct_error;
DELIMITER //
CREATE PROCEDURE get_weighted_pct_error(
IN purpleair_col VARCHAR(64), IN airnow_col VARCHAR(64), IN table_name VARCHAR(64), 
IN where_clause VARCHAR(500))
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
         100 * SUM(ABS(', purpleair_col, ' - ', airnow_col, ')) /
         NULLIF(SUM(', airnow_col, '), 0) AS weighted_pct_error
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


CALL get_weighted_pct_error('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.1');
CALL get_weighted_pct_error('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.5');
CALL get_weighted_pct_error('pm25_atm_a', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 1.0');
CALL get_weighted_pct_error('pm25_atm_b', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.1');
CALL get_weighted_pct_error('pm25_atm_b', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.5');
CALL get_weighted_pct_error('pm25_atm_b', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 1.0');

CALL get_correlation('humidity', 'pm25_nowcast_value', 'minimal_data_matched', '');
CALL get_correlation('humidity', 'pm25_atm_a', 'minimal_data_matched', 'dist_miles <= 0.1');
CALL get_correlation('humidity', 'pm25_atm_b', 'minimal_data_matched', 'dist_miles <= 0.1');
CALL get_correlation('temperature', 'pm25_atm_a', 'minimal_data_matched', 'dist_miles <= 0.5');

CREATE OR REPLACE VIEW minimal_data_matched_error AS
SELECT *,
       pm25_atm_a - pm25_nowcast_value AS atm_a_error,
       pm25_atm_b - pm25_nowcast_value AS atm_b_error
FROM minimal_data_matched;

CREATE OR REPLACE VIEW minimal_data_matched_abs_error AS
SELECT *,
       ABS(pm25_atm_a - pm25_nowcast_value) AS atm_a_abs_error,
       ABS(pm25_atm_b - pm25_nowcast_value) AS atm_b_abs_error
FROM minimal_data_matched;

# While we must rely on PurpleAir for these readings, there is a slightly stronger correlation for
# humidity to both reading error (A=0.26,B=0.20) and absolute error (A=0.24,B=0.19) compared to
# humidity and AirNow readings (0.14)
# Suggesting humidity might introduce a slight bias in the PurpleAir dataset to overestimate the PM2.5
# readings as opposed to what it would otherwise read at lower humidities 
CALL get_correlation('humidity', 'pm25_nowcast_value', 'minimal_data_matched', 'dist_miles <= 0.1');
CALL get_correlation('humidity', 'pm25_atm_a', 'minimal_data_matched', 'dist_miles <= 0.1');
CALL get_correlation('humidity', 'atm_a_error', 'minimal_data_matched_error', 'dist_miles <= 0.1');
CALL get_correlation('humidity', 'atm_a_abs_error', 'minimal_data_matched_abs_error', 'dist_miles <= 0.1');
CALL get_correlation('humidity', 'pm25_atm_a', 'minimal_data_matched', 'dist_miles <= 0.1');
CALL get_correlation('humidity', 'atm_b_error', 'minimal_data_matched_error', 'dist_miles <= 0.1');
CALL get_correlation('humidity', 'atm_b_abs_error', 'minimal_data_matched_abs_error', 'dist_miles <= 0.1');

CREATE OR REPLACE VIEW minimal_data_matched_channel_diff AS
SELECT *, ABS(pm25_atm_a - pm25_atm_b) AS ab_diff, ABS(pm25_atm_a - pm25_nowcast_value) AS atm_a_abs_error,
ABS(pm25_atm_b - pm25_nowcast_value) AS atm_b_abs_error
FROM minimal_data_matched;

# Channel disagreement is a strong predictor of error for channel A, but only a moderate predictor for 
# channel B
CALL get_correlation('ab_diff', 'atm_a_abs_error', 'minimal_data_matched_channel_diff', 'dist_miles <= 0.1');
CALL get_correlation('ab_diff', 'atm_b_abs_error', 'minimal_data_matched_channel_diff', 'dist_miles <= 0.1');