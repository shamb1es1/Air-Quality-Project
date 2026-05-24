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

SELECT * 
FROM airnow_sensor_data
JOIN airnow_sites ON airnow_sensor_data.site_id = airnow_sites.site_id
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/airnow_cleaned.csv'
FIELDS TERMINATED BY ',' 
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n';

SELECT * 
FROM airnow_sensor_data
JOIN airnow_sites ON airnow_sensor_data.site_id = airnow_sites.site_id
limit 5;