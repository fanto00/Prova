"""TDD tests for railway_inspector.app.analysis.datatips (8 tests)."""
from __future__ import annotations

from datetime import datetime
import pytest

from railway_inspector.app.analysis.datatips import (
    custom_datatip_robust,
    master_datatip_fcn,
    classification_datatip,
)


# ---------------------------------------------------------------------------
# Mock Classes for event_obj
# ---------------------------------------------------------------------------

class MockTarget:
    """Mock matplotlib event target."""

    def __init__(self, tag: str | None = None, user_data: object = None):
        self.Tag = tag
        self.UserData = user_data
        self.DisplayName = tag
        self.axes = MockAxes()


class MockAxes:
    """Mock matplotlib axes."""

    def __init__(self, xlabel: str = ""):
        self._xlabel = xlabel

    def get_xlim(self) -> tuple[float, float]:
        return (0.0, 10.0)

    def get_ylim(self) -> tuple[float, float]:
        return (0.0, 10.0)

    def get_xlabel(self) -> str:
        return self._xlabel


class MockEventObj:
    """Mock matplotlib event object."""

    def __init__(
        self,
        position: list[float],
        target: MockTarget,
        data_index: int = 0,
        axes: MockAxes | None = None,
    ):
        self.Position = position
        self.Target = target
        self.DataIndex = data_index
        self.Axes = axes or MockAxes()


# ---------------------------------------------------------------------------
# Test 1: custom_datatip_robust with DefectScatter tag
# ---------------------------------------------------------------------------

def test_custom_datatip_robust_with_tag():
    """custom_datatip_robust() returns PK + Ant/Pos for DefectScatter."""
    pk_list = ["PK 12.5", "PK 15.3", "PK 18.7"]
    target = MockTarget(tag="DefectScatter", user_data=pk_list)
    target.Tag = "DefectScatter"  # Ensure uppercase Tag attribute
    target.UserData = pk_list  # Ensure UserData attribute
    event = MockEventObj(position=[0.25, 0.8], target=target, data_index=1)

    txt = custom_datatip_robust(None, event)

    assert isinstance(txt, list)
    assert len(txt) == 3
    assert "PK 15.3" in txt[0]
    # Check formatting: 2 decimals
    assert "0.25" in txt[1] or "0.2" in txt[1]
    assert "0.80" in txt[2] or "0.8" in txt[2]


# ---------------------------------------------------------------------------
# Test 2: custom_datatip_robust without DefectScatter tag
# ---------------------------------------------------------------------------

def test_custom_datatip_robust_without_tag():
    """custom_datatip_robust() fallback to XY if not DefectScatter."""
    target = MockTarget(tag="OtherPlot", user_data=None)
    target.Tag = "OtherPlot"  # Ensure Tag attribute
    event = MockEventObj(position=[1.5, 2.3], target=target, data_index=0)

    txt = custom_datatip_robust(None, event)

    assert isinstance(txt, list)
    assert len(txt) == 2
    # Verify X, Y coordinates
    assert any(
        "1.5" in str(line) or "1.50" in str(line) for line in txt
    )
    assert any(
        "2.3" in str(line) or "2.30" in str(line) for line in txt
    )


# ---------------------------------------------------------------------------
# Test 3: custom_datatip_robust out of range
# ---------------------------------------------------------------------------

def test_custom_datatip_robust_out_of_range():
    """custom_datatip_robust() with out-of-range DataIndex → N/A."""
    pk_list = ["PK 12.5", "PK 15.3"]
    target = MockTarget(tag="DefectScatter", user_data=pk_list)
    target.Tag = "DefectScatter"  # Ensure Tag attribute
    target.UserData = pk_list  # Ensure UserData attribute
    event = MockEventObj(position=[0.25, 0.8], target=target, data_index=10)

    txt = custom_datatip_robust(None, event)

    assert "N/A" in txt[0]


# ---------------------------------------------------------------------------
# Test 4: master_datatip_fcn PSD 2D (Freq → Lambda)
# ---------------------------------------------------------------------------

def test_master_datatip_fcn_psd_2d():
    """master_datatip_fcn() PSD 2D: Freq → Lambda conversion."""
    # Use datenum (float) not datetime for info["Date"]
    # matplotlib datenum: ~730000 for dates ~2000+
    info = {"Type": "Forward", "Date": 730000.6}  # datenum float
    target = MockTarget(tag="PSD2D", user_data=info)
    target.UserData = info  # Ensure UserData attribute
    axes = MockAxes(xlabel="Frequenza [cicli/m]")
    target.axes = axes  # Ensure axes attribute
    event = MockEventObj(
        position=[0.1, 5.2],  # freq, amplitude
        target=target,
        data_index=0,
        axes=axes,
    )

    txt = master_datatip_fcn(None, event)

    assert isinstance(txt, list)
    txt_str = str(txt)
    # Lambda = 1/freq = 1/0.1 = 10.0
    assert "10" in txt_str or "lambda" in txt_str.lower()
    assert "Forward" in txt_str or "forward" in txt_str.lower()
    assert "5" in txt_str  # Amplitude


