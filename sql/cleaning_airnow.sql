##### DROP COLUMNS

# agencyname, parameter, unit, and intlaqscode columns have distinct values
# parameter and unit always PM2.5 and UG/M3 respectively
ALTER TABLE staging_airnow_sensor_data
DROP COLUMN agencyname,
DROP COLUMN parameter,
DROP COLUMN intlaqscode,
DROP COLUMN unit;

# category aligns with binned api values, can use case statements to rebuild
ALTER TABLE staging_airnow_sensor_data
DROP COLUMN category;

##### DROP BAD SENSOR READINGS

# 479 rows with missing or invalid value in value and aqi, and 2993 in rawconcentration
SELECT COUNT(`value`) FROM staging_airnow_sensor_data WHERE `value` = '-999'
UNION ALL
SELECT COUNT(rawconcentration) FROM staging_airnow_sensor_data WHERE rawconcentration = '-999'
UNION ALL
SELECT COUNT(aqi) FROM staging_airnow_sensor_data WHERE aqi = '-999';

# Delete all -999 rows
DELETE FROM staging_airnow_sensor_data
WHERE `value` = '-999' OR rawconcentration = '-999' OR aqi = '-999';

##### TYPE CHECKING

# No NULL values found
SELECT *
FROM staging_airnow_sensor_data
WHERE latitude IS NULL OR TRIM(latitude) = ''
OR longitude IS NULL OR TRIM(longitude) = ''
OR utc IS NULL OR TRIM(utc) = ''
OR `value` IS NULL OR TRIM(`value`) = ''
OR rawconcentration IS NULL OR TRIM(rawconcentration) = ''
OR aqi IS NULL OR TRIM(aqi) = ''
OR sitename IS NULL OR TRIM(sitename) = ''
OR fullaqscode IS NULL OR TRIM(fullaqscode) = '';

# All value data valid
SELECT `value` 
FROM staging_airnow_sensor_data
WHERE `value` NOT REGEXP '^[0-9]{1,3}(\\.[0-9])?$';

# All aqs codes valid
SELECT fullaqscode
FROM staging_airnow_sensor_data
WHERE fullaqscode NOT REGEXP '^[0-9]+$';

# All latitude and longitude values valid
SELECT latitude, longitude
FROM staging_airnow_sensor_data
WHERE latitude NOT REGEXP '^[+-]?[0-9]{1,2}(\\.[0-9]+)?$'
OR longitude NOT REGEXP '^[+-]?[0-9]{1,3}(\\.[0-9]+)?$';

# All but 1 aqs code coorelates with a single sitename
SELECT fullaqscode, COUNT(DISTINCT sitename) AS distinct_sitenames
FROM staging_airnow_sensor_data
GROUP BY fullaqscode
HAVING COUNT(DISTINCT sitename) > 1;

# Site names that fall under the specific aqs code from above
SELECT DISTINCT sitename
FROM staging_airnow_sensor_data
WHERE fullaqscode = 840340000000;

