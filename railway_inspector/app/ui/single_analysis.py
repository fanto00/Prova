"""Pure functions for single-defect analysis window (Modulo 10).

Translated from MATLAB app.m lines 2042-2449, 2550-2573, 2590-2593.
No UI code — all functions return plain Python/NumPy data structures.
"""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple

import numpy as np
import scipy.ndimage
import scipy.stats

from railway_inspector.app.analysis.single_analysis_psd import (
    _datenum_to_datetime,
    _datetime_to_datenum,
    _periodogram_matlab,
    _round_datetime_to_period,
)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _moving_window_stat(sig: np.ndarray, k: int, fun) -> np.ndarray:
    """Scalar moving-window statistic (MATLAB app.m lines 2551-2572).

    Replicates MATLAB moving_window_stat(sig, k, fun_handle):
      - step=1 for n<=2000, step=5 for longer signals
      - If step>1: sparse compute then linear interpolate back to full length
    """
    n = int(sig.size)
    out = np.zeros(n, dtype=float)
    step = 1 if n <= 2000 else 5
    half_k = k // 2  # MATLAB: floor(k/2)

    for ii in range(0, n, step):
        i_start = max(0, ii - half_k)       # MATLAB: max(1, ii-half_k) → 0-based
        i_end = min(n, ii + half_k + 1)     # MATLAB: min(n, ii+half_k) → exclusive
        chunk = sig[i_start:i_end]
        if chunk.size > 0:
            out[ii] = fun(chunk)

    if step > 1:
        # MATLAB: interp1(idx_filled, out(idx_filled), 1:n, 'linear', 'extrap')
        idx_filled = np.arange(0, n, step)
        all_idx = np.arange(n)
        out = np.interp(all_idx, idx_filled, out[idx_filled])

    return out


def _get_quick_lambda(sig: np.ndarray, nfft: int, fs: float) -> float:
    """Dominant wavelength via periodogram (MATLAB get_quick_lambda_local, line 2154).

    Returns wavelength in metres (1/f_peak), or 0 if signal is too short/flat.
    """
    sig = np.asarray(sig, dtype=float).reshape(-1)
    if sig.size < 4:
        return 0.0
    # Use at most nfft samples centred on the signal
    if sig.size > nfft:
        start = (sig.size - nfft) // 2
        sig = sig[start: start + nfft]
    try:
        psd, freq = _periodogram_matlab(sig, fs, nfft)
    except Exception:
        return 0.0
    if freq.size < 2:
        return 0.0
    # Ignore DC bin (index 0)
    idx_peak = int(np.argmax(psd[1:])) + 1
    f_peak = freq[idx_peak]
    return (1.0 / f_peak) if f_peak > 0 else 0.0


# ---------------------------------------------------------------------------
# 1. prepare_raw_data_store
# ---------------------------------------------------------------------------

def prepare_raw_data_store(
    defect_history: List[dict],
    cfg: dict,
    sensor_fields_list: List[str],
) -> List[dict]:
    """Extract signals, axes, amplitudes from defect_history (MATLAB lines 2042-2119).

    Returns RawDataStore sorted chronologically (mirrors MATLAB sort_idx logic).
    Each element: {Date, Signals, Axis, Amp, Speed, Detected}.
    """
    dx_default: float = float(cfg.get('SPATIAL_RES', 0.030)
                              if isinstance(cfg, dict)
                              else cfg.SPATIAL_RES)

    # MATLAB line 2079: win_samples_base = max(3, round(0.5 / dx_default))
    win_samples_base: int = max(3, round(0.5 / dx_default))

    n_runs = len(defect_history)
    raw_store: List[dict] = []
    dates_num: List[float] = []

    for i, run in enumerate(defect_history):
        entry: dict = {}
        entry['Date'] = run.get('Date', datetime(1970, 1, 1))
        entry['Amp'] = run.get('Amp', 0.0)

        # MATLAB lines 2061-2070
        data = run.get('Data', {})
        speed = data.get('Speed', float('nan'))
        if speed is None:
            speed = float('nan')
        entry['Speed'] = speed

        # MATLAB line 2066-2070: Detected field
        if 'Detected' in run:
            entry['Detected'] = run['Detected']
        else:
            entry['Detected'] = True

        entry['Signals'] = {}

        # MATLAB lines 2080-2112
        filt = data.get('Filt', {})
        if filt:
            for sn in sensor_fields_list:
                if sn in filt:
                    sig = np.asarray(filt[sn], dtype=float).reshape(-1)
                    entry['Signals'][sn] = sig

            # MATLAB lines 2104-2112: derive axis
            if 'RelativeAxis' in data:
                ax_loc = np.asarray(data['RelativeAxis'], dtype=float).reshape(-1)
            elif sensor_fields_list[0] in filt:
                L = len(filt[sensor_fields_list[0]])
                ax_loc = np.linspace(-L / 2 * dx_default, L / 2 * dx_default, L)
            else:
                ax_loc = np.array([])
            entry['Axis'] = ax_loc
        else:
            entry['Axis'] = np.array([])

        dates_num.append(_datetime_to_datenum(entry['Date']))
        raw_store.append(entry)

    # MATLAB lines 2117-2119: sort by dates_num ascending
    sort_idx = np.argsort(dates_num, kind='stable')
    raw_store = [raw_store[i] for i in sort_idx]

    return raw_store


