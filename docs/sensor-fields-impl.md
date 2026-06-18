# Sensor Fields — Implementation Notes

## Added columns (migration 003)

| Column | Unit | Source |
|---|---|---|
| average_cadence | rpm | Strava summary / Garmin summaryDTO / FIT per-record avg |
| max_cadence | rpm | Garmin summaryDTO / FIT per-record max |
| average_power | watts | Strava `average_watts` / Garmin summaryDTO / FIT per-record avg |
| max_power | watts | Strava `max_watts` / Garmin summaryDTO / FIT per-record max |
| max_heartrate | bpm | Strava `max_heartrate` / Garmin summaryDTO / iGPSPORT API |
| calories | kcal | Strava `calories` / Garmin summaryDTO |
| average_temperature | °C | Strava `average_temp` / Garmin summaryDTO / FIT per-record avg |

All columns nullable. Non-cycling activities or sources without sensor data leave nil.

## Per-adapter capability

| Source | CAD | PWR | HR max | CAL | TEMP | Source of per-point L2 data |
|---|---|---|---|---|---|---|
| Strava | summary | summary | summary | summary | summary | streams API (cadence, watts, temp) |
| Garmin | summaryDTO / FIT | summaryDTO / FIT | summaryDTO | summaryDTO | summaryDTO / FIT | FIT records (cadence, power) |
| iGPSPORT | FIT per-record | FIT per-record | API avgHrm/maxHrm | nil | FIT per-record | FIT records (all fields) |
| Keep | nil | nil | nil | nil | nil | L2 has HR, pressure; no cadence/power |
| XingZhe | nil | nil | nil | nil | nil | L2 has speed/distance only |
| XOSS | nil | nil | nil | nil | nil | Summary only, no L2 |

Strava summary field mapping:
```
average_cadence     ← act["average_cadence"]
average_power       ← act["average_watts"]
max_power           ← act["max_watts"]
max_heartrate       ← act["max_heartrate"]
calories            ← act["calories"]
average_temperature ← act["average_temp"]
```

Garmin summaryDTO field mapping (camelCase as returned by Connect API):
```
average_cadence     ← summary["avgCadence"]
max_cadence         ← summary["maxCadence"]
average_power       ← summary["avgPower"]
max_power           ← summary["maxPower"]
max_heartrate       ← summary["maxHR"]
calories            ← summary["calories"]
average_temperature ← summary["avgTemperature"]
```

iGPSPORT API + FIT:
```
average_heartrate   ← act["avgHrm"]
max_heartrate       ← act["maxHrm"]
average_cadence     ← compute_sensor_summary (FIT per-record cadence avg)
max_cadence         ← compute_sensor_summary (FIT per-record max)
average_power       ← compute_sensor_summary (FIT per-record power avg)
max_power           ← compute_sensor_summary (FIT per-record max)
average_temperature ← compute_sensor_summary (FIT per-record temperature avg)
```

## Exports

| Export | Fields added |
|---|---|
| JSON | all 7 |
| CSV | all 7 as columns |
| GPX | gpxtpx:hr, gpxtpx:cad, gpxtpx:watts, gpxtpx:temp per trackpoint |
| SVG | ride category shows avg cadence + avg power in footer |
| Stats | monthly: avg_cadence, avg_power; summary: avg_cadence, avg_power |
| Dashboard | detail panel conditionally shows cadence and power |

## Historical data

Existing DB rows will have NULL for all new columns. No backfill.
New syncs will populate fields as available per adapter.
