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