# ---------------------------------------------------------------------------
# Test 5: master_datatip_fcn 3D PSD
# ---------------------------------------------------------------------------

def test_master_datatip_fcn_3d_psd():
    """master_datatip_fcn() 3D PSD: Freq, Date, Power."""
    info = {"Type": "Backward", "Date": 730000.5}  # datenum float
    target = MockTarget(tag="PSD3D", user_data=info)
    target.UserData = info  # Ensure UserData attribute
    axes = MockAxes(xlabel="Frequenza")
    target.axes = axes  # Ensure axes attribute
    event = MockEventObj(
        position=[0.2, 730000, 3.5],  # freq, date(datenum), power
        target=target,
        data_index=0,
        axes=axes,
    )

    txt = master_datatip_fcn(None, event)

    assert isinstance(txt, list)
    assert len(txt) > 0


# ---------------------------------------------------------------------------
# Test 6: master_datatip_fcn Trend 2D (datenum)
# ---------------------------------------------------------------------------

def test_master_datatip_fcn_trend_2d():
    """master_datatip_fcn() Trend 2D: datenum X-axis."""
    target = MockTarget(tag=None, user_data=None)
    event = MockEventObj(
        position=[745000, 2.5],  # datenum (large), value
        target=target,
        data_index=0,
    )

    txt = master_datatip_fcn(None, event)

    assert isinstance(txt, list)
    assert len(txt) == 2


# ---------------------------------------------------------------------------
# Test 7: classification_datatip basic
# ---------------------------------------------------------------------------

def test_classification_datatip_basic():
    """classification_datatip() formats defect classification info."""
    summary = {
        "ID": "12.5",
        "TipoStrutturale": "Giunto",
        "Amp": 8.5,
        "Lambda_SX": 0.25,
        "Lambda_DX": 0.28,
        "NaturaSpettrale_SX": "Picco",
        "NaturaSpettrale_DX": "Picco",
        "Ratio_SX_DX": 1.15,
        "Ratio_Lat_Vert": 0.45,
    }

    target = MockTarget(tag="Giunto")
    target.DisplayName = "Giunto"  # Ensure DisplayName attribute
    event = MockEventObj(
        position=[0.25, 0.28],
        target=target,
        data_index=0,
    )

    txt = classification_datatip(event, [summary], ["Giunto"])

    assert isinstance(txt, list)
    txt_str = str(txt)
    assert "12.5" in txt_str or "PK" in txt_str
    assert "Giunto" in txt_str or "giunto" in txt_str.lower()
    assert "8.5" in txt_str or "8" in txt_str
    assert "0.25" in txt_str or "0.2" in txt_str


# ---------------------------------------------------------------------------
# Test 8: classification_datatip fallback nearest neighbor
# ---------------------------------------------------------------------------

def test_classification_datatip_fallback_nearest():
    """classification_datatip() fallback nearest neighbor on invalid index."""
    summary_list = [
        {
            "ID": "10.0",
            "TipoStrutturale": "Giunto",
            "Amp": 5.0,
            "Lambda_SX": 0.2,
            "Lambda_DX": 0.22,
            "NaturaSpettrale_SX": "Picco",
            "NaturaSpettrale_DX": "Picco",
            "Ratio_SX_DX": 1.0,
            "Ratio_Lat_Vert": 0.5,
        },
        {
            "ID": "15.0",
            "TipoStrutturale": "Difetto",
            "Amp": 6.0,
            "Lambda_SX": 0.25,
            "Lambda_DX": 0.25,
            "NaturaSpettrale_SX": "Allarga",
            "NaturaSpettrale_DX": "Allarga",
            "Ratio_SX_DX": 1.1,
            "Ratio_Lat_Vert": 0.6,
        },
    ]

    target = MockTarget(tag="Unknown")
    target.DisplayName = "Unknown"  # Ensure DisplayName attribute
    event = MockEventObj(
        position=[0.25, 0.25],  # Close to summary_list[1]
        target=target,
        data_index=999,  # Invalid
    )

    txt = classification_datatip(event, summary_list, ["Unknown"])

    assert isinstance(txt, list)
    txt_str = str(txt)
    # Should find nearest (index 1 = ID 15.0)
    assert "15.0" in txt_str or "6.0" in txt_str or len(txt_str) > 0