# ---------------------------------------------------------------------------
# 2. compute_all_amps
# ---------------------------------------------------------------------------

def compute_all_amps(
    RawDataStore: List[dict],
    sensor_fields_list: List[str],
    cfg: dict,
) -> np.ndarray:
    """Compute max(moving-RMS) per run/sensor with 0.5 m window (MATLAB lines 2075-2102).

    Returns ndarray of shape (n_runs, 8).
    Window is hardcoded to 0.5 m (MATLAB line 2079 comment: 'prova con window di 0.5m').
    """
    dx_default: float = float(cfg.get('SPATIAL_RES', 0.030)
                              if isinstance(cfg, dict)
                              else cfg.SPATIAL_RES)
    # MATLAB line 2079
    win_samples_base: int = max(3, round(0.5 / dx_default))

    n_runs = len(RawDataStore)
    n_sens = len(sensor_fields_list)
    all_amps = np.full((n_runs, n_sens), np.nan)

    for i, entry in enumerate(RawDataStore):
        signals = entry.get('Signals', {})
        for s, sn in enumerate(sensor_fields_list):
            if sn in signals:
                sig = np.asarray(signals[sn], dtype=float).reshape(-1)
                # MATLAB lines 2087-2095
                if sig.size >= win_samples_base:
                    # movmean(sig.^2, win_samples_base) → uniform_filter1d
                    rms_sig = np.sqrt(
                        scipy.ndimage.uniform_filter1d(
                            sig ** 2, size=win_samples_base, mode='nearest'
                        )
                    )
                    val_max_rms = float(np.max(rms_sig))
                else:
                    # Fallback: max(abs(sig))
                    val_max_rms = float(np.max(np.abs(sig))) if sig.size > 0 else 0.0
                all_amps[i, s] = val_max_rms
            else:
                # MATLAB line 2100: AllAmps(i,s) = 0
                all_amps[i, s] = 0.0

    return all_amps


# ---------------------------------------------------------------------------
# 3. compute_metrics_per_run
# ---------------------------------------------------------------------------

