import datetime as dt
import numpy as np
import pytest
from railway_inspector.app.analysis.classification import _mode_categorical
from railway_inspector.app.analysis.classification import classify_defects
from railway_inspector.config import default_config

SENSORS = ['left_sensor_front', 'left_sensor_rear', 'right_sensor_front',
           'right_sensor_rear', 'right_sensor_front_lat', 'right_sensor_rear_lat',
           'left_sensor_front_lat', 'left_sensor_rear_lat']


def _run(date, amps, n=400):
    """amps keyed by sensor name -> a flat signal of constant |value| (so get_amp == value)."""
    filt = {}
    for s in SENSORS:
        v = amps.get(s, 0.0)
        filt[s] = np.full(n, v)
    return {"Date": date, "Data": {"Filt": filt}}


def test_mode_categorical_clear_winner():
    assert _mode_categorical(["A", "B", "A", "A"]) == "A"


def test_mode_categorical_tie_returns_alphabetically_smallest():
    # "Front-Left" and "Rear-Right" each appear twice -> alphabetical first
    cells = ["Rear-Right", "Front-Left", "Rear-Right", "Front-Left"]
    assert _mode_categorical(cells) == "Front-Left"


def test_mode_categorical_single():
    assert _mode_categorical(["Center-Center"]) == "Center-Center"


def test_classify_empty_history_gives_nd_record():
    cfg = default_config()
    DB = [{"ID_PK": "1.234", "Avg_Pos": 1234.0, "History": []}]
    out = classify_defects(DB, cfg)
    assert len(out) == 1
    assert out[0]["ID"] == "1.234"
    assert out[0]["Pos"] == 1234.0
    assert out[0]["Cella_Dominante"] == "N/D"
    assert out[0]["Lambda_SX"] == 0
    assert out[0]["Lambda_DX"] == 0


def test_classify_dominant_cell_and_ratios():
    cfg = default_config()
    # Build a defect whose runs are strongly Left (SX>>DX) and Front (F>>R).
    # A_SX_F=A_SX_R=10, A_DX_F=A_DX_R=1 -> Ratio_SX_DX = 20/2 = 10 > 2 -> 'Left'
    # Ratio_Front_Rear = (10+1)/(10+1) = 1 -> 'Center'  => cell 'Center-Left'
    amps = {'left_sensor_front': 10.0, 'left_sensor_rear': 10.0,
            'right_sensor_front': 1.0, 'right_sensor_rear': 1.0,
            'left_sensor_front_lat': 2.0}
    runs = [_run(dt.datetime(2026, 5, d), amps) for d in (1, 2, 3)]
    DB = [{"ID_PK": "9.9", "Avg_Pos": 9900.0, "History": runs}]
    out = classify_defects(DB, cfg)
    rec = out[0]
    assert rec["Cella_Dominante"] == "Center-Left"
    assert rec["Mese_Ultimo"] == "2026_05"
    assert rec["Ratio_SX_DX_Avg"] == pytest.approx(10.0)
    assert rec["Ratio_FR_Avg"] == pytest.approx(1.0)
    # Ratio_Lat_Vert = max_lat(2)/max_vert(10) = 0.2
    assert rec["Ratio_Lat_Vert_Avg"] == pytest.approx(0.2)
    assert rec["Amp"] == pytest.approx(10.0)
    # lambdas are finite and labels consistent with lambda_to_label
    from railway_inspector.app.analysis.classification import L_GIUNTO, L_IRREG, L_DEFORM
    from railway_inspector.app.analysis.spectrum import lambda_to_label
    assert rec["Lambda_SX"] >= 0
    assert rec["NaturaSpettrale_SX"] == lambda_to_label(rec["Lambda_SX"], L_GIUNTO, L_IRREG, L_DEFORM)


def test_classify_uses_last_month():
    cfg = default_config()
    amps_left = {'left_sensor_front': 10.0, 'left_sensor_rear': 10.0,
                 'right_sensor_front': 1.0, 'right_sensor_rear': 1.0}
    amps_right = {'left_sensor_front': 1.0, 'left_sensor_rear': 1.0,
                  'right_sensor_front': 10.0, 'right_sensor_rear': 10.0}
    runs = [_run(dt.datetime(2026, 1, 5), amps_left),    # Jan -> Left
            _run(dt.datetime(2026, 3, 5), amps_right)]   # Mar -> Right (last month)
    DB = [{"ID_PK": "x", "Avg_Pos": 0.0, "History": runs}]
    out = classify_defects(DB, cfg)
    assert out[0]["Mese_Ultimo"] == "2026_03"
    assert out[0]["Cella_Dominante"] == "Center-Right"
