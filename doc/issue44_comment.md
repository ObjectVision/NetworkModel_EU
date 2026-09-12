## Data difference, engine limitation, gone with the engine upgrade — Finland is back in (2aeb6c0)

**What is different about the Finnish file.** `fin_pharmacies.parquet` is a GeoParquet: it carries a real point geometry column (`geom`, WGS84 CRS) where the other 19 country files carry `geom` as a plain WKT *string* and no geometry at all. That is the only difference (`ogrinfo -so`: Finland shows `Geometry: Point` and a `Layer SRS WKT`; Sweden, the Netherlands and the rest show `Geometry: None`, `SRS (unknown)`). Same attribute columns (`id, name, ref_date, lon, lat`), 797 rows, no missing coordinates, extent inside Finland.

**Why it broke in June.** The engine of that time (20.0) made a `spatial_reference` item for a gdal.vect layer with a CRS, and the pharmacy union tripped over it. So: a data difference that exposed an engine limitation, not a data error.

**Why no fix is needed now.** The project runs on the installed 20.19.1.m since 3 Sep. Probed today through exactly the `CountryDataT` shape of `Locations.dms`: the Finnish table reads (count 797), the template's `geometry` from lat/lon computes, the reader creates `geometry, id, name, ref_date, lon, lat` and nothing else — no `spatial_reference`, no error. The template's calculated geometry takes precedence over the reader's own geometry column, as it does for every other country.

**Reinstated in 2aeb6c0:** `fin` in the country enum (20) and in `AvailableCountry`; Finland in the deck order, the descriptives order and the default study areas; typology Type 2 Consensual-pluralist, HIGH (typology deck slide 14). Its TomTom network was already on the share. Network + OD rebuild, descriptives and the sweep (both cost functions) run as scheduled task `NM_finland_44`, queued behind the #53 rebuild; results follow here with the #52/#53 batch.

Iceland (`isl`) is in the enum as before but has no study area; unchanged.