def compute_metrics_per_run(
    all_amps: np.ndarray,
    RawDataStore: List[dict],
    dates_num: np.ndarray,
    cfg: dict,
    sensor_fields_list: List[str],
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Compute amplitude ratios, lambda, and severity for each run (MATLAB lines 2122-2157).

    Returns (ratio_sx_dx, ratio_fr, ratio_lv, lambda_all, severity).
    """
    dx_default: float = float(cfg.get('SPATIAL_RES', 0.030)
                              if isinstance(cfg, dict)
                              else cfg.SPATIAL_RES)

    amps = np.asarray(all_amps, dtype=float)
    n_runs = amps.shape[0]

    # MATLAB lines 2129-2130
    fs_space = 1.0 / dx_default
    nfft_val = max(4, round(10.0 / dx_default))   # 10 m window for lambda

    ratio_sx_dx = np.zeros(n_runs)
    ratio_fr    = np.zeros(n_runs)
    ratio_lv    = np.zeros(n_runs)
    lambda_all  = np.zeros((n_runs, 8))
    severity    = np.zeros(n_runs)

    for i in range(n_runs):
        # MATLAB lines 2135-2137 (0-based columns)
        a_sx_f = amps[i, 0]
        a_sx_r = amps[i, 1]
        a_dx_f = amps[i, 2]
        a_dx_r = amps[i, 3]
        a_lat_max  = float(np.nanmax(amps[i, 4:8]))
        a_vert_max = float(np.nanmax(amps[i, 0:4]))

        # MATLAB line 2140
        severity[i] = float(np.nanmax([a_sx_f, a_sx_r, a_dx_f, a_dx_r]))

        # MATLAB lines 2145-2147
        ratio_sx_dx[i] = (a_sx_f + a_sx_r) / max(a_dx_f + a_dx_r, 1e-6)
        ratio_fr[i]    = (a_sx_f + a_dx_f) / max(a_sx_r + a_dx_r, 1e-6)
        ratio_lv[i]    = a_lat_max           / max(a_vert_max,      1e-6)

        # MATLAB lines 2150-2156: lambda per sensor
        signals = RawDataStore[i].get('Signals', {})
        for s, sn in enumerate(sensor_fields_list):
            if sn in signals:
                sig_tmp = np.asarray(signals[sn], dtype=float).reshape(-1)
                lambda_all[i, s] = _get_quick_lambda(sig_tmp, nfft_val, fs_space)

    return ratio_sx_dx, ratio_fr, ratio_lv, lambda_all, severity


# ---------------------------------------------------------------------------
# 4. build_tab_trend_data
# ---------------------------------------------------------------------------

def build_tab_trend_data(
    all_amps: np.ndarray,
    dates_num: np.ndarray,
    cfg: dict,
) -> Dict:
    """Aggregate AllAmps per day for 4 sensor-pair subplots (MATLAB lines 2186-2207).

    Pairs (0-based column indices matching MATLAB pairs_idx):
      pair 0: cols (0,1)  SX_F / SX_R
      pair 1: cols (2,3)  DX_F / DX_R
      pair 2: cols (4,5)  LAT_DX_F / LAT_DX_R
      pair 3: cols (6,7)  LAT_SX_F / LAT_SX_R

    Returns dict: unique_days, mean_f_by_day, mean_r_by_day, plot_titles.
    """
    # MATLAB pairs_idx (1-based): [1,2; 3,4; 5,6; 7,8] → 0-based: [(0,1),(2,3),(4,5),(6,7)]
    pairs_idx = [(0, 1), (2, 3), (4, 5), (6, 7)]
    plot_titles = [
        'Verticale SX (F vs R)',
        'Verticale DX (F vs R)',
        'Laterale DX (F vs R)',
        'Laterale SX (F vs R)',
    ]

    dns = np.asarray(dates_num, dtype=float)
    # MATLAB: days_floor = floor(dates_num); unique_days = unique(days_floor)
    days_floor = np.floor(dns)
    unique_days = np.unique(days_floor)   # sorted
    n_days = len(unique_days)

    # Build per-pair lists
    mean_f_by_day: List[np.ndarray] = []
    mean_r_by_day: List[np.ndarray] = []

    for idx_f, idx_r in pairs_idx:
        mf = np.zeros(n_days)
        mr = np.zeros(n_days)
        for k, ud in enumerate(unique_days):
            mask = (days_floor == ud)
            vals_f = all_amps[mask, idx_f]
            vals_r = all_amps[mask, idx_r]
            # MATLAB: if isempty, use 0; else mean
            mf[k] = float(np.mean(vals_f)) if vals_f.size > 0 else 0.0
            mr[k] = float(np.mean(vals_r)) if vals_r.size > 0 else 0.0
        mean_f_by_day.append(mf)
        mean_r_by_day.append(mr)

    return {
        'unique_days': unique_days,
        'mean_f_by_day': mean_f_by_day,
        'mean_r_by_day': mean_r_by_day,
        'plot_titles': plot_titles,
    }


# ---------------------------------------------------------------------------
# 5. build_tab_stats_table_data
# ---------------------------------------------------------------------------

def build_tab_stats_table_data(
    RawDataStore: List[dict],
    all_amps: np.ndarray,
    ratio_sx_dx: np.ndarray,
    ratio_fr: np.ndarray,
    ratio_lv: np.ndarray,
    lambda_all: np.ndarray,
    dates_num: np.ndarray,
    grouping_mode: str,
    cfg: dict,
    sensor_pair_idx: Tuple[int, int] = (0, 1),
    win_m: Optional[float] = None,
) -> List[dict]:
    """Build stats table rows grouped by period (MATLAB lines 2246-2460).

    grouping_mode: 'run' | 'daily' | 'weekly' | 'monthly'
    sensor_pair_idx: (front_col_idx, rear_col_idx) into sensor_fields_list (0-based)
    win_m: moving window in metres for profile stats (default 0.5 m)

    Each returned dict has keys:
        Date, Speed, Peak, MaxRMS, Skew, Kurt, Crest, Pos_3x3, Lambda
    """
    dx_default: float = float(cfg.get('SPATIAL_RES', 0.030)
                              if isinstance(cfg, dict)
                              else cfg.SPATIAL_RES)
    window_size: float = float(cfg.get('WINDOW_SIZE', 5.0)
                               if isinstance(cfg, dict)
                               else cfg.WINDOW_SIZE)
    if win_m is None:
        win_m = 0.5
    win_samples: int = max(3, round(win_m / dx_default))

    dns = np.asarray(dates_num, dtype=float)
    r_sx_dx = np.asarray(ratio_sx_dx, dtype=float)
    r_fr    = np.asarray(ratio_fr,    dtype=float)
    lam     = np.asarray(lambda_all,  dtype=float)

    # MATLAB lines 2265-2288: compute dates_rounded per grouping
    run_dts: List[datetime] = [_datenum_to_datetime(dn) for dn in dns]
    rounded: List[datetime] = [
        _round_datetime_to_period(dt, grouping_mode) for dt in run_dts
    ]

    # MATLAB: [unique_periods, ~, ic] = unique(dates_rounded)
    seen: List[datetime] = []
    for rd in rounded:
        if rd not in seen:
            seen.append(rd)
    unique_periods: List[datetime] = sorted(seen)
    period_index: Dict[datetime, int] = {dt: k for k, dt in enumerate(unique_periods)}
    ic: List[int] = [period_index[rd] for rd in rounded]
    ic_arr = np.asarray(ic, dtype=int)

    n_periods = len(unique_periods)

    # MATLAB line 2300: common_axis
    common_axis = np.arange(-window_size, window_size + dx_default * 0.5, dx_default)

    # Sensor pair names for signal lookup
    # sensor_pair_idx are 0-based indices into the default sensor_fields_list
    # (mirrors MATLAB stat_pairs / sel_sens_front / sel_sens_rear at lines 2250-2258)
    default_sensor_list = [
        'left_sensor_front', 'left_sensor_rear',
        'right_sensor_front', 'right_sensor_rear',
        'right_sensor_front_lat', 'right_sensor_rear_lat',
        'left_sensor_front_lat', 'left_sensor_rear_lat',
    ]
    idx_f, idx_r = sensor_pair_idx
    # Guard against out-of-bounds
    sel_sens_front = default_sensor_list[idx_f] if idx_f < len(default_sensor_list) else ''
    sel_sens_rear  = default_sensor_list[idx_r] if idx_r < len(default_sensor_list) else ''

    table_rows: List[dict] = []

    for k in range(n_periods):
        day_idxs = list(np.where(ic_arr == k)[0])   # MATLAB: find(ic == k)

        sigs_matrix: List[np.ndarray] = []
        max_amp_day = 0.0
        speeds_day: List[float] = []

        for j in day_idxs:
            # MATLAB lines 2315-2345: speed and signal accumulation
            v_run = RawDataStore[j].get('Speed', float('nan'))
            if v_run is not None and not (isinstance(v_run, float) and np.isnan(v_run)) and v_run > 0:
                speeds_day.append(float(v_run))

            for sens_name in (sel_sens_front, sel_sens_rear):
                signals = RawDataStore[j].get('Signals', {})
                if sens_name in signals:
                    sig = np.asarray(signals[sens_name], dtype=float).reshape(-1)
                    ax_loc = RawDataStore[j].get('Axis', np.array([]))
                    ax_loc = np.asarray(ax_loc, dtype=float).reshape(-1)

                    # MATLAB line 2330: il vero picco assoluto
                    if sig.size > 0:
                        max_amp_day = max(max_amp_day, float(np.max(np.abs(sig))))

                    # MATLAB lines 2334-2343: interpolation
                    if (sig.size > 1 and ax_loc.size > 1):
                        L_min = min(sig.size, ax_loc.size)
                        sig_final = sig[:L_min]
                        ax_final  = ax_loc[:L_min]
                        if ax_final.size >= 2:
                            # MATLAB: interp1(ax_final, sig_final, common_axis, 'linear', 0)
                            sig_interp = np.interp(
                                common_axis, ax_final, sig_final,
                                left=0.0, right=0.0
                            )
                            sigs_matrix.append(sig_interp)

        if sigs_matrix:
            sigs_mat = np.vstack(sigs_matrix)          # (n_sigs, n_samples)
            n_sigs, n_samples = sigs_mat.shape

            all_rms_profiles   = np.zeros((n_sigs, n_samples))
            all_skew_profiles  = np.zeros((n_sigs, n_samples))
            all_kurt_profiles  = np.zeros((n_sigs, n_samples))
            all_crest_profiles = np.zeros((n_sigs, n_samples))
            all_max_rms        = np.zeros(n_sigs)

            for row_idx in range(n_sigs):
                sig_row = sigs_mat[row_idx]

                # MATLAB line 2363: rms_row = sqrt(movmean(sig_row.^2, win_samples))
                rms_row = np.sqrt(
                    scipy.ndimage.uniform_filter1d(
                        sig_row ** 2, size=win_samples, mode='nearest'
                    )
                )
                all_rms_profiles[row_idx] = rms_row
                all_max_rms[row_idx] = float(np.max(rms_row))

                # MATLAB lines 2368-2370: skew, kurt, crest per sample
                all_skew_profiles[row_idx] = _moving_window_stat(
                    sig_row, win_samples, scipy.stats.skew
                )
                all_kurt_profiles[row_idx] = _moving_window_stat(
                    sig_row, win_samples,
                    lambda x: scipy.stats.kurtosis(x, fisher=False)
                )
                # MATLAB: movmax(abs(sig_row), win_samples) ./ (rms_row + eps)
                eps = np.finfo(float).eps
                mov_max_abs = scipy.ndimage.maximum_filter1d(
                    np.abs(sig_row), size=win_samples, mode='nearest'
                )
                all_crest_profiles[row_idx] = mov_max_abs / (rms_row + eps)

            # MATLAB lines 2375-2378: mean over signals (omitnan)
            p_rms   = np.nanmean(all_rms_profiles,   axis=0)
            p_skew  = np.nanmean(all_skew_profiles,  axis=0)
            p_kurt  = np.nanmean(all_kurt_profiles,  axis=0)
            p_crest = np.nanmean(all_crest_profiles, axis=0)

            # MATLAB line 2388: mean of max_rms per signal
            mean_of_max_rms = float(np.nanmean(all_max_rms))

            # MATLAB line 2391: peak index on average RMS profile
            idx_pk = int(np.argmax(p_rms))

            # MATLAB lines 2394-2398: date string
            if grouping_mode == 'run':
                d_str = unique_periods[k].strftime('%d/%m/%y %H:%M')
            else:
                d_str = unique_periods[k].strftime('%d/%m/%y')

            # MATLAB lines 2401-2411: speed string
            if not speeds_day:
                speed_str = 'N/A'
            else:
                mean_v = float(np.mean(speeds_day))
                if len(speeds_day) == 1:
                    speed_str = f'{mean_v:.1f}'
                else:
                    indiv_str = ', '.join(str(round(v)) for v in speeds_day)
                    speed_str = f'{mean_v:.1f} [{indiv_str}]'

            # MATLAB lines 2417-2432: 3x3 classification
            mean_ratio_x = float(np.nanmean(r_sx_dx[day_idxs]))
            mean_ratio_y = float(np.nanmean(r_fr[day_idxs]))

            if np.isnan(mean_ratio_x):
                lat_char = '-'
            elif mean_ratio_x > 2.0:
                lat_char = 'L'
            elif mean_ratio_x < 0.5:
                lat_char = 'R'
            else:
                lat_char = 'C'

            if np.isnan(mean_ratio_y):
                long_char = '-'
            elif mean_ratio_y > 2.0:
                long_char = 'F'
            elif mean_ratio_y < 0.5:
                long_char = 'R'
            else:
                long_char = 'C'

            pos_3x3_str = f'{lat_char}-{long_char}'

            # MATLAB lines 2437-2450: mean lambda for selected sensor pair
            lams_f = lam[day_idxs, idx_f]
            lams_r = lam[day_idxs, idx_r]
            valid_lams = np.concatenate([lams_f.ravel(), lams_r.ravel()])
            valid_lams = valid_lams[valid_lams > 0]
            if valid_lams.size == 0:
                mean_lambda = 0.0
            else:
                mean_lambda = round(float(np.mean(valid_lams)), 2)

            table_rows.append({
                'Date':   d_str,
                'Speed':  speed_str,
                'Peak':   max_amp_day,
                'MaxRMS': mean_of_max_rms,
                'Skew':   float(p_skew[idx_pk]),
                'Kurt':   float(p_kurt[idx_pk]),
                'Crest':  float(p_crest[idx_pk]),
                'Pos_3x3': pos_3x3_str,
                'Lambda': mean_lambda,
            })
        else:
            # MATLAB line 2457-2459: fallback row
            if grouping_mode == 'run':
                d_str = unique_periods[k].strftime('%d/%m/%y %H:%M')
            else:
                d_str = unique_periods[k].strftime('%d/%m/%y')
            table_rows.append({
                'Date':   d_str,
                'Speed':  'N/A',
                'Peak':   0.0,
                'MaxRMS': 0.0,
                'Skew':   0.0,
                'Kurt':   0.0,
                'Crest':  0.0,
                'Pos_3x3': '-',
                'Lambda': 0.0,
            })

    return table_rows


# ---------------------------------------------------------------------------
# 6. build_stft_dates_labels
# ---------------------------------------------------------------------------

def build_stft_dates_labels(RawDataStore: List[dict]) -> List[str]:
    """Format run date+amplitude labels for STFT dropdown (MATLAB lines 2590-2593).

    Format: 'dd/mm/yy HH:MM  [ X.X m/s² ]'
    """
    labels: List[str] = []
    for entry in RawDataStore:
        dt = entry.get('Date', datetime(1970, 1, 1))
        amp = float(entry.get('Amp', 0.0))
        # MATLAB: sprintf('%s  [ %.1f m/s^2 ]', datestr(Date, 'dd/mm/yy HH:MM'), Amp)
        labels.append(f"{dt.strftime('%d/%m/%y %H:%M')}  [ {amp:.1f} m/s^2 ]")
    return labels


# ---------------------------------------------------------------------------
# 7. compute_cache_profiles
# ---------------------------------------------------------------------------

def compute_cache_profiles(
    RawDataStore: List[dict],
    dates_num: np.ndarray,
    sensor_fields_list: List[str],
    sensor_pair_idx: Tuple[int, int],
    grouping_mode: str,
    cfg: dict,
    win_m: Optional[float] = None,
) -> List[dict]:
    """Compute moving-window profile cache per period (MATLAB lines 2246-2385).

    For each temporal period: interpolates signals onto common_axis = [-WINDOW_SIZE, WINDOW_SIZE],
    computes RMS/Skew/Kurt/Crest profiles per signal, then averages across signals.

    Returns List[dict] with keys: RMS, Skew, Kurt, Crest, Axis, Date.
    """
    dx_default: float = float(cfg.get('SPATIAL_RES', 0.030)
                              if isinstance(cfg, dict)
                              else cfg.SPATIAL_RES)
    window_size: float = float(cfg.get('WINDOW_SIZE', 5.0)
                               if isinstance(cfg, dict)
                               else cfg.WINDOW_SIZE)
    if win_m is None:
        win_m = 0.5
    win_samples: int = max(3, round(win_m / dx_default))

    dns = np.asarray(dates_num, dtype=float)

    # Grouping (MATLAB lines 2272-2288)
    run_dts: List[datetime] = [_datenum_to_datetime(dn) for dn in dns]
    rounded: List[datetime] = [
        _round_datetime_to_period(dt, grouping_mode) for dt in run_dts
    ]

    seen: List[datetime] = []
    for rd in rounded:
        if rd not in seen:
            seen.append(rd)
    unique_periods: List[datetime] = sorted(seen)
    period_index: Dict[datetime, int] = {dt: k for k, dt in enumerate(unique_periods)}
    ic_arr = np.asarray([period_index[rd] for rd in rounded], dtype=int)

    # MATLAB line 2300
    common_axis = np.arange(-window_size, window_size + dx_default * 0.5, dx_default)

    # Sensor names for the pair
    idx_f, idx_r = sensor_pair_idx
    def _sname(idx: int) -> str:
        return sensor_fields_list[idx] if idx < len(sensor_fields_list) else ''
    sel_sens_front = _sname(idx_f)
    sel_sens_rear  = _sname(idx_r)

    profiles: List[dict] = []

    for k, period_dt in enumerate(unique_periods):
        day_idxs = list(np.where(ic_arr == k)[0])

        sigs_matrix: List[np.ndarray] = []

        for j in day_idxs:
            signals = RawDataStore[j].get('Signals', {})
            ax_loc  = np.asarray(RawDataStore[j].get('Axis', []), dtype=float).reshape(-1)

            for sens_name in (sel_sens_front, sel_sens_rear):
                if sens_name in signals:
                    sig = np.asarray(signals[sens_name], dtype=float).reshape(-1)
                    if sig.size > 1 and ax_loc.size > 1:
                        L_min = min(sig.size, ax_loc.size)
                        sig_final = sig[:L_min]
                        ax_final  = ax_loc[:L_min]
                        if ax_final.size >= 2:
                            sig_interp = np.interp(
                                common_axis, ax_final, sig_final,
                                left=0.0, right=0.0
                            )
                            sigs_matrix.append(sig_interp)

        if not sigs_matrix:
            # Empty period — skip (MATLAB: Cache_Profiles(k) remains empty struct)
            continue

        sigs_mat = np.vstack(sigs_matrix)
        n_sigs, n_samples = sigs_mat.shape

        all_rms_profiles   = np.zeros((n_sigs, n_samples))
        all_skew_profiles  = np.zeros((n_sigs, n_samples))
        all_kurt_profiles  = np.zeros((n_sigs, n_samples))
        all_crest_profiles = np.zeros((n_sigs, n_samples))

        eps = np.finfo(float).eps

        for row_idx in range(n_sigs):
            sig_row = sigs_mat[row_idx]

            rms_row = np.sqrt(
                scipy.ndimage.uniform_filter1d(
                    sig_row ** 2, size=win_samples, mode='nearest'
                )
            )
            all_rms_profiles[row_idx] = rms_row

            all_skew_profiles[row_idx] = _moving_window_stat(
                sig_row, win_samples, scipy.stats.skew
            )
            all_kurt_profiles[row_idx] = _moving_window_stat(
                sig_row, win_samples,
                lambda x: scipy.stats.kurtosis(x, fisher=False)
            )
            mov_max_abs = scipy.ndimage.maximum_filter1d(
                np.abs(sig_row), size=win_samples, mode='nearest'
            )
            all_crest_profiles[row_idx] = mov_max_abs / (rms_row + eps)

        # MATLAB lines 2375-2385: nanmean over all signals
        profiles.append({
            'RMS':   np.nanmean(all_rms_profiles,   axis=0),
            'Skew':  np.nanmean(all_skew_profiles,  axis=0),
            'Kurt':  np.nanmean(all_kurt_profiles,  axis=0),
            'Crest': np.nanmean(all_crest_profiles, axis=0),
            'Axis':  common_axis,
            'Date':  period_dt,
        })

    return profiles
