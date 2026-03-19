# Air-Quality-Project

##### by Justin Wright

## Project objective

##### Evaluate the reliability of low-cost air quality sensors by validating PurpleAir PM2.5 measurements against EPA AirNow reference monitors, using dual-channel (A/B) consistency and humidity conditions to distinguish true pollution exposure from measurement bias.

## How this project came to be

##### At the onset of this project, I sought to find a dataset having to do with air quality readings so that I could take a look at the correlation between hazardous air conditions and reported asthma attacks. It was in this search that I stumbled upon PurpleAir and decided to use their sensors to satisfy the former. Although, in this process, through concerned users of their own sensors and by the admittance of the company in their own forums, I became aware of the possibility of sensors to underestimate and overestimate particulate matter readings depending on environmental factors and ware of the device. The company is aware of this case, allowing consumers to look at different conversion factors of their readings based on what meets their needs best. So while PurpleAir does not seem to oversell the efficacy of their product to consumers, with the main selling points being the sensors small size and greater affordability compared to its competitors, I was convinced to change the course of action for this project and investigate.

## Staging table cleaning and column creation

_cleaning_purpleair.sql, cleaning_airnow.sql, insertion.sql_

#### Goal: Transform and remove "bad" data from each dataset to leave us with data we can appropriately compare to each other, while also recording what proportion of the data we ingested was faulty or reported

#### Part 1: PurpleAir

After some basic initial queries checking for NULLs and pattern matching with regex, I performed a join to verify all indexes have a match between tables, where I was suprised to find an excessive number of indexes do not

```
SELECT d.sensor_index, COUNT(*) AS row_ct
FROM staging_purpleair_sensor_data d
LEFT JOIN staging_purpleair_sensors s
ON s.sensor_index = d.sensor_index
WHERE s.sensor_index IS NULL
GROUP BY d.sensor_index;
```

![alt text](/img/non_matched_indexes.png)  
I examined two indexes that should have matched and realized the indexes in the history dataset has a return carriage '0d' appended at the end of the values, so I altered my LOAD DATA query to replace these characters in the insert script

```
(time_stamp, humidity, temperature, `pm2.5_atm_a`, `pm2.5_atm_b`, `pm2.5_cf_1_a`,
`pm2.5_cf_1_b`, @sensor_index)
SET sensor_index = REPLACE(TRIM(@sensor_index), '\r', '')
```

Following this I decided to reun a check on the opposite as well

```
SELECT s.sensor_index
FROM staging_purpleair_sensors s
LEFT JOIN staging_purpleair_sensor_data d
ON d.sensor_index = s.sensor_index
WHERE d.sensor_index IS NULL;
```

![alt text](/img/non_matched_indexes.png)  
This revealed 122 sensors that do not appear in the PurpleAir history dataset, so they could be promptly disposed of

```
DELETE FROM staging_purpleair_sensors
WHERE sensor_index IN (
  SELECT sensor_index
  FROM (
    SELECT s.sensor_index
    FROM staging_purpleair_sensors s
    LEFT JOIN staging_purpleair_sensor_data d
      ON d.sensor_index = s.sensor_index
    WHERE d.sensor_index IS NULL
  ) x
);
```

Running the following snippet revealed empty or NULL values wuthin the purpleair sensor data table

```SELECT
SUM(time_stamp IS NULL OR TRIM(time_stamp) = '') AS time_stamp_nulls,
SUM(humidity IS NULL OR TRIM(humidity) = '') AS humidity_nulls,
SUM(temperature IS NULL OR TRIM(temperature) = '') AS temperature_nulls,
SUM(`pm2.5_atm_a` IS NULL OR TRIM(`pm2.5_atm_a`) = '') AS pm25_atm_a_nulls,
SUM(`pm2.5_atm_b` IS NULL OR TRIM(`pm2.5_atm_b`) = '') AS pm25_atm_b_nulls,
SUM(`pm2.5_cf_1_a` IS NULL OR TRIM(`pm2.5_cf_1_a`) = '') AS pm25_cf_1_a_nulls,
SUM(`pm2.5_cf_1_b` IS NULL OR TRIM(`pm2.5_cf_1_b`) = '') AS pm25_cf_1_b_nulls
FROM staging_purpleair_sensor_data;
```

![alt text](/img/purpleair_data_nulls.png)
The first thing I wanted to look at was finding out what proportion of an indexes humidity and temperature values are not
appearing

```
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
    SUM(humidity = '' OR humidity IS NULL) AS humidity_empty_ct,
    COUNT(humidity) AS humidity_ct,
    SUM(temperature = '' OR humidity IS NULL) AS temperature_empty_ct,
    COUNT(temperature) AS temperature_ct
	FROM staging_purpleair_sensor_data
	GROUP BY sensor_index
) s
WHERE humidity_empty_ct > 0 OR temperature_empty_ct > 0
ORDER BY humidity_empty_pct DESC, temperature_empty_pct DESC;
```

