##### TYPE CHECKING

# No null values found in staging_purpleair_sensors
SELECT *
FROM staging_purpleair_sensors
WHERE sensor_index IS NULL OR TRIM(sensor_index) = ''
OR date_created IS NULL OR TRIM(date_created) = ''
OR last_seen IS NULL OR TRIM(last_seen) = ''
OR `name` IS NULL OR TRIM(`name`) = ''
OR uptime IS NULL OR TRIM(uptime) = ''
OR latitude IS NULL OR TRIM(latitude) = ''
OR longitude IS NULL OR TRIM(longitude) = '';

# All sensor indexes and uptime are valid digits
SELECT sensor_index, uptime
FROM staging_purpleair_sensors
WHERE sensor_index NOT REGEXP '^[0-9]+$' OR uptime NOT REGEXP '^[0-9]+$';

# All latitude and longitude values valid
SELECT latitude, longitude
FROM staging_purpleair_sensors
WHERE latitude NOT REGEXP '^[+-]?[0-9]{1,2}(\\.[0-9]+)?$'
AND CAST(latitude AS DECIMAL(9,6)) NOT BETWEEN -90 AND 90
OR longitude NOT REGEXP '^[+-]?[0-9]{1,3}(\\.[0-9]+)?$'
AND CAST(longitude AS DECIMAL(9,6)) NOT BETWEEN -180 AND 180;

# All unix timestamps valid
SELECT date_created, last_seen
FROM staging_purpleair_sensors
WHERE date_created NOT REGEXP '^[0-9]{10}$' AND last_seen NOT REGEXP '^[0-9]{10}$';

# NULL values found in humidity, temperature, atm b sensors, and cf1 b sensors
SELECT
SUM(time_stamp IS NULL OR TRIM(time_stamp) = '') AS time_stamp_nulls,
SUM(humidity IS NULL OR TRIM(humidity) = '') AS humidity_nulls,
SUM(temperature IS NULL OR TRIM(temperature) = '') AS temperature_nulls,
SUM(`pm2.5_atm_a` IS NULL OR TRIM(`pm2.5_atm_a`) = '') AS pm25_atm_a_nulls,
SUM(`pm2.5_atm_b` IS NULL OR TRIM(`pm2.5_atm_b`) = '') AS pm25_atm_b_nulls,
SUM(`pm2.5_cf_1_a` IS NULL OR TRIM(`pm2.5_cf_1_a`) = '') AS pm25_cf_1_a_nulls,
SUM(`pm2.5_cf_1_b` IS NULL OR TRIM(`pm2.5_cf_1_b`) = '') AS pm25_cf_1_b_nulls
FROM staging_purpleair_sensor_data;

# Look at what proportion of an indexes humidity and temperature values are not
# appearing
SELECT
  sensor_index,
  humidity_empty_ct,
  humidity_ct,
  ROUND(100*humidity_empty_ct/NULLIF(humidity_ct, 0),1) AS humidity_empty_pct,
  temperature_empty_ct,
  temperature_ct,
  ROUND(100*temperature_empty_ct/NULLIF(temperature_ct, 0),1) AS temperature_empty_pct
FROM (
	SELECT sensor_index,
    SUM(humidity = '') AS humidity_empty_ct,
    COUNT(humidity) AS humidity_ct,
    SUM(temperature = '') AS temperature_empty_ct,
    COUNT(temperature) AS temperature_ct
	FROM staging_purpleair_sensor_data
	GROUP BY sensor_index
) s
WHERE humidity_empty_ct > 0 OR temperature_empty_ct > 0
ORDER BY humidity_empty_pct DESC, temperature_empty_pct DESC;

# Removing empty humidity and temperature rows
DELETE FROM staging_purpleair_sensor_data
WHERE humidity = '' OR humidity IS NULL OR temperature = '' OR temperature IS NULL;

# Look at what sensors are primary culprits
SELECT sensor_index,
SUM(`pm2.5_atm_b` IS NULL OR TRIM(`pm2.5_atm_b`) = '') AS pm25_atm_b_bad_rows,
SUM(`pm2.5_cf_1_b` IS NULL OR TRIM(`pm2.5_cf_1_b`) = '') AS pm25_cf_1_b_bad_rows
FROM staging_purpleair_sensor_data 
GROUP BY sensor_index
HAVING pm25_atm_b_bad_rows > 1 OR pm25_cf_1_b_bad_rows > 1;

# Because there are only 2 sensors that have missing data in these categories, it's
# easier to delete those sensors from the data set in case they are faulty overall
DELETE FROM staging_purpleair_sensors
WHERE sensor_index IN (
  SELECT sensor_index
  FROM (
    SELECT DISTINCT sensor_index
    FROM staging_purpleair_sensor_data
    WHERE (`pm2.5_atm_b` IS NULL OR TRIM(`pm2.5_atm_b`) = '')
       OR (`pm2.5_cf_1_b` IS NULL OR TRIM(`pm2.5_cf_1_b`) = '')
  ) s
);

