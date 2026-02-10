DROP TABLE IF EXISTS purpleair_sensor_data;
DROP TABLE IF EXISTS purpleair_sensors;

CREATE TABLE purpleair_sensors (
	sensor_index INT PRIMARY KEY,
    datetime_date_created DATETIME NOT NULL,
    datetime_last_seen DATETIME NOT NULL,
    site_name VARCHAR(255),
    latitude DECIMAL(9, 6) NOT NULL,
    longitude DECIMAL(9, 6) NOT NULL,
    CHECK (latitude BETWEEN -90 AND 90),
    CHECK (longitude BETWEEN -180 AND 180)
);

INSERT INTO purpleair_sensors (
    sensor_index, datetime_date_created, datetime_last_seen, site_name, latitude, longitude
)
SELECT sensor_index, datetime_date_created, datetime_last_seen, `name`, latitude, longitude
FROM staging_purpleair_sensors;

CREATE TABLE purpleair_sensor_data (
	sensor_index INT NOT NULL,
    datetime_timestamp DATETIME NOT NULL,
    humidity DECIMAL(5, 2) NOT NULL,
    temperature DECIMAL(5, 2) NOT NULL, 
    pm25_atm_a DECIMAL(6, 1) NOT NULL,
	pm25_atm_b DECIMAL(6, 1) NOT NULL,
    pm25_cf_1_a DECIMAL(6, 1) NOT NULL,
    pm25_cf_1_b DECIMAL(6, 1) NOT NULL,
    PRIMARY KEY (sensor_index, datetime_timestamp),
    FOREIGN KEY (sensor_index) REFERENCES purpleair_sensors(sensor_index) ON DELETE CASCADE,
    CHECK (pm25_atm_a >= 0),
    CHECK (pm25_atm_b >= 0),
    CHECK (pm25_cf_1_a >= 0),
    CHECK (pm25_cf_1_b >= 0)
);

INSERT INTO purpleair_sensor_data (
	sensor_index, datetime_timestamp, humidity, temperature, pm25_atm_a, pm25_atm_b,
    pm25_cf_1_a, pm25_cf_1_b
)
SELECT sensor_index, datetime_timestamp, humidity, temperature, `pm2.5_atm_a`, `pm2.5_atm_b`,
`pm2.5_cf_1_a`, `pm2.5_cf_1_b`
FROM staging_purpleair_sensor_data;

DROP TABLE IF EXISTS airnow_sensor_data;
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

CREATE TABLE airnow_sensor_data (
	site_id BIGINT NOT NULL,
	datetime_timestamp DATETIME NOT NULL,
	fullaqscode BIGINT NOT NULL,
    pm25_nowcast_value DECIMAL(6, 1) NOT NULL,
    pm25_raw_concentration DECIMAL(6, 1) NOT NULL,
    PRIMARY KEY (site_id, datetime_timestamp),
    FOREIGN KEY (site_id) REFERENCES airnow_sites(site_id) ON UPDATE CASCADE ON DELETE CASCADE
);

INSERT INTO airnow_sensor_data (
site_id, datetime_timestamp, pm25_nowcast_value, pm25_raw_concentration, fullaqscode)
SELECT DISTINCT s.site_id, d.utc, CAST(d.`value` AS DECIMAL(6,1)),
CAST(d.rawconcentration AS DECIMAL(6,1)), d.fullaqscode
FROM staging_airnow_sensor_data d
JOIN airnow_sites s
ON s.latitude  = ROUND(CAST(d.latitude AS DECIMAL(9,6)), 6)
AND s.longitude = ROUND(CAST(d.longitude AS DECIMAL(9,6)), 6);

select * from airnow_sensor_data limit 50;
select * from airnow_sites limit 50;