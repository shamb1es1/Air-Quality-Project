from pathlib import Path
import geopandas as gpd
import pandas as pd


# Filter sensors to only those located within New Jersey
def filter_non_nj(sensors: pd.DataFrame) -> pd.DataFrame:
    nj_path = Path("data/nj_coordinates/cb_2024_34_sldu_500k.shp")
    nj = gpd.read_file(nj_path).to_crs("EPSG:4326")
    gdf = gpd.GeoDataFrame( 
        sensors.copy(),
        geometry=gpd.points_from_xy(sensors["longitude"], sensors["latitude"]),
        crs="EPSG:4326"
    )
    nj_sensors = gpd.sjoin(gdf, nj, how="inner", predicate="within")
    out = nj_sensors.loc[:, sensors.columns].copy().sort_index()
    return pd.DataFrame(out)