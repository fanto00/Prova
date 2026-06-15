"""Pure functions for single-run PSD analysis (translated from MATLAB app.m lines 4102-4511)."""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import List, Optional, Tuple

import numpy as np
from matplotlib.axes import Axes
from mpl_toolkits.mplot3d import Axes3D  # noqa: F401 – registers the '3d' projection

# ---------------------------------------------------------------------------
# Module-level constant (matches MATLAB dx_global = 0.030)
# ---------------------------------------------------------------------------
DX_GLOBAL: float = 0.030


# ---------------------------------------------------------------------------
# Internal: MATLAB-faithful periodogram
# ---------------------------------------------------------------------------

def _periodogram_matlab(
    x: np.ndarray,
    fs: float,
    nfft: int,
) -> Tuple[np.ndarray, np.ndarray]:
    """One-sided periodogram with Hamming window, matching MATLAB's periodogram().

    MATLAB call: [pxx, f] = periodogram(sig_r, hamming(length(sig_r)), NFFT, fs)

    MATLAB applies the window to the signal (length = len(sig_r)), then zero-pads
    or truncates to NFFT for the FFT.  scipy.signal.periodogram requires the window
    array to have the same length as nfft when both are provided explicitly, so we
    replicate the underlying computation directly:

        xw   = x * hamming(N)          # window the signal
        Xw   = rfft(xw, n=nfft)        # zero-pad / truncate to nfft
        psd  = |Xw|^2 / (fs * sum(w^2))
        psd[1:-1] *= 2                  # one-sided doubling

    Returns
    -------
    psd  : ndarray, shape (nfft//2 + 1,) – one-sided PSD
    freq : ndarray, shape (nfft//2 + 1,) – frequency vector [cycles/m]
    """
    win = np.hamming(len(x))
    xw = x * win
    Xw = np.fft.rfft(xw, n=nfft)
    psd = (1.0 / (fs * np.sum(win ** 2))) * np.abs(Xw) ** 2
    # Double all bins except DC (index 0) and Nyquist (last bin when nfft is even)
    if nfft % 2 == 0:
        psd[1:-1] *= 2.0
    else:
        psd[1:] *= 2.0
    freq = np.fft.rfftfreq(nfft, d=1.0 / fs)
    return psd, freq


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _datenum_to_datetime(dn: float) -> datetime:
    """Convert MATLAB datenum to Python datetime (epoch = 1899-12-30)."""
    epoch = datetime(1899, 12, 30)
    return epoch + timedelta(days=dn)


def _datetime_to_datenum(dt: datetime) -> float:
    """Convert Python datetime to MATLAB datenum."""
    epoch = datetime(1899, 12, 30)
    delta = dt - epoch
    return delta.days + delta.seconds / 86400.0


def _round_datetime_to_period(dt: datetime, mode: str) -> datetime:
    """Round a datetime to the start of its grouping period.

    Matches MATLAB dateshift logic:
      'run'     -> identity (no rounding)
      'daily'   -> start of day
      'weekly'  -> start of week (Monday), equivalent to MATLAB:
                   dateshift(dt - days(1), 'start', 'week') + days(1)
                   i.e. start of the ISO week (Monday)
      'monthly' -> start of month
    """
    if mode == 'run':
        return dt
    if mode == 'daily':
        return dt.replace(hour=0, minute=0, second=0, microsecond=0)
    if mode == 'weekly':
        # MATLAB: dateshift(all_dates_dt - days(1), 'start', 'week') + days(1)
        # MATLAB week starts on Sunday; shifting back 1 day then to start of
        # (Sunday-based) week then +1 day gives Monday.
        day_before = dt - timedelta(days=1)
        # Start of Sunday-based week: subtract weekday() (Mon=0..Sun=6)
        # In MATLAB's convention Sunday=1, so "start of week" is the preceding Sunday.
        # weekday(): Mon=0, Tue=1, ..., Sun=6
        days_since_sunday = (day_before.weekday() + 1) % 7  # Sun=0 offset
        sunday = day_before - timedelta(days=days_since_sunday)
        monday = sunday + timedelta(days=1)
        return monday.replace(hour=0, minute=0, second=0, microsecond=0)
    if mode == 'monthly':
        return dt.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    raise ValueError(f"Unknown grouping_mode: {mode!r}")


