"""Pure plotting helpers for single-run signals and temporal trend metrics.

No UI state, no globals, no callbacks — only matplotlib Axes side-effects.
All parameter defaults mirror the MATLAB app.m originals (lines 2087-2206, 3300-3309).
"""
from __future__ import annotations

import numpy as np
from matplotlib.axes import Axes
from scipy.ndimage import uniform_filter1d

# ---------------------------------------------------------------------------
# Constants (extracted from MATLAB literals — do not change without MATLAB diff)
# ---------------------------------------------------------------------------
_FRONT_COLOR = "b"          # MATLAB: 'b-o'   line 2200
_FRONT_MARKER = "o"         # MATLAB: 'b-o'   line 2200
_REAR_COLOR = "r"           # MATLAB: 'r-s'   line 2201
_REAR_MARKER = "s"          # MATLAB: 'r-s'   line 2201
_MARKER_SIZE = 4            # MATLAB: 'MarkerSize', 4   lines 2200-2201
_TREND_FONTSIZE_TITLE = 9   # MATLAB: 'FontSize', 9   line 2202
_TREND_FONTSIZE_LABEL = 8   # MATLAB: 'FontSize', 8   line 2203
_DEFAULT_FONTSIZE = 9       # MATLAB: set(ax,'FontSize',8) line 3303 (Python default bumped to 9)
_LINEWIDTH = 1.0            # MATLAB: 'LineWidth', 1.0  lines 3300-3301
_SINGLE_COLOR = [0.0, 0.4, 0.8]   # MATLAB: 'Color',[0 0.4 0.8]  line 5034
_SINGLE_LINEWIDTH = 1.2            # MATLAB: 'LineWidth', 1.2      line 5034


# ---------------------------------------------------------------------------
# 1. plot_temporal_trend
# ---------------------------------------------------------------------------

def plot_temporal_trend(
    ax: Axes,
    dates: np.ndarray,
    series_front: np.ndarray,
    series_rear: np.ndarray,
    title: str,
    ylabel: str,
    *,
    show_legend: bool = True,
    legend_loc: str = "upper left",
    datetick_fmt: str | None = None,
    fontsize_title: int = _TREND_FONTSIZE_TITLE,
    fontsize_label: int = _TREND_FONTSIZE_LABEL,
    **kwargs,
) -> None:
    """Plot front/rear daily-mean trend with MATLAB-matching colors and markers."""
    # MATLAB lines 2200-2201: 'b-o' MarkerFaceColor='b', 'r-s' MarkerFaceColor='r'
    ax.plot(
        dates, series_front,
        color=_FRONT_COLOR,
        linestyle="-",
        marker=_FRONT_MARKER,
        markerfacecolor=_FRONT_COLOR,
        markersize=_MARKER_SIZE,
        label="Front",
    )
    ax.plot(
        dates, series_rear,
        color=_REAR_COLOR,
        linestyle="-",
        marker=_REAR_MARKER,
        markerfacecolor=_REAR_COLOR,
        markersize=_MARKER_SIZE,
        label="Rear",
    )

    # MATLAB line 2189: grid(ax,'on')
    ax.grid(True)

    # MATLAB line 2202: title(...,'FontSize',9,'FontWeight','bold')
    ax.set_title(title, fontsize=fontsize_title, fontweight="bold")

    # MATLAB line 2203: ylabel(...,'FontSize',8)
    ax.set_ylabel(ylabel, fontsize=fontsize_label)

    # MATLAB line 2204: datetick(ax,'x','dd/mm/yy','keeplimits','keepticks')
    if datetick_fmt is not None:
        import matplotlib.dates as mdates
        ax.xaxis.set_major_formatter(mdates.DateFormatter(datetick_fmt))
        ax.figure.autofmt_xdate()

    # MATLAB line 2205: legend(...,'Location','northwest','Orientation','horizontal')
    if show_legend:
        ax.legend(loc=legend_loc, ncol=2)


# ---------------------------------------------------------------------------
# 2. plot_single_signal
# ---------------------------------------------------------------------------

def plot_single_signal(
    ax: Axes,
    x_axis: np.ndarray,
    signal: np.ndarray,
    label: str = "Signal",
    color: object = _SINGLE_COLOR,
    *,
    linewidth: float = _SINGLE_LINEWIDTH,
    xlabel: str = "Posizione [m]",
    ylabel: str = "m/s^2",
    **kwargs,
) -> None:
    """Plot a single spatial signal with standard axis labels and grid."""
    # MATLAB line 5034: plot(ax_s, axis, sig, 'Color',[0 0.4 0.8],'LineWidth',1.2)
    ax.plot(x_axis, signal, color=color, linewidth=linewidth, label=label)

    # MATLAB line 5032: grid(ax_s,'on')
    ax.grid(True)

    # MATLAB lines 5036: xlabel/ylabel
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)


