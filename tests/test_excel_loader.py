import math
import pandas as pd
import pytest
from railway_inspector.io.excel_loader import load_infrastructure_map, load_joints_map, to_num


# ---------------------------------------------------------------------------
# to_num
# ---------------------------------------------------------------------------

def test_to_num_float():
    assert to_num(3.5) == 3.5

def test_to_num_int():
    assert to_num(7) == 7.0

def test_to_num_string_numeric():
    assert to_num("7") == 7.0

def test_to_num_string_float():
    assert to_num("3.14") == pytest.approx(3.14)

def test_to_num_string_invalid():
    assert math.isnan(to_num("abc"))

def test_to_num_none():
    assert math.isnan(to_num(None))

def test_to_num_nan_passthrough():
    import numpy as np
    assert math.isnan(to_num(float("nan")))

def test_to_num_numpy_scalar():
    import numpy as np
    assert to_num(np.float64(2.5)) == 2.5


# ---------------------------------------------------------------------------
# load_joints_map
# ---------------------------------------------------------------------------

def test_load_joints_map_reads_positions(tmp_path):
    p = tmp_path / "giunti.xlsx"
    df = pd.DataFrame(
        {
            "Stations": ["37-A", "37-A"],
            "Position": [100.0, 250.0],
            "Joint": ["J1", "J2"],
            "Shared": ["", ""],
        }
    )
    with pd.ExcelWriter(p, engine="openpyxl") as w:
        df.to_excel(w, sheet_name="M2-Pari", index=False)
    J = load_joints_map(str(p), "pari")
    assert list(J["Position"]) == [100.0, 250.0]
    assert set(J["Stations"]) == {"37-A"}


def test_load_joints_map_filters_by_type(tmp_path):
    """Only sheets whose name contains the type string (case-insensitive) are read.
    Note: MATLAB uses contains() substring match, so 'dispari' DOES contain 'pari'.
    Use a type string that does NOT appear as a substring in unwanted sheet names.
    """
    p = tmp_path / "giunti.xlsx"
    df_match = pd.DataFrame(
        {"Stations": ["A"], "Position": [10.0], "Joint": ["J1"], "Shared": [""]}
    )
    df_no_match = pd.DataFrame(
        {"Stations": ["B"], "Position": [20.0], "Joint": ["J2"], "Shared": [""]}
    )
    with pd.ExcelWriter(p, engine="openpyxl") as w:
        df_match.to_excel(w, sheet_name="M1-Binario", index=False)
        df_no_match.to_excel(w, sheet_name="M1-Altro", index=False)
    J = load_joints_map(str(p), "binario")
    assert list(J["Position"]) == [10.0]
    assert set(J["Stations"]) == {"A"}


def test_load_joints_map_skips_nan_position(tmp_path):
    """Rows where Position cannot be converted to float are dropped."""
    p = tmp_path / "giunti.xlsx"
    df = pd.DataFrame(
        {
            "Stations": ["A", "B", "C"],
            "Position": [10.0, "N/A", 30.0],
            "Joint": ["J1", "J2", "J3"],
            "Shared": ["", "", ""],
        }
    )
    with pd.ExcelWriter(p, engine="openpyxl") as w:
        df.to_excel(w, sheet_name="Track-Pari", index=False)
    J = load_joints_map(str(p), "pari")
    assert list(J["Position"]) == [10.0, 30.0]


def test_load_joints_map_missing_joint_and_shared(tmp_path):
    """Sheets without Joint/Shared columns still load with empty strings."""
    p = tmp_path / "giunti.xlsx"
    df = pd.DataFrame({"Stations": ["A"], "Position": [5.0]})
    with pd.ExcelWriter(p, engine="openpyxl") as w:
        df.to_excel(w, sheet_name="M1-Pari", index=False)
    J = load_joints_map(str(p), "pari")
    assert list(J["Position"]) == [5.0]
    assert list(J["Joint"]) == [""]
    assert list(J["Shared"]) == [""]


def test_load_joints_map_uses_fixed_over_position(tmp_path):
    """'fixed' column takes priority over 'position'."""
    p = tmp_path / "giunti.xlsx"
    df = pd.DataFrame(
        {
            "Stations": ["A"],
            "Fixed": [99.0],
            "Position": [1.0],  # should be ignored
            "Joint": ["J1"],
            "Shared": [""],
        }
    )
    with pd.ExcelWriter(p, engine="openpyxl") as w:
        df.to_excel(w, sheet_name="M1-Pari", index=False)
    J = load_joints_map(str(p), "pari")
    assert list(J["Position"]) == [99.0]


def test_load_joints_map_returns_empty_when_no_matching_sheet(tmp_path):
    """Use a type string that genuinely does not appear in the sheet name."""
    p = tmp_path / "giunti.xlsx"
    df = pd.DataFrame({"Stations": ["A"], "Position": [1.0]})
    with pd.ExcelWriter(p, engine="openpyxl") as w:
        df.to_excel(w, sheet_name="M1-Altro", index=False)
    J = load_joints_map(str(p), "binario")
    assert J.empty
    assert list(J.columns) == ["Stations", "Position", "Joint", "Shared"]


