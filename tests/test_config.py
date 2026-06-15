from railway_inspector.config import CFG, default_config

def test_default_config_values():
    c = default_config()
    assert c.SPATIAL_RES == 0.004
    assert c.WINDOW_FINAL == 5.0
    assert c.WINDOW_EXTRACT == 7.0
    assert c.fmin == 2
    assert c.fmax == 350
    assert c.ABS_RMS_THRESH == 5.0
    assert c.RMS_MUL == 3
    assert c.CROSS_TOL == 1.5
    assert c.UPSAMPLE_FACTOR == 4
    assert c.JOINT_WINDOW == 7.0

def test_config_is_mutable_dataclass():
    c = default_config()
    c.ROUTE_FILTER = "42"
    assert c.ROUTE_FILTER == "42"

def test_cfg_has_ipi_constants():
    from railway_inspector.config import default_config
    c = default_config()
    assert c.WINDOW_SIZE == 5.0
    assert c.IPI_PCA_K == 2
    assert c.IPI_PCA_MIN_RUNS == 30
    assert c.IPI_PCA_BONUS == 20
    assert c.IPI_PCA_SENS == 50
    assert c.IPI_PCA_EXCUR_BONUS == 5
    assert c.IPI_PCA_EXCUR_DAYS == 7
    assert c.IPI_RECENT_DAYS == 30
    assert c.IPI_MIN_HISTORY_DAYS == 45
    assert c.IPI_MIN_DAYS == 10
