"""
Signal alignment utilities faithful to Database_Allineamento_nomax.m.

Functions
---------
xcorr_lag(ref, sig, max_lag)
    Cross-correlation lag (samples) at peak — MATLAB xcorr convention.
macro_align_shift(reference, sig_res, spatial_res, max_lag_m)
    Coarse (macro) alignment: returns shift in metres (lines 226-230).
shift_signal_frac(sig, shift_m, spatial_res)
    Sub-sample fractional shift via phase-FFT (lines 1195-1224).
shift_fill(x, k)
    Integer shift with zero-fill, no wraparound (lines 1376-1385).
hilbert_envelope(x)
    abs(hilbert(x)) — instantaneous envelope.
build_align_template(sorted_runs, ref_sensor, focus_len, max_lag_samples, n_up, cfg)
    Robust alignment template: medoid seed, iterative xcorr→mean, interpft
    upsample (lines 1314-1374).
"""

from __future__ import annotations

import numpy as np
import scipy.signal

from railway_inspector.signal.resampling import interpft


# ---------------------------------------------------------------------------
# xcorr_lag
# ---------------------------------------------------------------------------

def xcorr_lag(ref: np.ndarray, sig: np.ndarray, max_lag: int) -> int:
    """Return the lag (in samples) of the cross-correlation peak.

    Replicates MATLAB::

        [corr_vals, lags] = xcorr(ref, sig, max_lag);
        [~, idx]          = max(corr_vals);
        lag               = lags(idx);

    The lags vector runs from ``-max_lag`` to ``+max_lag`` (length
    ``2*max_lag + 1``), exactly as MATLAB produces.

    Sign convention (matches MATLAB):
        A positive lag means *sig* must be shifted **right** (delayed) to
        align with *ref*, i.e. *ref* leads *sig* by ``lag`` samples.

    Parameters
    ----------
    ref : array_like, 1-D
        Reference signal.
    sig : array_like, 1-D
        Signal to correlate against *ref*.
    max_lag : int
        Maximum lag to consider.

    Returns
    -------
    lag : int
    """
    ref = np.asarray(ref, dtype=float)
    sig = np.asarray(sig, dtype=float)

    # scipy.signal.correlate(a, b) computes sum_k a[k] * b[k - lag],
    # i.e. the output at index m corresponds to lag = m - (N-1) where
    # N = max(len(a), len(b)) for 'full' mode.
    #
    # MATLAB xcorr(a, b, maxlag) returns corr[lag] = sum_k a[k] * b[k-lag]
    # which is the same definition.  scipy uses the same convention:
    # correlate(a, b)[m]  =  sum_k a[k+m] * b[k]   (mode='full')
    # Wait — let us be precise.
    #
    # scipy.signal.correlate(in1, in2, mode='full') computes:
    #   out[k] = sum_n in1[n] * conj(in2[n - (k - (len(in2)-1))])
    # so the lag at index k is  k - (len(in2) - 1).
    #
    # For our 1-D real case with equal-length inputs (length L):
    #   lag at index k  =  k - (L - 1),   k in [0, 2L-1]
    #
    # MATLAB xcorr(ref, sig, max_lag):
    #   corr[lag] = sum_k ref[k] * sig[k - lag]
    # which equals scipy.signal.correlate(ref, sig, 'full')
    # at the corresponding index.
    #
    # We just need to slice to ±max_lag around the centre.

    # MATLAB xcorr(ref, sig) computes Rxy(m) = sum_n ref(n+m)*sig(n).
    # scipy.signal.correlate(a, b)[k] = sum_n a[n+k-(N-1)] * b[n]
    # so correlate(ref, sig) gives lag = -(MATLAB lag).
    # Swapping to correlate(sig, ref) recovers the MATLAB sign convention.
    full = scipy.signal.correlate(sig, ref, mode='full')
    # Centre index of the full correlogram (lag = 0)
    centre = len(ref) - 1
    # Extract the window [centre - max_lag : centre + max_lag + 1]
    lo = centre - max_lag
    hi = centre + max_lag + 1
    window = full[lo:hi]

    # lags vector: -max_lag, ..., 0, ..., +max_lag  (MATLAB convention)
    lags = np.arange(-max_lag, max_lag + 1)

    idx = int(np.argmax(window))
    return int(lags[idx])


# ---------------------------------------------------------------------------
# macro_align_shift
# ---------------------------------------------------------------------------

def macro_align_shift(
    reference: np.ndarray,
    sig_res: np.ndarray,
    spatial_res: float,
    max_lag_m: float = 150.0,
) -> float:
    """Coarse alignment shift in metres (MATLAB lines 226-230).

    Parameters
    ----------
    reference : array_like
        Master reference signal.
    sig_res : array_like
        Current signal (already geo-resampled to the same spatial grid).
    spatial_res : float
        Spatial resolution in metres per sample (``CFG.SPATIAL_RES``).
    max_lag_m : float
        Maximum search range in metres.

    Returns
    -------
    shift_m : float
        Positive → *sig_res* must be shifted right to align with *reference*.
    """
    reference = np.asarray(reference, dtype=float)
    sig_res = np.asarray(sig_res, dtype=float)

    max_lag = int(round(max_lag_m / spatial_res))
    L_min = min(len(reference), len(sig_res))

    lag = xcorr_lag(reference[:L_min], sig_res[:L_min], max_lag)
    return lag * spatial_res