# ---------------------------------------------------------------------------
# 1. compute_psd_for_run
# ---------------------------------------------------------------------------

def compute_psd_for_run(
    signal: np.ndarray,
    axis: np.ndarray,
    window_m: float,
    dx: float = DX_GLOBAL,
) -> Tuple[np.ndarray, np.ndarray]:
    """Crop signal to ±window_m/2 and compute periodogram with Hamming window.

    Matches MATLAB lines 4135-4141:
        mask = axis_full >= -win_m/2 & axis_full <= win_m/2;
        sig_r = sig_full(mask);
        [pxx_r, f] = periodogram(sig_r, hamming(length(sig_r)), NFFT_global, fs_global);

    Parameters
    ----------
    signal : ndarray, shape (N,)
    axis   : ndarray, shape (N,) – spatial positions [m]
    window_m : float – full window width [m]
    dx     : float – spatial sampling step [m]

    Returns
    -------
    psd      : ndarray – one-sided power spectral density
    freq_axis: ndarray – frequency vector [cycles/m]
    """
    fs_global = 1.0 / dx
    nfft = round(window_m / dx)
    if nfft < 4:
        nfft = 4

    # Crop to ±window_m/2  (MATLAB: mask = axis_full >= -win_m/2 & axis_full <= win_m/2)
    half = window_m / 2.0
    mask = (axis >= -half) & (axis <= half)
    sig_r = signal[mask].astype(float)

    if sig_r.size < 4:
        return np.array([]), np.array([])

    # Periodogram with Hamming window, NFFT zero-padding (matches MATLAB)
    psd, freq_axis = _periodogram_matlab(sig_r, fs_global, nfft)
    return psd, freq_axis


# ---------------------------------------------------------------------------
# 2. compute_psd_matrix_3d
# ---------------------------------------------------------------------------