# Delete possibly fault sensor data from above
DELETE FROM staging_purpleair_sensor_data
WHERE sensor_index IN (
  SELECT sensor_index
  FROM (
    SELECT DISTINCT sensor_index
    FROM staging_purpleair_sensor_data
    WHERE (`pm2.5_atm_b` IS NULL OR TRIM(`pm2.5_atm_b`) = '')
       OR (`pm2.5_cf_1_b` IS NULL OR TRIM(`pm2.5_cf_1_b`) = '')
  ) s
);

# Personal computer uses the eastern time zone for the OS, so need to set it to UTC to avoid the
# earliest return data from appearing as if it was taken on 12/31/2024
# Prevented problem where 1762059600 and 1762063200 we're being converted to the
# same datetime bucket due to daylight savings
SET SESSION time_zone = '+00:00';

# Verify unix timecode converts to 1/1/2025 00:00:00.00 in sensor csv
(SELECT date_created AS unix_ts, FROM_UNIXTIME(date_created) AS converted_ts,
'date_created' AS source_col
FROM staging_purpleair_sensors
ORDER BY date_created ASC
LIMIT 5)
UNION ALL
(SELECT last_seen AS unix_ts, FROM_UNIXTIME(last_seen) AS converted_ts,
'last_seen' AS source_col
FROM staging_purpleair_sensors
ORDER BY last_seen ASC
LIMIT 5);

# Verify unix timecode converts to 1/1/2025 00:00:00.00 in sensor data csv
SELECT time_stamp, from_unixtime(time_stamp) AS dt FROM staging_purpleair_sensor_data
ORDER BY dt asc
LIMIT 5;

# Verify all ints convertable to a unix time in sensor csv
SELECT date_created, last_seen
FROM staging_purpleair_sensors
WHERE FROM_UNIXTIME(date_created) IS NULL OR FROM_UNIXTIME(last_seen) IS NULL;

# Verify all ints convertable to a unix time in sensor data csv
SELECT time_stamp
FROM staging_purpleair_sensor_data
WHERE FROM_UNIXTIME(time_stamp) IS NULL;

SELECT FROM_UNIXTIME(time_stamp) from staging_purpleair_sensor_data;

##### NEW COLUMNS

# Create datetime_date_created
ALTER TABLE staging_purpleair_sensors
ADD COLUMN datetime_date_created DATETIME;

# Change date format for date_created
UPDATE staging_purpleair_sensors
SET datetime_date_created = DATE_FORMAT(
FROM_UNIXTIME(date_created),'%Y-%m-%d %H:00:00');

# Create datetime_last_seen
ALTER TABLE staging_purpleair_sensors
ADD COLUMN datetime_last_seen DATETIME;

# Change date format for last_seen
UPDATE staging_purpleair_sensors
SET datetime_last_seen = DATE_FORMAT(
FROM_UNIXTIME(last_seen),'%Y-%m-%d %H:00:00');

# Create datetime_timestamp
ALTER TABLE staging_purpleair_sensor_data
ADD COLUMN datetime_timestamp DATETIME;

# Change date format for time_stamp
UPDATE staging_purpleair_sensor_data
SET datetime_timestamp = 
CAST(DATE_FORMAT(FROM_UNIXTIME(time_stamp),'%Y-%m-%d %H:00:00') AS DATETIME);

##### KEY VERIFICATION

# Check for duplicate keys (PK is sensor_index and datetime_timestamp)
SELECT sensor_index, datetime_timestamp, COUNT(*)
FROM staging_purpleair_sensor_data
GROUP BY sensor_index, datetime_timestamp
HAVING COUNT(*) > 1;

# Was used for evaluating previous time bucketing error
SELECT *
FROM staging_purpleair_sensor_data
WHERE (sensor_index, datetime_timestamp) IN (
	SELECT sensor_index, datetime_timestamp
	FROM (
		SELECT sensor_index, datetime_timestamp, COUNT(*)
		FROM staging_purpleair_sensor_data
		GROUP BY sensor_index, datetime_timestamp
		HAVING COUNT(*) > 1
	) i
)
ORDER BY sensor_index, datetime_timestamp;

# Verfied the timestamps that were getting bucketed to the same datetime are now
# split
SELECT
  time_stamp,
  FROM_UNIXTIME(time_stamp) AS dt
FROM staging_purpleair_sensor_data
WHERE time_stamp IN (1762059600, 1762063200)
LIMIT 20;