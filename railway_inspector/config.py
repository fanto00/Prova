from dataclasses import dataclass, field


@dataclass
class CFG:
    # --- Paths ---
    root_folder: str = r'C:\Users\Nicco\MATLAB Drive\TESI\M2_pari'
    excel_path: str = r'C:\Users\Nicco\MATLAB Drive\TESI\M2-PEDRO.xlsx'
    save_folder: str = r'C:\Users\Nicco\MATLAB Drive\TESI\Defect_Database_pari'
    TRACK_TYPE: str = 'pari'

    # --- Route / direction selection ---
    ROUTE_FILTER: str = '37'
    ONLY_FORWARD: bool = True

    # --- Joints mode ---
    ONLY_JOINTS: bool = True
    JOINTS_EXCEL: str = r'C:\Users\Nicco\MATLAB Drive\TESI\Position-Giunti.xlsx'
    JOINT_WINDOW: float = 7.0     # Semi-window (+/- m)
    JOINT_MAX_RUNS: int = 300     # Max runs saved per joint

    # --- Frequency band ---
    fmin: int = 2
    fmax: int = 350

    # --- Spatial parameters ---
    SPATIAL_RES: float = 0.004          # m
    WINDOW_FINAL: float = 5.0           # +/- m
    WINDOW_EXTRACT: float = 7.0         # +/- m
    ALIGN_FOCUS: int = 2                # radius in m for peak isolation
    FILTER_MARGIN: float = 50.0         # safety margin for filter transients
    ALIGN_MAX_LAG: int = 4              # max shift in m for micro-alignment
    UPSAMPLE_FACTOR: int = 4            # upsampling factor for sub-sample alignment
    ALIGN_TEMPLATE_ITERS: int = 3       # template refinement passes
    ALIGN_TEMPLATE_NRUNS: int = 5       # runs to build template (0 = all)
    INFRA_TOL: float = 2.5              # distance between infrastructure elements
    CROSS_TOL: float = 1.5              # distance between peaks

    # --- Switch filter ---
    FILTER_SWITCHES: bool = True

    # --- Adaptive filtering ---
    L_MAX: int = 15
    L_MIN_QUIET: float = 0.01

    # --- Thresholds and shock ---
    RMS_WIN_FAST: int = 1
    RMS_WIN_SLOW: float = 20.0
    RMS_MUL: int = 3
    MIN_DIST: float = 1.5
    ABS_RMS_THRESH: float = 5.0         # m/s^2
    SAVE_RAW: bool = False
    SPEED_TOL: int = 10

    # --- Database completion ---
    MIN_RUNS_COMPLETE: int = 10          # min triggered runs to activate completion
    MAX_TOTAL_RUNS: int = 150            # absolute max runs per defect


def default_config() -> CFG:
    """Return a CFG instance populated with the MATLAB defaults."""
    return CFG()
