SHOW VARIABLES LIKE 'local_infile';
SET GLOBAL local_infile = 1;
SHOW VARIABLES LIKE 'secure_file_priv';

DROP TABLE IF EXISTS staging_purpleair_sensors;
CREATE TABLE staging_purpleair_sensors (
	sensor_index TEXT,
    date_created TEXT,
    last_seen TEXT,
    `name` TEXT,
    uptime TEXT,
    latitude TEXT,
    longitude TEXT
);

LOAD DATA LOCAL INFILE 'C:/Users/juwri/Downloads/Air Quality Project/data/purpleair_sensors.csv'
INTO TABLE staging_purpleair_sensors
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
IGNORE 1 LINES
(sensor_index, date_created, last_seen, `name`, uptime, latitude, longitude);

DROP TABLE IF EXISTS staging_purpleair_sensor_data;
CREATE TABLE staging_purpleair_sensor_data (
	time_stamp TEXT, 
    humidity TEXT,
    temperature TEXT, 
    `pm2.5_atm_a` TEXT, 
    `pm2.5_atm_b` TEXT, 
    `pm2.5_cf_1_a` TEXT,
	`pm2.5_cf_1_b` TEXT, 
	sensor_index TEXT
);

LOAD DATA LOCAL INFILE 'C:/Users/juwri/Downloads/Air Quality Project/data/purpleair_sensor_data.csv'
INTO TABLE staging_purpleair_sensor_data
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
IGNORE 1 LINES
(time_stamp, humidity, temperature, `pm2.5_atm_a`, `pm2.5_atm_b`, `pm2.5_cf_1_a`,
`pm2.5_cf_1_b`, sensor_index);

DROP TABLE IF EXISTS staging_airnow_sensor_data;
CREATE TABLE staging_airnow_sensor_data (
	latitude TEXT,
    longitude TEXT,
    utc TEXT,
    parameter TEXT,
    unit TEXT,
    `value` TEXT,
    rawconcentration TEXT,
    aqi TEXT,
    category TEXT,
    sitename TEXT,
    agencyname TEXT,
    fullaqscode TEXT,
    intlaqscode TEXT
);

LOAD DATA LOCAL INFILE 'C:/Users/juwri/Downloads/Air Quality Project/data/airnow_sensor_data.csv'
INTO TABLE staging_airnow_sensor_data
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
IGNORE 1 LINES
(latitude, longitude, utc, parameter, unit, `value`, rawconcentration, aqi,
category, sitename, agencyname, fullaqscode, intlaqscode);