![alt text](/img/humid_temp_nulls.png)  
Further analysis revealed that all these rows have values of '' for both humidity and temperature

A total of 50,390 rows contained these missing values and it was decided that these should be dropped in the case that these specific devices are faulty, especially given that for these devices, bad humidity and temperature rows make up such a large portion of the data they provide

The sensors were removed from both PurpleAir data sets

```
DELETE FROM staging_purpleair_sensor_data
WHERE humidity = '' OR humidity IS NULL OR temperature = '' OR temperature IS NULL;
```

```
DELETE FROM staging_purpleair_sensors
WHERE sensor_index NOT IN (
	SELECT DISTINCT sensor_index FROM staging_purpleair_sensor_data
);
```

Next up was looking at the atm_b and cf_1_b rows that we're NULL or empty

```
SELECT sensor_index,
SUM(`pm2.5_atm_b` IS NULL OR TRIM(`pm2.5_atm_b`) = '') AS pm25_atm_b_bad_rows,
SUM(`pm2.5_cf_1_b` IS NULL OR TRIM(`pm2.5_cf_1_b`) = '') AS pm25_cf_1_b_bad_rows,
COUNT(*) AS total_rows
FROM staging_purpleair_sensor_data 
GROUP BY sensor_index
HAVING pm25_atm_b_bad_rows > 0 OR pm25_cf_1_b_bad_rows > 0;
```

GET PICTURE

Seeing that there are only two sensors that are returned on this query, with 100% of all the row contributions from those sensors having missing data (10 and 7655), it is better to assume those sensors are faulty and all cooresponding data can be deleted from each dataset

```
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
```
```
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
```

The following Unix time stamp related queries we're required to be ran with an explicit time zone conversion, to both avoid the smallest Unix time stamps from appearing as though they appear on the last day of 2024, and a daylight saving binning problem that caused two hours of data to be converted to the same datetime with the same Unix time stamp

```
SET SESSION time_zone = '+00:00';
```

Created datetime columns that will be used to match AirNow rows

```
ALTER TABLE staging_purpleair_sensors
ADD COLUMN datetime_date_created DATETIME;
```
```
UPDATE staging_purpleair_sensors
SET datetime_date_created = DATE_FORMAT(
FROM_UNIXTIME(date_created),'%Y-%m-%d %H:00:00');
```
```
ALTER TABLE staging_purpleair_sensors
ADD COLUMN datetime_last_seen DATETIME;
```
```
UPDATE staging_purpleair_sensors
SET datetime_last_seen = DATE_FORMAT(
FROM_UNIXTIME(last_seen),'%Y-%m-%d %H:00:00');
```
```
ALTER TABLE staging_purpleair_sensor_data
ADD COLUMN datetime_timestamp DATETIME;
```
```
UPDATE staging_purpleair_sensor_data
SET datetime_timestamp = 
CAST(DATE_FORMAT(FROM_UNIXTIME(time_stamp),'%Y-%m-%d %H:00:00') AS DATETIME);
```

#### Part 2: AirNow

The columns agencyname, parameter, unit, and intlaqscode have distinct values, and parameter and unit are always PM2.5 and UG/M3 respectively... All columns can be dropped

```
ALTER TABLE staging_airnow_sensor_data
DROP COLUMN agencyname,
DROP COLUMN parameter,
DROP COLUMN intlaqscode,
DROP COLUMN unit;
```

Category aligns with binned api values, can use case statements to rebuild

```
ALTER TABLE staging_airnow_sensor_data
DROP COLUMN category;
```

479 rows were found with missing or invalid values in value and aqi, and 2993 in rawconcentration (AirNow designates a -999 value as missinf or invalid)

```
SELECT COUNT(*) FROM staging_airnow_sensor_data WHERE `value` = '-999'
UNION ALL
SELECT COUNT(*) FROM staging_airnow_sensor_data WHERE rawconcentration = '-999'
UNION ALL
SELECT COUNT(*) FROM staging_airnow_sensor_data WHERE aqi = '-999';
```

Create the datetime column that will be used to match the datetime column in the PurpleAir data table

```
ALTER TABLE staging_airnow_sensor_data
ADD COLUMN datetime_timestamp DATETIME;
```
```
UPDATE staging_airnow_sensor_data
SET datetime_timestamp = STR_TO_DATE(REPLACE(utc, 'T', ' '), '%Y-%m-%d %H:%i');
```

Something that was discovered in the final table creation stage was a single AirNow entry that presumably had a rounded or truncated longitude value that caused the entry to create an entire new entry in airnow_sites table

This value was off by a 

## Final tables and insertion

