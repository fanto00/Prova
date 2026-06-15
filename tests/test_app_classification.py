import numpy as np
import pytest
from railway_inspector.app.analysis.classification import _mode_categorical


def test_mode_categorical_clear_winner():
    assert _mode_categorical(["A", "B", "A", "A"]) == "A"


def test_mode_categorical_tie_returns_alphabetically_smallest():
    # "Front-Left" and "Rear-Right" each appear twice -> alphabetical first
    cells = ["Rear-Right", "Front-Left", "Rear-Right", "Front-Left"]
    assert _mode_categorical(cells) == "Front-Left"


def test_mode_categorical_single():
    assert _mode_categorical(["Center-Center"]) == "Center-Center"
