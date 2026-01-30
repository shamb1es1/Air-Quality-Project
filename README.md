# Air-Quality-Project
##### by Justin Wright

## Project objective
##### Evaluate the reliability of low-cost air quality sensors by validating PurpleAir PM2.5 measurements against EPA AirNow reference monitors, using dual-channel (A/B) consistency and humidity conditions to distinguish true pollution exposure from measurement bias.
## How this project came to be
##### At the onset of this project, I sought to find a dataset having to do with air quality readings so that I could take a look at the correlation between hazardous air conditions and reported asthma attacks. It was in this search that I stumbled upon PurpleAir and decided to use their sensors to satisfy the former. Although, in this process, through concerned users of their own sensors and by the admittance of the company in their own forums, I became aware of the possibility of sensors to underestimate and overestimate particulate matter readings depending on environmental factors and ware of the device. The company is aware of this case, allowing consumers to look at different conversion factors of their readings based on what meets their needs best. So while PurpleAir does not seem to oversell the efficacy of their product to consumers, with the main selling points being the sensors small size and greater affordability compared to its competitors, I was convinced to change the course of action for this project and investigate.
## Data cleaning
*cleaning_purpleair.sql, cleaning_airnow.sql, insertion.sql*  
#### Goal: Transform and remove "bad" data from each dataset to leave us with data we can appropriately compare to each other, while also recording what proportion of the data we ingested was faulty or reported

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