# ---------------------------------------------------------------------------
# 3. plot_rms_envelope
# ---------------------------------------------------------------------------

def plot_rms_envelope(
    ax: Axes,
    x_axis: np.ndarray,
    signal: np.ndarray,
    window_samples: int,
    label: str = "RMS",
    color: object = "r",
    *,
    linewidth: float = _LINEWIDTH,
    **kwargs,
) -> None:
    """Compute and plot RMS envelope via movmean-equivalent (uniform_filter1d, mode='nearest')."""
    # MATLAB lines 2087-2089:
    #   if length(sig) >= win_samples_base
    #       rms_sig = sqrt(movmean(sig.^2, win_samples_base))
    #
    # scipy.ndimage.uniform_filter1d with mode='nearest' replicates MATLAB movmean
    # EndValues='shrink' behaviour at the array boundaries.
    if len(signal) >= window_samples:
        rms_sig = np.sqrt(
            uniform_filter1d(signal ** 2, size=window_samples, mode="nearest")
        )
    else:
        # MATLAB fallback line 2094: val_max_rms = max(abs(sig))
        # Edge-case: signal shorter than window — use pointwise absolute value as envelope
        rms_sig = np.abs(signal)

    ax.plot(x_axis, rms_sig, color=color, linewidth=linewidth, label=label)
    ax.grid(True)


# ---------------------------------------------------------------------------
# 4. plot_signal_comparison
# ---------------------------------------------------------------------------

def plot_signal_comparison(
    ax: Axes,
    x_axis: np.ndarray,
    original: np.ndarray,
    reconstructed: np.ndarray,
    title: str | None = None,
    *,
    xlabel: str = "Posizione [m]",
    ylabel: str = "Inviluppo RMS [m/s^2]",
    fontsize: int = _DEFAULT_FONTSIZE,
    **kwargs,
) -> None:
    """Plot original (blue solid) vs reconstructed (red dashed) on the same axes."""
    # MATLAB line 3300: plot(ax, xg, orig_row,  'b-',  'LineWidth', 1.0)
    ax.plot(x_axis, original, "b-", linewidth=_LINEWIDTH, label="Original")
    # MATLAB line 3301: plot(ax, xg, recon_row, 'r--', 'LineWidth', 1.0)
    ax.plot(x_axis, reconstructed, "r--", linewidth=_LINEWIDTH, label="Reconstructed")

    # MATLAB line 3303: grid(ax,'on')
    ax.grid(True)

    # MATLAB line 3302: title(ax, ch_label, 'FontWeight','normal','FontSize',9)
    if title is not None:
        ax.set_title(title, fontweight="normal", fontsize=fontsize)

    # MATLAB lines 3306-3309: xlabel/ylabel condizionali — qui forniti come default
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)


# ---------------------------------------------------------------------------
# 5. setup_signal_axes
# ---------------------------------------------------------------------------

def setup_signal_axes(
    ax: Axes,
    title: str | None = None,
    xlabel: str | None = None,
    ylabel: str | None = None,
    fontsize: int = _DEFAULT_FONTSIZE,
    *,
    xlim: tuple[float, float] | None = None,
    ylim: tuple[float, float] | None = None,
    **kwargs,
) -> None:
    """Apply standard grid/font/label formatting to an existing axes object."""
    # MATLAB line 3303: grid(ax,'on')
    ax.grid(True)

    # MATLAB line 3303: set(ax,'FontSize',8)
    ax.tick_params(labelsize=fontsize)
    ax.xaxis.label.set_fontsize(fontsize)
    ax.yaxis.label.set_fontsize(fontsize)

    if title is not None:
        ax.set_title(title, fontsize=fontsize)

    # MATLAB lines 3306, 3309: xlabel/ylabel condizionali
    if xlabel is not None:
        ax.set_xlabel(xlabel, fontsize=fontsize)
    if ylabel is not None:
        ax.set_ylabel(ylabel, fontsize=fontsize)

    # MATLAB line 3304: xlim(ax,[xg(1) xg(end)])
    if xlim is not None:
        ax.set_xlim(xlim)
    if ylim is not None:
        ax.set_ylim(ylim)
