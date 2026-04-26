SELECT COUNT(*) FROM data_matched
UNION ALL
SELECT COUNT(*) FROM minimal_data_matched
UNION ALL
SELECT COUNT(*) FROM purpleair_sensor_data
UNION ALL
SELECT COUNT(*) FROM minimal_data_matched;

SELECT COUNT(*)
FROM airnow_sensor_data a
JOIN (
	SELECT site_id FROM airnow_sites
	WHERE site_id NOT IN (
		SELECT DISTINCT site_id FROM data_matched
	)) AS i
ON a.site_id = i.site_id
GROUP BY i.site_id;

SELECT * FROM data_matched;
SELECT * FROM minimal_data_matched;
SELECT * FROM minimal_purpleair;
SELECT * FROM purpleair_sensor_data;

SELECT COUNT(*) FROM staging_purpleair_sensor_data;
SELECT COUNT(*) FROM minimal_purpleair;

SELECT AVG(pm25_atm_a), datetime_timestamp FROM purpleair_sensor_data
WHERE pm25_atm_a <= 202.1 AND pm25_atm_b <= 202.1 AND pm25_cf_1_a <= 202.1 AND pm25_cf_1_b <= 202.1
group by datetime_timestamp 
ORDER BY datetime_timestamp ASC LIMIT 10;

SELECT * 
FROM purpleair_sensor_data
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/purpleair_cleaned.csv'
FIELDS TERMINATED BY ',' 
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n';