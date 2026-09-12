## Installed and wired in (29fcf7f); the affected areas are being rebuilt and re-swept

### What the delivery contains

Both files are the standard lat/lon parquet (`id, name, ref_date, lon, lat, geom`; Italy also `address`), WGS84, no missing coordinates.

| | rows | replaces | source per the OECD quality-check document |
|---|--:|---|---|
| `ita_pharmacies.parquet` | **20,635** | ESPON 2021 point shapefile, **12,991** | Ministry of Health list (20,652 active, 20,794 unique incl. 142 closed, 1,800 without coordinates); official coordinates were duplicated/implausible, so all were geolocated by the OECD (Mapbox > ArcGIS > manual; 28 of 30 rural checks correct) |
| `hun_pharmacies.parquet` | **3,094** | — (new country) | National Center for Public Health and Pharmacy; coordinate-less source geocoded by the OECD; records starting with "DR." removed (accuracy 76 % → 90 %) |

Installed under `SourceData/NetworkModel_EU/Locations/Pharmacies/`, with the June unchecked Italy parquet kept as `ita_pharmacies_20260622_unchecked.parquet` and the OECD document and zip beside them for provenance.

### Config

`cfg/main/SourceData/Locations.dms`: Italy reads the parquet again through `CountryDataT` (the shapefile template stays for the next such delivery); Hungary added as country code `hun` in the enum and in `AvailableCountry` (19). Hungary's TomTom network was already on the source share.

### Why this is a rebuild, not just a re-sweep

The cached network (`FinalSet`) carries the connector links from the pharmacy points to the road nodes, so it depends on the pharmacy set: the descriptives run on the new Italy data failed inside the cached ITC network with `DestNode_rel: out of range`. So for Italy's five NUTS-1 areas and for Hungary the network and both ODs are rebuilt (`run_rebuild_all.ps1 -Areas ITC,ITF,ITG,ITH,ITI,Hungary`), then the descriptives for Italy, Hungary and the five, then full sweeps (both cost functions) for the six. Italy's candidate set changes as well (candidates = ≥50-pop cells ∪ pharmacy cells).

Italy goes from 12,991 to 20,635 pharmacies, so its baseline (more locations, less travel), its descriptives (residents per pharmacy 4,520 → about 2,850) and every Italian frontier move; the earlier ITF/ITG rankings on the improvement lists are superseded. Hungary is a new row everywhere: descriptives, region slide, S1/S2 tables, the point clouds and ranked lists, and the aggregate (41 → 42 disjoint areas). Its policy-typology class is still needed for the coloured charts — Chris, is Hungary in the typology deck?

Results follow here when the sweeps finish (the runs are combined with the #52 S1/S2 refinement).
