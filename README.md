# Air-Quality-Project
##### by Justin Wright
## Project objective
##### Evaluate the reliability of low-cost air quality sensors by validating PurpleAir PM2.5 measurements against EPA AirNow reference monitors, using dual-channel (A/B) consistency and humidity conditions to distinguish true pollution exposure from measurement bias.
## How this project came to be
##### At the onset of this project, I sought to find a dataset having to do with air quality readings so that I could take a look at the correlation between hazardous air conditions and reported asthma attacks. It was in this search that I stumbled upon PurpleAir and decided to use their sensors to satisfy the former. Although, in this process, through concerned users of their own sensors and by the admittance of the company in their own forums, I became aware of the possibility of sensors to underestimate and overestimate particulate matter readings depending on environmental factors and ware of the device. The company is aware of this case, allowing consumers to look at different conversion factors of their readings based on what meets their needs best. So while PurpleAir does not seem to oversell the efficacy of their product to consumers, with the main selling points being the sensors small size and greater affordability compared to its competitors, I was convinced to change the course of action for this project and investigate.
## Data cleaning
*cleaning_purpleair.sql, cleaning_airnow.sql* 
#### Goal: Transform and remove "bad" data from each dataset to leave us with data we can appropriately compare to each other, while also recording what proportion of the data we ingested was faulty or reported
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
    SUM(humidity = '') AS humidity_empty_ct,
    COUNT(humidity) AS humidity_ct,
    SUM(temperature = '') AS temperature_empty_ct,
    COUNT(temperature) AS temperature_ct
	FROM staging_purpleair_sensor_data
	GROUP BY sensor_index
) s
WHERE humidity_empty_ct > 0 OR temperature_empty_ct > 0
ORDER BY humidity_empty_pct DESC, temperature_empty_pct DESC;
```
![alt text](/img/humid_temp_nulls.png)