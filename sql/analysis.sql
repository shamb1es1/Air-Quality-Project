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
IN which_table VARCHAR(64))
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
        FROM ', which_table
    );

    PREPARE getcorr FROM @corrquer;
    EXECUTE getcorr;
    DEALLOCATE PREPARE getcorr;
END //
DELIMITER ;

CALL correlation('pm25_atm_a', 'pm25_atm_b', 'purpleair_sensor_data');
CALL correlation('pm25_cf_1_a', 'pm25_cf_1_b', 'purpleair_sensor_data');

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

SELECT * FROM purpleair_sensor_data limit 10;

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

# Create view of PurpleAir dataset without outliers in ANY of the data rows
CREATE OR REPLACE VIEW purpleair_cleaned_wo_outliers AS
WITH
atm_a_bound AS (
    SELECT q3 + 1.5 * (q3 - q1) AS upper_bound
    FROM (
        SELECT
            MAX(CASE WHEN pr <= 0.25 THEN pm25_atm_a END) AS q1,
            MIN(CASE WHEN pr >= 0.75 THEN pm25_atm_a END) AS q3
        FROM (
            SELECT
                pm25_atm_a,
                PERCENT_RANK() OVER (ORDER BY pm25_atm_a) AS pr
            FROM purpleair_sensor_data
            WHERE pm25_atm_a > 0
        ) x
    ) y
),
atm_b_bound AS (
    SELECT q3 + 1.5 * (q3 - q1) AS upper_bound
    FROM (
        SELECT
            MAX(CASE WHEN pr <= 0.25 THEN pm25_atm_b END) AS q1,
            MIN(CASE WHEN pr >= 0.75 THEN pm25_atm_b END) AS q3
        FROM (
            SELECT
                pm25_atm_b,
                PERCENT_RANK() OVER (ORDER BY pm25_atm_b) AS pr
            FROM purpleair_sensor_data
            WHERE pm25_atm_b > 0
        ) x
    ) y
),
cf1_a_bound AS (
    SELECT q3 + 1.5 * (q3 - q1) AS upper_bound
    FROM (
        SELECT
            MAX(CASE WHEN pr <= 0.25 THEN pm25_cf_1_a END) AS q1,
            MIN(CASE WHEN pr >= 0.75 THEN pm25_cf_1_a END) AS q3
        FROM (
            SELECT
                pm25_cf_1_a,
                PERCENT_RANK() OVER (ORDER BY pm25_cf_1_a) AS pr
            FROM purpleair_sensor_data
            WHERE pm25_cf_1_a > 0
        ) x
    ) y
),
cf1_b_bound AS (
    SELECT q3 + 1.5 * (q3 - q1) AS upper_bound
    FROM (
        SELECT
            MAX(CASE WHEN pr <= 0.25 THEN pm25_cf_1_b END) AS q1,
            MIN(CASE WHEN pr >= 0.75 THEN pm25_cf_1_b END) AS q3
        FROM (
            SELECT
                pm25_cf_1_b,
                PERCENT_RANK() OVER (ORDER BY pm25_cf_1_b) AS pr
            FROM purpleair_sensor_data
            WHERE pm25_cf_1_b > 0
        ) x
    ) y
)
SELECT p.*
FROM purpleair_sensor_data p
CROSS JOIN atm_a_bound a CROSS JOIN atm_b_bound b CROSS JOIN cf1_a_bound c CROSS JOIN cf1_b_bound d
WHERE (p.pm25_atm_a = 0 OR p.pm25_atm_a <= a.upper_bound)
AND (p.pm25_atm_b = 0 OR p.pm25_atm_b <= b.upper_bound)
AND (p.pm25_cf_1_a = 0 OR p.pm25_cf_1_a <= c.upper_bound)
AND (p.pm25_cf_1_b = 0 OR p.pm25_cf_1_b <= d.upper_bound);

SELECT * FROM purpleair_cleaned_wo_outliers;

