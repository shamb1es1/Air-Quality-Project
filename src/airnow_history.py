from api_utils import get_api_key, get_bounding_box
import pandas as pd
import requests

endpoint = 'https://www.airnowapi.org/aq/data/'

key = get_api_key("AirNow")

# Get coordinates from api_utils
NW_LAT, NW_LNG, SE_LAT, SE_LNG = get_bounding_box()

params = {
    'bbox': f"{NW_LNG},{SE_LAT},{SE_LNG},{NW_LAT}",
    'startdate': '2026-01-01T00:00',
    'enddate': '2026-01-03T00:00',
    'parameters': 'pm25',
    'datatype': 'B',
    'format': 'application/json',
    'api_key': key,
    'verbose': 1,
    'includerawconcentrations': 1
}

response = requests.get(url=endpoint, params=params)
response.raise_for_status()
data = pd.DataFrame(response.json())
data.to_csv("data/airnow_data.csv", index=False)
print(response.json())