# ---------------------------------------------------------------------------
# shift_signal_frac
# ---------------------------------------------------------------------------

def shift_signal_frac(
    sig: np.ndarray,
    shift_m: float,
    spatial_res: float,
) -> np.ndarray:
    """Sub-sample fractional shift via phase-FFT (MATLAB lines 1195-1224).

    Equivalent MATLAB::

        N            = length(sig);
        shift_samples = shift_m / spatial_res;
        X            = fft(sig);
        k            = (0:N-1)';
        k(k > floor(N/2)) = k(k > floor(N/2)) - N;
        phase_shift  = exp(-1i * 2*pi * k * shift_samples / N);
        shifted_sig  = real(ifft(X .* phase_shift));

    Preserves the input dtype (float32 / float64) and shape (row / column).
    N <= 1 returns *sig* unchanged.

    Parameters
    ----------
    sig : array_like
        Input signal (1-D, real).
    shift_m : float
        Desired shift in metres (positive → shift right / delay).
    spatial_res : float
        Metres per sample.

    Returns
    -------
    shifted_sig : ndarray
        Same shape and dtype as *sig*.
    """
    sig = np.asarray(sig)

    # Preserve shape and dtype metadata
    is_row = sig.ndim == 2 and sig.shape[0] == 1
    is_1d_row = sig.ndim == 1  # treat 1-D as column (MATLAB default)
    is_single = sig.dtype == np.float32

    N = sig.size
    if N <= 1:
        return sig.copy()

    # Work in float64 column vector (matches MATLAB's double)
    s = sig.ravel().astype(np.float64)

    shift_samples = shift_m / spatial_res

    X = np.fft.fft(s)

    # Frequency index vector: 0, 1, ..., N-1; wrap k > floor(N/2) → k-N
    k = np.arange(N, dtype=np.float64)
    half_N = int(N // 2)
    k[k > half_N] -= N

    phase_shift = np.exp(-1j * 2.0 * np.pi * k * shift_samples / N)
    shifted = np.fft.ifft(X * phase_shift).real

    # Restore dtype
    if is_single:
        shifted = shifted.astype(np.float32)

    # Restore shape: 1-D inputs stay 1-D, row inputs stay row
    if is_row:
        return shifted.reshape(1, -1)
    # 1-D input → return 1-D (MATLAB returns column, but Python callers
    # pass 1-D arrays; we honour the original ndim)
    return shifted  # already 1-D from ravel + no reshape


# ---------------------------------------------------------------------------
# shift_fill
# ---------------------------------------------------------------------------

def shift_fill(x: np.ndarray, k: float) -> np.ndarray:
    """Integer shift with zero-fill, no wraparound (MATLAB lines 1376-1385).

    Equivalent MATLAB::

        x = x(:); n = numel(x); y = zeros(n,1); k = round(k);
        if k >= 0
            if k < n, y(1+k:n) = x(1:n-k); end
        else
            k = -k;
            if k < n, y(1:n-k) = x(1+k:n); end
        end

    Parameters
    ----------
    x : array_like
        Input signal (1-D).
    k : float
        Shift amount (will be rounded to nearest integer).
        Positive → shift right (delay); negative → shift left (advance).

    Returns
    -------
    y : ndarray, shape (n,)
        Shifted signal, zero-padded.
    """
    x = np.asarray(x, dtype=float).ravel()
    n = len(x)
    y = np.zeros(n, dtype=x.dtype)
    k = int(round(float(k)))

    if k >= 0:
        # MATLAB: y(1+k:n) = x(1:n-k)  →  0-based: y[k:n] = x[0:n-k]
        if k < n:
            y[k:n] = x[0:n - k]
    else:
        k = -k
        # MATLAB: y(1:n-k) = x(1+k:n)  →  0-based: y[0:n-k] = x[k:n]
        if k < n:
            y[0:n - k] = x[k:n]

    return y


# ---------------------------------------------------------------------------
# hilbert_envelope
# ---------------------------------------------------------------------------

def hilbert_envelope(x: np.ndarray) -> np.ndarray:
    """Instantaneous envelope: ``abs(hilbert(x))`` (MATLAB lines 480, 690-691, 1332)."""
    return np.abs(scipy.signal.hilbert(np.asarray(x, dtype=float)))


# ---------------------------------------------------------------------------
# build_align_template
# ---------------------------------------------------------------------------

def build_align_template(
    sorted_runs: list[dict],
    ref_sensor: str,
    focus_len: int,
    max_lag_samples: int,
    n_up: int,
    cfg,
) -> np.ndarray | None:
    """Build a robust alignment template (MATLAB lines 1314-1374).

    Algorithm
    ---------
    1. Extract the *focus* envelope (``abs(hilbert(...))``) for every valid
       run around the nominal zero-crossing (``RelativeAxis`` closest to 0).
    2. Select the medoid seed: the column most correlated to all others on
       average.
    3. Optionally restrict to the ``cfg.ALIGN_TEMPLATE_NRUNS`` most similar
       runs (if > 0 and smaller than total).
    4. Iterate ``cfg.ALIGN_TEMPLATE_ITERS`` times:
       - xcorr each envelope against the running reference → ``shift_fill`` →
         accumulate.
       - Compute mean; re-centre on the envelope's own peak via ``shift_fill``.
    5. Upsample to *n_up* via ``interpft``.

    Parameters
    ----------
    sorted_runs : list of dict
        Each entry must have:
        ``'Filt'``  — dict mapping sensor name → 1-D np.ndarray signal.
        ``'RelativeAxis'`` — 1-D np.ndarray of spatial positions (metres),
        with 0 at the nominal defect/joint location.
    ref_sensor : str
        Key in ``run['Filt']`` to use for alignment.
    focus_len : int
        Number of samples in the focus window (must be odd for symmetric
        centring; the half-radius is ``(focus_len - 1) // 2``).
    max_lag_samples : int
        Maximum xcorr lag (in native-resolution samples) during iteration.
    n_up : int
        Target length after ``interpft`` upsampling.
    cfg : CFG or similar
        Must expose ``ALIGN_TEMPLATE_NRUNS`` (int, 0 = use all) and
        ``ALIGN_TEMPLATE_ITERS`` (int).

    Returns
    -------
    template : ndarray, shape (n_up,), or None
        Upsampled envelope template, or ``None`` if fewer than 2 valid runs
        are found.
    """
    if not ref_sensor or focus_len < 3:
        return None

    corr_radius_samp = (focus_len - 1) // 2  # MATLAB: (focus_len - 1) / 2

    # ------------------------------------------------------------------
    # 1) Collect focus envelopes (native resolution)
    # ------------------------------------------------------------------
    R = len(sorted_runs)
    E_list: list[np.ndarray] = []

    for run in sorted_runs:
        filt = run.get('Filt', {})
        if ref_sensor not in filt:
            continue
        f = np.asarray(filt[ref_sensor], dtype=float).ravel()
        rel = np.asarray(run['RelativeAxis'], dtype=float).ravel()

        # Index of sample closest to RelativeAxis == 0
        z = int(np.argmin(np.abs(rel)))

        a = z - corr_radius_samp   # 0-based inclusive start
        b = z + corr_radius_samp   # 0-based inclusive end

        # MATLAB: a < 1 || b > length(f)  →  0-based: a < 0 || b >= len(f)
        if a < 0 or b >= len(f):
            continue

        # MATLAB: f(a:b)  with 1-based inclusive → f[a : b+1] 0-based
        segment = f[a: b + 1]          # length == focus_len
        e = hilbert_envelope(segment)

        if np.std(e) < 1e-9:
            continue

        E_list.append(e)

    if len(E_list) < 2:
        return None

    # Stack as columns: shape (focus_len, n_valid)
    E = np.column_stack(E_list)        # (focus_len, R_valid)

    # ------------------------------------------------------------------
    # 2) Medoid seed
    # ------------------------------------------------------------------
    # Normalise columns to unit norm
    norms = np.sqrt(np.sum(E ** 2, axis=0)) + np.finfo(float).eps
    En = E / norms[np.newaxis, :]      # (focus_len, R_valid)

    Cm = En.T @ En                     # (R_valid, R_valid) correlation matrix

    # score[i] = mean cross-correlation of column i with all other columns
    score = (np.sum(Cm, axis=1) - 1.0) / (Cm.shape[1] - 1)
    seed = int(np.argmax(score))
    ref = E[:, seed].copy()            # (focus_len,)

    # ------------------------------------------------------------------
    # 2b) Optionally restrict to NRUNS most similar to the medoid
    # ------------------------------------------------------------------
    cols = np.arange(E.shape[1])
    nruns = getattr(cfg, 'ALIGN_TEMPLATE_NRUNS', 0)
    if 0 < nruns < len(cols):
        # Sort by correlation with seed column (descending)
        ord_ = np.argsort(Cm[:, seed])[::-1]
        cols = ord_[:nruns]

    # ------------------------------------------------------------------
    # 3) Iterative alignment
    # ------------------------------------------------------------------
    iters = max(1, getattr(cfg, 'ALIGN_TEMPLATE_ITERS', 3))
    cF = corr_radius_samp              # 0-based index of nominal centre
    # MATLAB: cF = corr_radius_samp + 1  (1-based), which is 0-based cF

    for _ in range(iters):
        acc = np.zeros(focus_len, dtype=float)
        for jj in cols:
            lag = xcorr_lag(ref, E[:, jj], max_lag_samples)
            acc += shift_fill(E[:, jj], lag)
        ref = acc / len(cols)

        # Re-centre on the peak
        pk = int(np.argmax(ref))
        ref = shift_fill(ref, cF - pk)

    # ------------------------------------------------------------------
    # 4) Upsample
    # ------------------------------------------------------------------
    template = interpft(ref, n_up)
    return template.ravel()
