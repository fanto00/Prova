import numpy as np
from railway_inspector.config import default_config
from railway_inspector.database.pipeline import compute_geo_signal, determine_orientation, align_and_crop_run

def test_compute_geo_signal_is_zscored():
    c = default_config()
    space_raw = np.arange(0, 100, c.SPATIAL_RES)
    data = {"space_neutral": space_raw, "curve": np.sin(space_raw)}
    geo, axis = compute_geo_signal(data, c)
    assert abs(np.mean(geo)) < 1e-3
    assert abs(np.std(geo) - 1.0) < 1e-2

def test_determine_orientation_from_field():
    assert determine_orientation({"orientation": "moving forward"}) == "moving forward"

def test_determine_orientation_from_space_parameters():
    assert determine_orientation({"space_parameters": {"front": -3.0}}) == "moving backward"
    assert determine_orientation({"space_parameters": {"front": 2.0}}) == "moving forward"

def test_align_and_crop_recovers_known_shift():
    c = default_config()
    # Master: feature (hanning pulse) at sample n//2, spatial axis 0..199.996 m.
    n = 50000
    space = np.arange(n) * c.SPATIAL_RES   # 0 .. ~200 m at 4 mm/sample
    feature_m = np.zeros(n)
    feature_m[n//2-50:n//2+50] = np.hanning(100)   # pulse centred at ~100 m

    master = {"space_neutral": space.copy(), "curve": feature_m.copy(),
              "orientation": "moving forward", "left_sensor_front": feature_m.copy()}
    geo_master, _ = compute_geo_signal(master, c)

    # Run: SAME spatial axis, but feature displaced +3 m in sample space
    # (750 samples at 0.004 m/sample).  The xcorr must recover this displacement.
    shift_true = 3.0                                # metres
    offset_samples = int(round(shift_true / c.SPATIAL_RES))   # = 750
    feature_r = np.zeros(n)
    feature_r[n//2-50+offset_samples:n//2+50+offset_samples] = np.hanning(100)

    run = {"space_neutral": space.copy(), "curve": feature_r.copy(),
           "orientation": "moving forward", "left_sensor_front": feature_r.copy()}

    res = align_and_crop_run(run, geo_master, "moving forward",
                             space.min(), space.max(), c)
    assert res["valid"] is True
    # The xcorr lag is -750 → shift = -3.0 m: |shift| should equal shift_true
    assert abs(abs(res["shift"]) - shift_true) < 0.1
