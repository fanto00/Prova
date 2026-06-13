"""
Load MATLAB .mat files and parse run dates.

Replicates MATLAB behavior from Database_Allineamento_nomax.m lines 156-167:
- Load section_extracted from .mat file
- Parse run_date from time_start field or from filename
"""

from datetime import datetime
from typing import Any, Dict

import numpy as np
from scipy.io import loadmat


def mat_struct_to_dict(mat_struct: Any) -> Dict[str, Any]:
    """
    Convert a scipy.io mat_struct to a Python dict.

    Recursively handles nested structures.

    Args:
        mat_struct: A mat_struct object from scipy.io.loadmat with struct_as_record=False

    Returns:
        dict: A dictionary mapping field names to their values
    """
    if not hasattr(mat_struct, "_fieldnames"):
        # Not a struct, return as-is
        return mat_struct

    result = {}
    for field_name in mat_struct._fieldnames:
        field_value = getattr(mat_struct, field_name)

        # If the field value is a single-element array, unwrap it
        if isinstance(field_value, np.ndarray) and field_value.size == 1:
            field_value = field_value.item()

        # Recursively convert nested structs
        if hasattr(field_value, "_fieldnames"):
            field_value = mat_struct_to_dict(field_value)

        result[field_name] = field_value

    return result


def load_section(path: str) -> Dict[str, Any]:
    """
    Load section_extracted from a .mat file.

    Replicates MATLAB line 156-157:
        d = load(f_path, 'section_extracted');
        data_struct = d.section_extracted;

    Args:
        path: Path to the .mat file

    Returns:
        dict: The section_extracted structure as a Python dict.
              Raises KeyError if section_extracted is not found.
    """
    mat_dict = loadmat(path, struct_as_record=False, squeeze_me=True)

    if "section_extracted" not in mat_dict:
        raise KeyError(f"'section_extracted' not found in {path}")

    section_struct = mat_dict["section_extracted"]

    # Convert mat_struct to dict
    if hasattr(section_struct, "_fieldnames"):
        return mat_struct_to_dict(section_struct)
    else:
        # Fallback: if it's already a dict or another type, try to return it
        return section_struct if isinstance(section_struct, dict) else {}


def parse_run_date(fname: str, section: Dict[str, Any]) -> datetime:
    """
    Parse run date from section.time_start or from filename.

    Replicates MATLAB lines 158-162:
        if isfield(data_struct, 'time_start')
            run_date = datetime(data_struct.time_start);
        else
            parts = split(f_name, '_');
            run_date = datetime([parts{2} ' ' parts{3}], 'InputFormat', 'yyyyMMdd HHmmss');
        end

    Args:
        fname: Filename (e.g., "RUN_20240115_103000")
        section: Dictionary with optional 'time_start' key

    Returns:
        datetime.datetime: The parsed run date

    Raises:
        ValueError: If filename cannot be parsed
    """
    # Check if time_start is in section and is non-empty
    if "time_start" in section:
        time_start = section["time_start"]
        if time_start is not None and (not isinstance(time_start, str) or time_start.strip()):
            # Convert numpy datetime64 or string to Python datetime
            if isinstance(time_start, np.datetime64):
                # numpy datetime64 → datetime
                return datetime.fromisoformat(str(time_start))
            elif isinstance(time_start, str):
                # Try to parse as ISO format or flexible format
                return datetime.fromisoformat(time_start)
            else:
                # Fallback to string representation
                return datetime.fromisoformat(str(time_start))

    # Fall back to filename parsing
    # MATLAB: parts{2} is index 2 (1-based) = index 1 (0-based)
    #         parts{3} is index 3 (1-based) = index 2 (0-based)
    parts = fname.split("_")
    if len(parts) < 3:
        raise ValueError(
            f"Cannot parse date from filename '{fname}': "
            f"expected format 'NAME_YYYYMMDD_HHMMSS' with at least 3 parts, got {len(parts)}"
        )

    date_str = parts[1]  # e.g., "20240115"
    time_str = parts[2]  # e.g., "103000"
    datetime_str = f"{date_str} {time_str}"

    # Parse using format 'yyyyMMdd HHmmss' (MATLAB format)
    return datetime.strptime(datetime_str, "%Y%m%d %H%M%S")
