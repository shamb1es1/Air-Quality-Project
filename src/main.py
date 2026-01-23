import pandas as pd
import geo_utils
from purpleair_sensors import get_sensors
from purpleair_history import call_histories, get_sensor_indexes
import airnow_history


# Driver for all other function calls
def main():
    # For purpleair_sensors.py
    sensors_df = get_sensors()
    purpleair_sensors = geo_utils.filter_non_nj(sensors_df)
    purpleair_sensors.to_csv("data/purpleair_sensors.csv")
    
    # For purpleair_history.py
    sensor_indexes = get_sensor_indexes("data/purpleair_sensors.csv")
    good, bad = call_histories(sensor_indexes)
    good.to_csv("data/purpleair_sensor_data.csv", index=False)
    bad_df = pd.DataFrame(bad, columns=["sensor_index", "error"])
    bad_df.to_csv("data/bad_sensor_calls.csv", index=False)

    airnow_df = airnow_history.get_airnow_history()
    airnow_df.to_csv("data/airnow_sensor_data.csv", index=False)


if __name__ == "__main__":
    main()