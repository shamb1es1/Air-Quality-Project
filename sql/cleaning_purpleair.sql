##### DROP COLUMNS

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
OR longitude NOT REGEXP '^[+-]?[0-9]{1,3}(\\.[0-9]+)?$';

# All unix timestamps valid
SELECT date_created, last_seen
FROM staging_purpleair_sensors
WHERE date_created NOT REGEXP '^[0-9]{10}$' AND last_seen NOT REGEXP '^[0-9]{10}$';

# NULL values found in humidity and temperature
SELECT *
FROM staging_purpleair_sensor_data
WHERE time_stamp IS NULL OR TRIM(time_stamp) = ''
OR humidity IS NULL OR TRIM(humidity) = ''
OR temperature IS NULL OR TRIM(temperature) = ''
OR `pm2.5_atm_a` IS NULL OR TRIM(`pm2.5_atm_a`) = ''
OR `pm2.5_atm_b` IS NULL OR TRIM(`pm2.5_atm_b`) = ''
OR `pm2.5_cf_1_a` IS NULL OR TRIM(`pm2.5_cf_1_a`) = ''
OR `pm2.5_cf_1_b` IS NULL OR TRIM(`pm2.5_cf_1_b`) = '';

# Get count of empty humidity and temperature values
SELECT SUM(humidity = '') AS humidity_empty_ct,
SUM(temperature = '') AS temperature_empty_ct
FROM staging_purpleair_sensor_data;

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
WHERE humidity_empty_ct > 0 OR temperature_empty_ct > 0;


# Check from preceding and following hour values for humidity
SELECT
  t.sensor_index,
  t.time_stamp,
  t.humidity,
  -- check whether the exact previous/next hour exists
  EXISTS (
    SELECT 1
    FROM staging_purpleair_sensor_data p
    WHERE p.sensor_index = t.sensor_index
      AND p.time_stamp = t.time_stamp - INTERVAL 1 HOUR
      AND p.humidity IS NOT NULL
  ) AS has_prev_1h,
  EXISTS (
    SELECT 1
    FROM staging_purpleair_sensor_data n
    WHERE n.sensor_index = t.sensor_index
      AND n.time_stamp = t.time_stamp + INTERVAL 1 HOUR
      AND n.humidity IS NOT NULL
  ) AS has_next_1h
FROM staging_purpleair_sensor_data t
WHERE t.humidity IS NULL;

# Personal computer uses the eastern time zone for the OS, so need to set it to UTC to avoid the
# earliest return data from appearing as if it was taken on 12/31/2024
SET time_zone = '+00:00';

# Verify unix timecode converts to 1/1/2025 00:00:00.00
SELECT time_stamp, from_unixtime(time_stamp) AS dt FROM staging_purpleair_sensor_data
ORDER BY dt asc
LIMIT 5;

