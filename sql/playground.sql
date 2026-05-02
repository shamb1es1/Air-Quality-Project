SELECT COUNT(*) FROM data_matched
UNION ALL
SELECT COUNT(*) FROM minimal_data_matched
UNION ALL
SELECT COUNT(*) FROM purpleair_sensor_data
UNION ALL
SELECT COUNT(*) FROM minimal_purpleair;

SELECT p.*
FROM purpleair_sensor_data p
LEFT JOIN data_matched m
  ON p.sensor_index = m.sensor_index
 AND p.datetime_timestamp = m.datetime_timestamp
WHERE m.sensor_index IS NULL;

SELECT COUNT(*)
FROM purpleair_sensor_data p
LEFT JOIN airnow_sensor_data a
  ON p.datetime_timestamp = a.datetime_timestamp
WHERE a.datetime_timestamp IS NULL;

SELECT COUNT(*)
FROM purpleair_sensor_data p
LEFT JOIN sensor_distances d
  ON p.sensor_index = d.sensor_index
WHERE d.sensor_index IS NULL;

SELECT DISTINCT site_id
FROM airnow_sites
WHERE site_id NOT IN (SELECT site_id FROM sensor_distances);

SELECT DISTINCT purpleair_sensor_data.sensor_index FROM purpleair_sensor_data
LEFT JOIN sensor_distances ON purpleair_sensor_data.sensor_index = sensor_distances.sensor_index
WHERE sensor_distances.sensor_index IS NULL;

SELECT 
  d.site_id,
  COUNT(*) AS unmatched_rows
FROM purpleair_sensor_data p
JOIN sensor_distances d
  ON p.sensor_index = d.sensor_index
LEFT JOIN airnow_sensor_data a
  ON a.site_id = d.site_id
 AND a.datetime_timestamp = p.datetime_timestamp
WHERE a.site_id IS NULL
GROUP BY d.site_id
ORDER BY unmatched_rows DESC;

SELECT DISTINCT
  p.datetime_timestamp,
  d.site_id AS nearest_airnow_site
FROM purpleair_sensor_data p
JOIN sensor_distances d
  ON p.sensor_index = d.sensor_index
LEFT JOIN airnow_sensor_data a
  ON a.site_id = d.site_id
 AND a.datetime_timestamp = p.datetime_timestamp
WHERE a.datetime_timestamp IS NULL
ORDER BY d.site_id, p.datetime_timestamp;

SELECT
  p.sensor_index,
  d.site_id AS nearest_airnow_site_id,
  d.dist_miles,
  p.datetime_timestamp
FROM purpleair_sensor_data p
JOIN sensor_distances d
  ON p.sensor_index = d.sensor_index
LEFT JOIN airnow_sensor_data a
  ON a.site_id = d.site_id
 AND a.datetime_timestamp = p.datetime_timestamp
WHERE a.site_id IS NULL
ORDER BY d.site_id, p.datetime_timestamp, p.sensor_index;

SELECT * FROM airnow_sensor_data WHERE site_id = 1 AND datetime_timestamp = '2025-01-11 18:00:00';

SELECT
  d.site_id AS nearest_airnow_site_id,
  p.datetime_timestamp,
  COUNT(*) AS affected_purpleair_rows
FROM purpleair_sensor_data p
JOIN sensor_distances d
  ON p.sensor_index = d.sensor_index
LEFT JOIN airnow_sensor_data a
  ON a.site_id = d.site_id
 AND a.datetime_timestamp = p.datetime_timestamp
WHERE a.site_id IS NULL
GROUP BY d.site_id, p.datetime_timestamp
ORDER BY d.site_id, p.datetime_timestamp;

SELECT COUNT(*) AS no_airnow_reading_for_nearest_site
FROM purpleair_sensor_data p
JOIN sensor_distances d
  ON p.sensor_index = d.sensor_index
LEFT JOIN airnow_sensor_data a
  ON a.site_id = d.site_id
 AND a.datetime_timestamp = p.datetime_timestamp
WHERE a.site_id IS NULL;

SELECT COUNT(*)
FROM airnow_sensor_data a
JOIN (
	SELECT site_id FROM airnow_sites
	WHERE site_id NOT IN (
		SELECT DISTINCT site_id FROM data_matched
	)) AS i
ON a.site_id = i.site_id
GROUP BY i.site_id;

SELECT COUNT(*) FROM airnow_sensor_data WHERE site_id = 4;

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
select count(*) from purpleair_sensor_data;
select count(*) from data_matched;
SELECT * 
FROM purpleair_sensor_data
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/purpleair_cleaned.csv'
FIELDS TERMINATED BY ',' 
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n';
select * from data_matched limit 5;
SELECT * 
FROM data_matched
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/data_matched.csv'
FIELDS TERMINATED BY ',' 
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n';