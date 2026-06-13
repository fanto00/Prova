"""
Signal resampling utilities faithful to their MATLAB equivalents.

Functions
---------
interpft(x, n)
    Fourier-method upsampling — equivalent to MATLAB ``interpft(x, n)``.
interp1_zero(x, y, xq)
    Piecewise-linear interpolation with out-of-range fill = 0 —
    equivalent to MATLAB ``interp1(x, y, xq, 'linear', 0)``.
"""

import numpy as np


def interpft(x: np.ndarray, n: int) -> np.ndarray:
    """Upsample *x* to length *n* via FFT zero-padding.

    Replicates MATLAB ``interpft(x, n)`` exactly:

    1. Compute the DFT of the length-N input.
    2. Build a length-n spectrum by:
       - copying the positive-frequency bins (0 … floor(N/2)-1),
       - when N is even, placing *half* of the Nyquist bin at position
         N//2 in the new spectrum and *half* at the mirror position
         (n - N//2) so that the result stays real after IFFT,
       - zero-padding the high-frequency interior,
       - copying the negative-frequency bins (N//2+1 … N-1, or
         (N+1)//2 … N-1 when N is odd).
    3. Scale by ``n / N`` (IFFT normalises by 1/n, but the original
       signal was normalised by 1/N, so the net factor is n/N).
    4. Return ``real(ifft(spectrum))``.

    Parameters
    ----------
    x : array_like, shape (N,)
        Input signal (1-D).  Real input produces real output.
    n : int
        Desired output length.  Must be >= N for pure upsampling,
        but the algorithm is valid for any n > 0.

    Returns
    -------
    y : ndarray, shape (n,)
        Resampled signal.

    References
    ----------
    MATLAB documentation: interpft
    https://www.mathworks.com/help/signal/ref/interpft.html
    """
    x = np.asarray(x, dtype=float)
    N = len(x)

    Y = np.fft.fft(x)           # length-N spectrum

    # Allocate the output spectrum (complex128 zero-filled)
    Z = np.zeros(n, dtype=complex)

    if N == 1:
        # DC only
        Z[0] = Y[0]
    elif N % 2 == 0:
        # --- Even-length input ---
        # Positive frequencies: bins 0 … N//2-1
        half = N // 2
        Z[:half] = Y[:half]
        # Nyquist bin: split equally between position half and its mirror
        # so that the IFFT remains real.
        Z[half] += Y[half] / 2.0
        Z[n - half] += Y[half] / 2.0
        # Negative frequencies: bins N//2+1 … N-1  →  n-half+1 … n-1
        neg_len = N - half - 1          # number of negative-freq bins
        if neg_len > 0:
            Z[n - neg_len:] = Y[half + 1:]
    else:
        # --- Odd-length input ---
        # Positive frequencies: bins 0 … (N-1)//2
        pos = (N + 1) // 2             # includes DC; = (N-1)//2 + 1
        Z[:pos] = Y[:pos]
        # Negative frequencies: bins pos … N-1  →  n-(N-pos) … n-1
        neg_len = N - pos
        if neg_len > 0:
            Z[n - neg_len:] = Y[pos:]

    # Scale: compensate for the change in DFT normalisation
    y = np.fft.ifft(Z) * (n / N)

    # For real input MATLAB always returns real output
    if np.isrealobj(x):
        return y.real
    return y


def interp1_zero(
    x: np.ndarray,
    y: np.ndarray,
    xq: np.ndarray,
) -> np.ndarray:
    """Piecewise-linear interpolation with zero fill outside the data range.

    Replicates MATLAB ``interp1(x, y, xq, 'linear', 0)``:
    query points that fall strictly outside ``[x[0], x[-1]]`` are
    assigned the value 0.0 rather than NaN or an extrapolated value.

    Parameters
    ----------
    x : array_like, shape (N,)
        Strictly monotonically increasing sample positions.
    y : array_like, shape (N,)
        Sample values at positions *x*.
    xq : array_like, shape (M,)
        Query positions.

    Returns
    -------
    yq : ndarray, shape (M,)
        Interpolated values.

    References
    ----------
    MATLAB documentation: interp1
    https://www.mathworks.com/help/matlab/ref/interp1.html
    """
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)
    xq = np.asarray(xq, dtype=float)

    return np.interp(xq, x, y, left=0.0, right=0.0)