def compute_psd_matrix_3d(
    all_runs: List[dict],
    sensor_name: str,
    window_m: float,
    dates_num: np.ndarray,
    grouping_mode: str = 'run',
    dx: float = DX_GLOBAL,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, List]:
    """Build 3-D PSD matrix by grouping runs into periods and averaging.

    Matches MATLAB lines 4413-4478 (update_psd_3d loop).

    Grouping modes
    --------------
    'run'     – each run is its own period (no grouping)
    'daily'   – runs on the same calendar day are averaged
    'weekly'  – runs in the same ISO week (Mon-Sun)
    'monthly' – runs in the same calendar month

    PSD averaging: accumulate pxx_r then divide by n_valid_runs
    (matches MATLAB: PSD_Matrix(k,:) = period_pxx' / n_valid_runs).

    Parameters
    ----------
    all_runs      : list of dicts with keys 'Signals', 'Axis', 'Date'
    sensor_name   : str – key inside run['Signals']
    window_m      : float – full window width [m]
    dates_num     : ndarray – MATLAB datenum for each run (same order as all_runs)
    grouping_mode : str
    dx            : float

    Returns
    -------
    psd_matrix    : ndarray, shape (n_periods_valid, n_freq)
    freq_axis     : ndarray, shape (n_freq,)
    date_axis     : ndarray – datenum for each valid period
    periods_valid : list of period keys (datetime)
    """
    fs_global = 1.0 / dx
    nfft = round(window_m / dx)
    if nfft < 4:
        nfft = 4
    half = window_m / 2.0

    # Build rounded datetime for each run  (MATLAB: dates_rounded)
    run_dates: List[datetime] = [_datenum_to_datetime(dn) for dn in dates_num]
    rounded: List[datetime] = [_round_datetime_to_period(dt, grouping_mode) for dt in run_dates]

    # unique periods in sorted (chronological) order (MATLAB unique() returns sorted)
    unique_periods_unsorted: List[datetime] = []
    for rd in rounded:
        if rd not in unique_periods_unsorted:
            unique_periods_unsorted.append(rd)
    unique_periods: List[datetime] = sorted(unique_periods_unsorted)

    # Rebuild index map (ic) based on sorted unique_periods
    seen: dict = {dt: i for i, dt in enumerate(unique_periods)}
    ic: List[int] = [seen[rd] for rd in rounded]

    psd_rows: List[np.ndarray] = []
    freq_axis: np.ndarray = np.array([])
    valid_period_keys: List[datetime] = []
    valid_datenums: List[float] = []

    for k, period_dt in enumerate(unique_periods):
        idxs = [j for j, c in enumerate(ic) if c == k]

        period_pxx: Optional[np.ndarray] = None
        n_valid_runs = 0

        for run_idx in idxs:
            run = all_runs[run_idx]

            # Check sensor exists
            signals = run.get('Signals', {})
            if sensor_name not in signals:
                continue

            sig_full = np.asarray(signals[sensor_name], dtype=float)
            axis_full = np.asarray(run.get('Axis', []), dtype=float)

            # MATLAB guards (lines 4445-4449)
            if sig_full.size == 0 or axis_full.size == 0 or sig_full.size <= 1:
                continue
            if not np.any(sig_full):
                continue

            L_min = min(len(sig_full), len(axis_full))
            if L_min < 10:
                continue

            sig_full = sig_full[:L_min]
            axis_full = axis_full[:L_min]

            # Crop  (MATLAB line 4454-4455)
            mask = (axis_full >= -half) & (axis_full <= half)
            sig_r = sig_full[mask]

            if sig_r.size < 10:
                continue

            # PSD – Hamming + NFFT_global (MATLAB line 4460)
            pxx_r, f = _periodogram_matlab(sig_r, fs_global, nfft)

            # Accumulate  (MATLAB lines 4462-4469)
            if period_pxx is None:
                period_pxx = np.zeros_like(pxx_r)
                if freq_axis.size == 0:
                    freq_axis = f

            if len(pxx_r) == len(period_pxx):
                period_pxx = period_pxx + pxx_r
                n_valid_runs += 1

        # Average and store if period has valid data  (MATLAB line 4473-4475)
        if period_pxx is not None and n_valid_runs > 0:
            psd_rows.append(period_pxx / n_valid_runs)
            valid_period_keys.append(period_dt)
            valid_datenums.append(_datetime_to_datenum(period_dt))

    if psd_rows:
        psd_matrix = np.vstack(psd_rows)
    else:
        psd_matrix = np.empty((0, 0))

    date_axis = np.array(valid_datenums)
    return psd_matrix, freq_axis, date_axis, valid_period_keys


# ---------------------------------------------------------------------------
# 3. plot_psd_2d
# ---------------------------------------------------------------------------