# ---------------------------------------------------------------------------
# load_infrastructure_map
# ---------------------------------------------------------------------------

def _make_infra_row(col1="DESC", col13="EXTRA", p1=10.0, p2=5.0):
    """Build a 21-column row (1-based cols 1, 13, 20, 21 matter)."""
    row = [""] * 21
    row[0] = col1        # col 1 (0-based 0)
    row[12] = col13      # col 13 (0-based 12)
    row[19] = p1         # col 20 (0-based 19)
    row[20] = p2         # col 21 (0-based 20)
    return row


def test_load_infrastructure_map_dispari(tmp_path):
    p = tmp_path / "infra.xlsx"
    header = ["H"] * 21
    data_row = _make_infra_row("LineA", "Seg1", 100.0, 200.0)
    df = pd.DataFrame([header, header, data_row])  # rows 0,1 = header junk; row 2 = first data (MATLAB row 3)
    with pd.ExcelWriter(p, engine="openpyxl") as w:
        df.to_excel(w, sheet_name="1 d", index=False, header=False)
    result = load_infrastructure_map(str(p), "dispari")
    assert len(result) == 1
    assert result.iloc[0]["Pk_Inizio"] == 100.0
    assert result.iloc[0]["Pk_Fine"] == 200.0
    assert result.iloc[0]["Tipo"] == "Elemento"
    assert "LineA" in result.iloc[0]["Descrizione"]
    assert "Seg1" in result.iloc[0]["Descrizione"]


def test_load_infrastructure_map_pari(tmp_path):
    p = tmp_path / "infra.xlsx"
    header = ["H"] * 21
    data_row = _make_infra_row("LineB", "Seg2", 50.0, 75.0)
    df = pd.DataFrame([header, header, data_row])
    with pd.ExcelWriter(p, engine="openpyxl") as w:
        df.to_excel(w, sheet_name="1 p", index=False, header=False)
    result = load_infrastructure_map(str(p), "pari")
    assert len(result) == 1
    assert result.iloc[0]["Pk_Inizio"] == 50.0
    assert result.iloc[0]["Foglio"] == "1 p"


def test_load_infrastructure_map_skips_non_numeric(tmp_path):
    """Rows where p1 or p2 are not numeric are skipped."""
    p = tmp_path / "infra.xlsx"
    header = ["H"] * 21
    bad_row = _make_infra_row(p1="N/A", p2=5.0)
    good_row = _make_infra_row(p1=10.0, p2=5.0)
    df = pd.DataFrame([header, header, bad_row, good_row])
    with pd.ExcelWriter(p, engine="openpyxl") as w:
        df.to_excel(w, sheet_name="1 d", index=False, header=False)
    result = load_infrastructure_map(str(p), "dispari")
    assert len(result) == 1
    assert result.iloc[0]["Pk_Inizio"] == 10.0


def test_load_infrastructure_map_skips_zero_sum(tmp_path):
    """Rows where p1+p2 <= 0 are skipped."""
    p = tmp_path / "infra.xlsx"
    header = ["H"] * 21
    zero_row = _make_infra_row(p1=0.0, p2=0.0)
    good_row = _make_infra_row(p1=1.0, p2=2.0)
    df = pd.DataFrame([header, header, zero_row, good_row])
    with pd.ExcelWriter(p, engine="openpyxl") as w:
        df.to_excel(w, sheet_name="1 d", index=False, header=False)
    result = load_infrastructure_map(str(p), "dispari")
    assert len(result) == 1
    assert result.iloc[0]["Pk_Inizio"] == 1.0


def test_load_infrastructure_map_continues_on_missing_sheet(tmp_path):
    """Missing sheet '1 dd' does not crash; data from '1 d' is returned."""
    p = tmp_path / "infra.xlsx"
    header = ["H"] * 21
    data_row = _make_infra_row(p1=10.0, p2=5.0)
    df = pd.DataFrame([header, header, data_row])
    with pd.ExcelWriter(p, engine="openpyxl") as w:
        df.to_excel(w, sheet_name="1 d", index=False, header=False)
        # '1 dd' intentionally missing
    result = load_infrastructure_map(str(p), "dispari")
    assert len(result) == 1


def test_load_infrastructure_map_empty_returns_correct_columns(tmp_path):
    p = tmp_path / "infra.xlsx"
    df = pd.DataFrame([["placeholder"]])
    with pd.ExcelWriter(p, engine="openpyxl") as w:
        df.to_excel(w, sheet_name="dummy", index=False, header=False)
    result = load_infrastructure_map(str(p), "dispari")
    assert result.empty
    assert list(result.columns) == ["Foglio", "Tipo", "Pk_Inizio", "Pk_Fine", "Descrizione"]