```
DROP TABLE IF EXISTS purpleair_sensors;
CREATE TABLE purpleair_sensors (
	sensor_index INT PRIMARY KEY,
    datetime_date_created DATETIME NOT NULL,
    datetime_last_seen DATETIME NOT NULL,
    `name` VARCHAR(255),
    latitude DECIMAL(9, 6) NOT NULL,
    longitude DECIMAL(9, 6) NOT NULL,
    CHECK (latitude BETWEEN -90 AND 90),
    CHECK (longitude BETWEEN -180 AND 180)
);

INSERT INTO purpleair_sensors (
    sensor_index, datetime_date_created, datetime_last_seen, `name`, latitude, longitude
)
SELECT sensor_index, datetime_date_created, datetime_last_seen, `name`, latitude, longitude
FROM staging_purpleair_sensors;

DROP TABLE IF EXISTS purpleair_sensor_data;
CREATE TABLE purpleair_sensor_data (
	sensor_index INT NOT NULL,
    datetime_timestamp DATETIME NOT NULL,
    humidity DECIMAL(5, 2) NOT NULL,
    temperature DECIMAL(5, 2) NOT NULL, 
    `pm2.5_atm_a` DECIMAL(7, 2) NOT NULL,
	`pm2.5_atm_b` DECIMAL(7, 2) NOT NULL,
    `pm2.5_cf_1_a` DECIMAL(7, 2) NOT NULL,
    `pm2.5_cf_1_b` DECIMAL(7, 2) NOT NULL,
    PRIMARY KEY (sensor_index, datetime_timestamp),
    FOREIGN KEY (sensor_index) REFERENCES purpleair_sensors(sensor_index) ON DELETE CASCADE,
    CHECK (`pm2.5_atm_a` >= 0),
    CHECK (`pm2.5_atm_b` >= 0),
    CHECK (`pm2.5_cf_1_a` >= 0),
    CHECK (`pm2.5_cf_1_b` >= 0)
);

INSERT INTO purpleair_sensor_data (
	sensor_index, datetime_timestamp, humidity, temperature, `pm2.5_atm_a`, `pm2.5_atm_b`,
    `pm2.5_cf_1_a`, `pm2.5_cf_1_b`
)
SELECT sensor_index, datetime_timestamp, humidity, temperature, `pm2.5_atm_a`, `pm2.5_atm_b`,
`pm2.5_cf_1_a`, `pm2.5_cf_1_b`
FROM staging_purpleair_sensor_data;

DROP TABLE IF EXISTS airnow_sites;
CREATE TABLE airnow_sites (
	site_id BIGINT AUTO_INCREMENT,
    latitude  DECIMAL(9,6) NOT NULL,
	longitude DECIMAL(9,6) NOT NULL,
	fullaqscode BIGINT NOT NULL,
    site_name VARCHAR(255) NOT NULL DEFAULT 'N/A',
    PRIMARY KEY (site_id),
    UNIQUE (latitude, longitude)
);

INSERT INTO airnow_sites (latitude, longitude, fullaqscode, site_name)
SELECT
  ROUND(CAST(d.latitude  AS DECIMAL(8,6)), 6)  AS latitude,
  ROUND(CAST(d.longitude AS DECIMAL(9,6)), 6) AS longitude,
  MIN(d.fullaqscode) AS fullaqscode,
  MIN(d.sitename)    AS site_name
FROM staging_airnow_sensor_data d
GROUP BY
  ROUND(CAST(d.latitude  AS DECIMAL(8,6)), 6),
  ROUND(CAST(d.longitude AS DECIMAL(9,6)), 6);

DROP TABLE IF EXISTS airnow_sensor_data;
CREATE TABLE airnow_sensor_data (
	site_id BIGINT NOT NULL,
	datetime_timestamp DATETIME NOT NULL,
	fullaqscode BIGINT NOT NULL,
    pm25_nowcast_value DECIMAL(6, 2) NOT NULL,
    pm25_raw_concentration DECIMAL(6, 2) NOT NULL,
    PRIMARY KEY (site_id, datetime_timestamp),
    FOREIGN KEY (site_id) REFERENCES airnow_sites(site_id) ON UPDATE CASCADE ON DELETE CASCADE
);

INSERT INTO airnow_sensor_data (
site_id, datetime_timestamp, pm25_nowcast_value, pm25_raw_concentration, fullaqscode)
SELECT DISTINCT s.site_id, d.utc, CAST(d.`value` AS DECIMAL(6,2)),
CAST(d.rawconcentration AS DECIMAL(6,2)), d.fullaqscode
FROM staging_airnow_sensor_data d
JOIN airnow_sites s
ON s.latitude  = ROUND(CAST(d.latitude AS DECIMAL(9,6)), 6)
AND s.longitude = ROUND(CAST(d.longitude AS DECIMAL(9,6)), 6);
```

## Analysis

