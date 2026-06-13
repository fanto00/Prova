from railway_inspector.io.database_io import save_master_db, load_master_db


def test_roundtrip(tmp_path):
    db = [{"ID_PK": "0.100", "Avg_Pos": 100.0, "Num_Occurrences": 5, "History": []}]
    p = tmp_path / "Database_damage_37-A.pkl"
    save_master_db(db, str(p))
    loaded = load_master_db(str(p))
    assert loaded[0]["ID_PK"] == "0.100"
    assert loaded[0]["Num_Occurrences"] == 5