# Procedure for creating views for each PurpleAir data column without outliers
DROP PROCEDURE IF EXISTS make_col_wo_outliers;
DELIMITER //
CREATE PROCEDURE make_col_wo_outliers(
    IN col_name VARCHAR(64),
    IN view_name VARCHAR(64)
)
BEGIN
    SET @sql = CONCAT(
        'CREATE OR REPLACE VIEW ', view_name, ' AS
         WITH positive_ranked AS (
             SELECT ', col_name, ', PERCENT_RANK() OVER (ORDER BY ', col_name, ') AS pr
             FROM purpleair_sensor_data
             WHERE ', col_name, ' > 0
         ),
         quartiles AS (
             SELECT
                 MAX(CASE WHEN pr <= 0.25 THEN ', col_name, ' END) AS q1,
                 MIN(CASE WHEN pr >= 0.75 THEN ', col_name, ' END) AS q3
             FROM positive_ranked
         ),
         bounds AS (
             SELECT
                 q1,
                 q3,
                 (q3 - q1) AS iqr,
                 (q3 + 1.5 * (q3 - q1)) AS upper_bound
             FROM quartiles
         )
         SELECT p.*
         FROM purpleair_sensor_data p
         CROSS JOIN bounds b
         WHERE p.', col_name, ' = 0
            OR p.', col_name, ' <= b.upper_bound'
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END //
DELIMITER ;

CALL make_col_wo_outliers('pm25_atm_a', 'purpleair_atm_a_no_outliers');
CALL make_col_wo_outliers('pm25_atm_b', 'purpleair_atm_b_no_outliers');
CALL make_col_wo_outliers('pm25_cf_1_a', 'purpleair_cf1_a_no_outliers');
CALL make_col_wo_outliers('pm25_cf_1_b', 'purpleair_cf1_b_no_outliers');

SELECT * FROM purpleair_atm_a_no_outliers;
SELECT * FROM purpleair_atm_b_no_outliers;
SELECT * FROM purpleair_cf1_a_no_outliers;
SELECT * FROM purpleair_cf1_b_no_outliers;

SELECT * FROM sensor_distances;

SELECT * FROM airnow_sensor_data JOIN airnow_sites ON
airnow_sensor_data.fullaqscode = airnow_sites.fullaqscode;

SELECT * FROM airnow_sensor_data;

SELECT * FROM purpleair_sensor_data;

SELECT * FROM purpleair_cleaned_wo_outliers limit 50;

SELECT * FROM sensor_distances;

SELECT site_id, COUNT(site_id)
FROM sensor_distances
GROUP BY site_id;

CREATE OR REPLACE VIEW data_matched_w_outliers AS
SELECT p.sensor_index AS sensor_index, p.datetime_timestamp AS datetime_timestamp, 
humidity, temperature, pm25_atm_a, pm25_atm_b, pm25_cf_1_a, pm25_cf_1_b, 
n.site_id AS site_id, pm25_nowcast_value, pm25_raw_concentration
FROM purpleair_sensor_data p
JOIN sensor_distances n
ON p.sensor_index = n.sensor_index
JOIN airnow_sensor_data a
ON n.site_id = a.site_id AND p.datetime_timestamp = a.datetime_timestamp;

CREATE OR REPLACE VIEW data_matched_wo_outliers AS
SELECT p.sensor_index AS sensor_index, p.datetime_timestamp AS datetime_timestamp, 
humidity, temperature, pm25_atm_a, pm25_atm_b, pm25_cf_1_a, pm25_cf_1_b, 
n.site_id AS site_id, pm25_nowcast_value, pm25_raw_concentration
FROM purpleair_cleaned_wo_outliers p
JOIN sensor_distances n
ON p.sensor_index = n.sensor_index
JOIN airnow_sensor_data a
ON n.site_id = a.site_id AND p.datetime_timestamp = a.datetime_timestamp
WHERE p.pm25_cf_1_a <= 100;

DROP PROCEDURE IF EXISTS get_corr;
DELIMITER //
CREATE PROCEDURE get_corr(IN x_col VARCHAR(64), IN y_col VARCHAR(64),
IN table_name VARCHAR(64))
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
        'AND ', y_col, ' IS NOT NULL'
    );
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END //
DELIMITER ;

# Get correlation coefficicient for outlier included data
CALL get_corr('pm25_atm_a', 'pm25_nowcast_value', 'data_matched_w_outliers');
CALL get_corr('pm25_atm_b', 'pm25_nowcast_value', 'data_matched_w_outliers');
CALL get_corr('pm25_cf_1_a', 'pm25_nowcast_value', 'data_matched_w_outliers');
CALL get_corr('pm25_cf_1_b', 'pm25_nowcast_value', 'data_matched_w_outliers');

# Get correlation coefficicient for outlier excluded data
CALL get_corr('pm25_atm_a', 'pm25_nowcast_value', 'data_matched_wo_outliers');
CALL get_corr('pm25_atm_b', 'pm25_nowcast_value', 'data_matched_wo_outliers');
CALL get_corr('pm25_cf_1_a', 'pm25_nowcast_value', 'data_matched_wo_outliers');
CALL get_corr('pm25_cf_1_b', 'pm25_nowcast_value', 'data_matched_wo_outliers');

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

CALL get_mae('pm25_atm_a', 'pm25_nowcast_value', 'data_matched_w_outliers');
CALL get_mae('pm25_atm_b', 'pm25_nowcast_value', 'data_matched_w_outliers');
CALL get_mae('pm25_cf_1_a', 'pm25_nowcast_value', 'data_matched_w_outliers');
CALL get_mae('pm25_cf_1_b', 'pm25_nowcast_value', 'data_matched_w_outliers');

CALL get_mae('pm25_atm_a', 'pm25_nowcast_value', 'data_matched_wo_outliers');
CALL get_mae('pm25_atm_b', 'pm25_nowcast_value', 'data_matched_wo_outliers');
CALL get_mae('pm25_cf_1_a', 'pm25_nowcast_value', 'data_matched_wo_outliers');
CALL get_mae('pm25_cf_1_b', 'pm25_nowcast_value', 'data_matched_wo_outliers');