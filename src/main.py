from purpleair_sensors import filter_non_nj, get_sensors

def main():
    sensors_df = get_sensors()
    nj_sensors = filter_non_nj(sensors_df)
    nj_sensors.to_csv("data/nj_sensors.csv")



















if __name__ == "__main__":
    main()