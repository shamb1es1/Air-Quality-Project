DELIMITER $$

DROP PROCEDURE IF EXISTS drop_index_if_exists $$

CREATE PROCEDURE drop_index_if_exists(
    IN p_table_name VARCHAR(128),
    IN p_index_name VARCHAR(128)
)
BEGIN
    DECLARE v_exists INT DEFAULT 0;
    DECLARE v_sql TEXT;

    -- Does the index exist on this table in the current database?
    SELECT COUNT(*) INTO v_exists
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_table_name AND INDEX_NAME = p_index_name;

    IF v_exists > 0 THEN
        SET v_sql = CONCAT(
            'DROP INDEX `', REPLACE(p_index_name, '`', '``'),
            '` ON `', REPLACE(DATABASE(), '`', '``'),
            '`.`', REPLACE(p_table_name, '`', '``'),
            '`'
        );
        
        SET @sql_stmt = v_sql;
        PREPARE stmt FROM @sql_stmt;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END $$
DELIMITER ;

CALL drop_index_if_exists('staging_purpleair_sensors', 'purpleair_sensor_index_index');
CALL drop_index_if_exists('staging_purpleair_sensor_data', 'purpleair_sensor_history_index_index');

CREATE INDEX purpleair_sensor_index_index 
ON staging_purpleair_sensors (sensor_index(6));

CREATE INDEX purpleair_sensor_history_index_index 
ON staging_purpleair_sensor_data (sensor_index(6))