def plot_psd_2d(
    ax: Axes,
    freq_axis: np.ndarray,
    psd_current: np.ndarray,
    psd_historical_list: List[np.ndarray],
    title: Optional[str] = None,
    **kwargs,
) -> None:
    """Plot historical PSDs (grey), their mean (dashed dark grey), and the selected run (red).

    Matches MATLAB lines 4149-4177:
      - Storico:       Color=[0.85 0.85 0.85], LineWidth=0.5
      - Media Storica: Color=[0.3 0.3 0.3], LineStyle='--', LineWidth=1.2
      - Run Selezionata: Color=[0.8 0.2 0], LineWidth=2
    """
    # Historical lines (grey)
    for pxx in psd_historical_list:
        ax.plot(
            freq_axis, pxx,
            color=(0.85, 0.85, 0.85),
            linewidth=0.5,
        )

    # Mean of historical runs  (MATLAB: pxx_mean = mean(all_pxx, 2))
    if psd_historical_list:
        pxx_mean = np.mean(np.column_stack(psd_historical_list), axis=1)
        ax.plot(
            freq_axis, pxx_mean,
            color=(0.3, 0.3, 0.3),
            linestyle='--',
            linewidth=1.2,
            label='Media Storica',
        )

    # Selected run (red-orange)
    ax.plot(
        freq_axis, psd_current,
        color=(0.8, 0.2, 0.0),
        linewidth=2,
        label='Run Selezionata',
    )

    ax.set_xlabel('Frequenza Spaziale [cicli/m]', fontweight='bold')
    ax.set_ylabel('PSD [(m/s²)² / (cicli/m)]', fontweight='bold')
    ax.grid(True)
    ax.legend(loc='upper right')  # northeast

    if title is not None:
        ax.set_title(title, fontsize=12)


# ---------------------------------------------------------------------------
# 4. plot_psd_3d_waterfall
# ---------------------------------------------------------------------------

def plot_psd_3d_waterfall(
    ax,  # Axes3D
    freq_axis: np.ndarray,
    date_axis: np.ndarray,
    psd_matrix: np.ndarray,
    title: Optional[str] = None,
    **kwargs,
) -> None:
    """Draw a waterfall (ribbon) 3-D PSD plot.

    Matches MATLAB lines 4493-4507:
        waterfall(ax, F_Axis, Y_Date_Axis_valid, PSD_Matrix)
        set(h_wf, 'LineWidth', 1.2, 'EdgeColor', 'interp', 'FaceAlpha', 0.7)
        view(-37.5, 30); colormap jet; colorbar; datetick y; grid on
    """
    from mpl_toolkits.mplot3d.art3d import Poly3DCollection
    import matplotlib.cm as cm
    import matplotlib.colors as mcolors

    n_periods, n_freq = psd_matrix.shape

    # Build ribbon polygons – one per row of psd_matrix (waterfall style)
    verts = []
    for i in range(n_periods):
        y_val = date_axis[i]
        xs = np.concatenate([[freq_axis[0]], freq_axis, [freq_axis[-1]]])
        zs = np.concatenate([[0.0], psd_matrix[i], [0.0]])
        ys = np.full_like(xs, y_val)
        verts.append(list(zip(xs, ys, zs)))

    import matplotlib
    cmap = matplotlib.colormaps['jet']
    z_min = psd_matrix.min()
    z_max = psd_matrix.max() if psd_matrix.max() > z_min else z_min + 1.0
    norm = mcolors.Normalize(vmin=z_min, vmax=z_max)

    face_colors = [cmap(norm(psd_matrix[i].mean())) for i in range(n_periods)]

    poly = Poly3DCollection(
        verts,
        facecolors=[(r, g, b, 0.7) for r, g, b, _ in face_colors],
        edgecolors=[cmap(norm(psd_matrix[i].mean())) for i in range(n_periods)],
        linewidths=1.2,
    )
    ax.add_collection3d(poly)

    # Set axis limits
    ax.set_xlim(freq_axis.min(), freq_axis.max())
    ax.set_ylim(date_axis.min(), date_axis.max())
    ax.set_zlim(0, z_max)

    # View: MATLAB view(-37.5, 30) → elev=30, azim=-37.5
    ax.view_init(elev=30, azim=-37.5)

    ax.set_xlabel('Frequenza Spaziale [cicli/m]', fontweight='bold')
    ax.set_ylabel('Evoluzione Temporale', fontweight='bold')
    ax.set_zlabel('PSD Power', fontweight='bold')
    ax.grid(True)

    # Colorbar
    mappable = cm.ScalarMappable(norm=norm, cmap=cmap)
    mappable.set_array(psd_matrix.ravel())
    ax.figure.colorbar(mappable, ax=ax, shrink=0.6)

    if title is not None:
        ax.set_title(title)
