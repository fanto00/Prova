"""Calendar dialog + date-filter utilities (port of src_app/app.m:451-648).

Pure filter functions (filter_defect_by_dates, filter_db_by_dates) have no
side effects.  The dialog class (CalendarDialog / open_calendar_dialog) uses
PyQt6 in place of MATLAB figure/guidata/uicontrol.
"""
from __future__ import annotations

import calendar
from copy import deepcopy
from datetime import date, datetime, timedelta
from typing import Optional

from dateutil.relativedelta import relativedelta
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QColor, QFont
from PyQt6.QtWidgets import (
    QDialog,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPushButton,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

__all__ = [
    "open_calendar_dialog",
    "CalendarDialog",
    "filter_defect_by_dates",
    "filter_db_by_dates",
]

# ---------------------------------------------------------------------------
# Colour constants (mirror of render_calendar locals)
# ---------------------------------------------------------------------------
_BLU    = "#0073D9"          # [0 0.45 0.85] in MATLAB
_RNG    = "#DBE6F5"          # [0.86 0.90 0.96]
_GRIGIO = "#B3B3B3"          # [0.70 0.70 0.70]

_MESI   = [
    "gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno",
    "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre",
]
_GIORNI = ["Lu", "Ma", "Me", "Gi", "Ve", "Sa", "Do"]


# ---------------------------------------------------------------------------
# Pure helper — dateshift(d, 'start', 'day') → truncate to midnight
# ---------------------------------------------------------------------------
def _start_of_day(d: datetime) -> datetime:
    """Return datetime truncated to midnight (MATLAB dateshift 'start' 'day')."""
    return datetime(d.year, d.month, d.day)


def _start_of_month(d: datetime) -> datetime:
    """Return first day of the month at midnight."""
    return datetime(d.year, d.month, 1)


# ---------------------------------------------------------------------------
# Pure filter functions
# ---------------------------------------------------------------------------

def filter_defect_by_dates(
    defect: dict,
    d1: Optional[datetime],
    d2: Optional[datetime],
) -> dict:
    """Filter defect History to [d1, d2] and recalculate aggregates."""
    # MATLAB: if isempty(d1), return; end
    if d1 is None:
        return defect

    if d2 is None:
        d2 = d1

    # MATLAB: if d2 < d1, t=d1; d1=d2; d2=t; end
    if d2 < d1:
        d1, d2 = d2, d1

    # MATLAB: dk = dateshift([H.Date], 'start', 'day')
    d1_day = _start_of_day(d1)
    d2_day = _start_of_day(d2)

    dsub = deepcopy(defect)

    H = dsub.get("History", [])
    if not H:
        return dsub

    # MATLAB: Dsub.History = H(dk >= d1 & dk <= d2)
    hs = [r for r in H if d1_day <= _start_of_day(r["Date"]) <= d2_day]
    dsub["History"] = hs

    # MATLAB: if isempty(Hs) → zero out aggregates
    if not hs:
        if "Num_Occurrences" in dsub:
            dsub["Num_Occurrences"] = 0
        if "Num_Total_Runs" in dsub:
            dsub["Num_Total_Runs"] = 0
        if "Max_Severity" in dsub:
            dsub["Max_Severity"] = 0
        return dsub

    # Recalculate aggregates — same order as MATLAB
    amps = [r["Amp"] for r in hs]

    # MATLAB: if isfield(Dsub,'Max_Severity'), Dsub.Max_Severity = max(amps)
    if "Max_Severity" in dsub:
        dsub["Max_Severity"] = max(amps)

    # MATLAB: if isfield(Dsub,'Num_Total_Runs'), Dsub.Num_Total_Runs = numel(Hs)
    if "Num_Total_Runs" in dsub:
        dsub["Num_Total_Runs"] = len(hs)

    # MATLAB: if isfield(Dsub,'Num_Occurrences')
    #           if isfield(Hs,'Detected'), sum([Hs.Detected])
    #           else numel(Hs)
    if "Num_Occurrences" in dsub:
        if hs and "Detected" in hs[0]:
            dsub["Num_Occurrences"] = sum(1 for r in hs if r.get("Detected", False))
        else:
            dsub["Num_Occurrences"] = len(hs)

    return dsub


def filter_db_by_dates(
    db: list[dict],
    d1: Optional[datetime],
    d2: Optional[datetime],
) -> list[dict]:
    """Filter DB list by date range; remove defects with empty History after filter."""
    # MATLAB: if isempty(d1) || isempty(DB), DBsub = DB; return; end
    if d1 is None or not db:
        return db

    db_sub: list[dict] = []
    for defect in db:
        filtered = filter_defect_by_dates(defect, d1, d2)
        # MATLAB: keepDefect(i) = ~isempty(DBsub(i).History)
        if filtered.get("History"):
            db_sub.append(filtered)

    return db_sub


# ---------------------------------------------------------------------------
# CalendarDialog — PyQt6 port of open_calendar_dialog / render_calendar
# ---------------------------------------------------------------------------

class CalendarDialog(QDialog):
    """Modal calendar dialog — port of open_calendar_dialog + render_calendar."""

    def __init__(
        self,
        parent: QWidget,
        avail_days: list[datetime],
        date_from: Optional[datetime] = None,
        date_to: Optional[datetime] = None,
    ) -> None:
        """Initialise state and render the calendar (mirrors open_calendar_dialog)."""
        super().__init__(parent)
        self.setWindowTitle("Calendario")
        self.setWindowModality(Qt.WindowModality.ApplicationModal)
        self.setFixedSize(360, 430)
        self.setStyleSheet("background-color: white;")

        # --- state (MATLAB: st struct) ---
        self._avail: list[datetime] = sorted(
            _start_of_day(d) for d in avail_days
        )
        if date_from is not None:
            self._sel_from: Optional[datetime] = _start_of_day(date_from)
            self._sel_to: Optional[datetime] = (
                _start_of_day(date_to) if date_to is not None else self._sel_from
            )
            self._view_month = _start_of_month(self._sel_from)
        else:
            self._sel_from = None
            self._sel_to = None
            # MATLAB: st.view_month = dateshift(st.avail(end), 'start', 'month')
            self._view_month = _start_of_month(self._avail[-1])

        # MATLAB: st.stage = 0
        self._stage: int = 0

        # Result slots (set by _apply)
        self.result_from: Optional[datetime] = None
        self.result_to: Optional[datetime] = None

        # Build the main container layout; day buttons go in _day_widget
        self._root_layout = QVBoxLayout(self)
        self._root_layout.setContentsMargins(0, 0, 0, 0)
        self._root_layout.setSpacing(0)

        self._render()

    # ------------------------------------------------------------------
    # Internal render (replaces render_calendar)
    # ------------------------------------------------------------------

    def _render(self) -> None:
        """Rebuild all widgets from current state (MATLAB render_calendar)."""
        # Clear previous widgets
        while self._root_layout.count():
            item = self._root_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

        # --- Title label ---
        title = QLabel("Calendario")
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        font_title = QFont()
        font_title.setPointSize(13)
        font_title.setBold(True)
        title.setFont(font_title)
        title.setStyleSheet(f"color: {_BLU}; background-color: white;")
        title.setFixedHeight(30)
        self._root_layout.addWidget(title)

        # --- Month navigation row ---
        nav_row = QHBoxLayout()
        nav_row.setContentsMargins(18, 4, 18, 4)

        btn_prev = QPushButton("<")
        btn_prev.setFixedSize(36, 28)
        btn_prev.setFont(_font(12))
        btn_prev.clicked.connect(lambda: self._nav(-1))

        btn_next = QPushButton(">")
        btn_next.setFixedSize(36, 28)
        btn_next.setFont(_font(12))
        btn_next.clicked.connect(lambda: self._nav(+1))

        # MATLAB: sprintf('%s %d', mesi{month(st.view_month)}, year(st.view_month))
        month_label = QLabel(
            f"{_MESI[self._view_month.month - 1]} {self._view_month.year}"
        )
        month_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        font_month = _font(12, bold=True)
        month_label.setFont(font_month)
        month_label.setStyleSheet("background-color: white;")

        nav_row.addWidget(btn_prev)
        nav_row.addWidget(month_label, stretch=1)
        nav_row.addWidget(btn_next)
        self._root_layout.addLayout(nav_row)

        # --- Weekday headers ---
        hdr_row = QHBoxLayout()
        hdr_row.setContentsMargins(18, 0, 18, 0)
        hdr_row.setSpacing(2)
        for g in _GIORNI:
            lbl = QLabel(g)
            lbl.setAlignment(Qt.AlignmentFlag.AlignCenter)
            lbl.setFixedWidth(44)
            lbl.setStyleSheet(f"color: {_GRIGIO}; background-color: white;")
            lbl.setFont(_font(9, bold=True))
            hdr_row.addWidget(lbl)
        self._root_layout.addLayout(hdr_row)

        # --- Day grid ---
        # MATLAB: first = dateshift(st.view_month,'start','month')
        first = _start_of_month(self._view_month)
        # MATLAB: col0 = mod(weekday(first)-2, 7)  [0=Monday]
        col0 = first.weekday()                        # Python weekday() is 0=Monday
        # MATLAB: ndays = eomday(year(first), month(first))
        ndays = calendar.monthrange(first.year, first.month)[1]

        selA = self._sel_from
        selB = self._sel_to
        # MATLAB: if ~isempty(selA) && isempty(selB), selB = selA; end
        if selA is not None and selB is None:
            selB = selA
        # MATLAB: if ~isempty(selA) && ~isempty(selB) && selB < selA
        if selA is not None and selB is not None and selB < selA:
            selA, selB = selB, selA

        # MATLAB: oggi = dateshift(datetime('now'), 'start', 'day')
        oggi = _start_of_day(datetime.now())

        grid = QGridLayout()
        grid.setContentsMargins(18, 4, 18, 4)
        grid.setSpacing(2)

        for n in range(1, ndays + 1):
            d = first + timedelta(days=n - 1)
            pos_idx = col0 + (n - 1)
            row = pos_idx // 7
            col = pos_idx % 7

            avail_day = d in self._avail

            # Default style
            bg = "white"
            fg = "black"
            fw = False
            enabled = True

            # MATLAB: if ~avail_day, fg = grigio; en = 'off'; end
            if not avail_day:
                fg = _GRIGIO
                enabled = False

            # MATLAB: selection highlight
            if selA is not None:
                if d == selA or d == selB:
                    bg = _BLU
                    fg = "white"
                    fw = True
                elif selA < d < selB:
                    bg = _RNG

            # MATLAB: if avail_day && oggi && no selection endpoint
            if (
                avail_day
                and (selA is None or (d != selA and d != selB))
                and d == oggi
            ):
                fg = _BLU
                fw = True

            btn = QPushButton(str(n))
            btn.setFixedSize(44, 34)
            btn.setFont(_font(9, bold=fw))
            btn.setEnabled(enabled)
            btn.setStyleSheet(
                f"background-color: {bg}; color: {fg}; border: none;"
            )
            btn.clicked.connect(_make_pick_cb(self, d))
            grid.addWidget(btn, row, col)

        grid_widget = QWidget()
        grid_widget.setLayout(grid)
        grid_widget.setStyleSheet("background-color: white;")
        self._root_layout.addWidget(grid_widget, stretch=1)

        # --- Bottom buttons ---
        btn_row = QHBoxLayout()
        btn_row.setContentsMargins(18, 8, 18, 12)
        btn_row.setSpacing(8)

        btn_all = QPushButton("Tutti i Giorni")
        btn_all.setFixedHeight(32)
        btn_all.clicked.connect(self._clear)

        btn_cancel = QPushButton("Annulla")
        btn_cancel.setFixedSize(90, 32)
        btn_cancel.clicked.connect(self.reject)

        btn_apply = QPushButton("Applica")
        btn_apply.setFixedSize(92, 32)
        btn_apply.setStyleSheet(
            f"background-color: {_BLU}; color: white; font-weight: bold;"
        )
        btn_apply.clicked.connect(self._apply)

        btn_row.addWidget(btn_all)
        btn_row.addWidget(btn_cancel)
        btn_row.addWidget(btn_apply)
        self._root_layout.addLayout(btn_row)

    # ------------------------------------------------------------------
    # Callbacks — mirrors calendar_nav / calendar_pick / calendar_clear / calendar_apply
    # ------------------------------------------------------------------

    def _nav(self, delta: int) -> None:
        """Shift view_month by delta months (MATLAB calendar_nav)."""
        # MATLAB: st.view_month = dateshift(st.view_month + calmonths(delta), 'start', 'month')
        self._view_month = _start_of_month(
            self._view_month + relativedelta(months=delta)
        )
        self._render()

    def _pick(self, d: datetime) -> None:
        """State machine: first click sets sel_from, second sets sel_to (MATLAB calendar_pick)."""
        d = _start_of_day(d)
        if self._stage == 0:
            self._sel_from = d
            self._sel_to = None
            self._stage = 1
        else:
            self._sel_to = d
            # MATLAB: if ~isempty(st.sel_from) && st.sel_to < st.sel_from → swap
            if self._sel_from is not None and self._sel_to < self._sel_from:
                self._sel_from, self._sel_to = self._sel_to, self._sel_from
            self._stage = 0
        self._render()

    def _clear(self) -> None:
        """Reset selection and apply immediately (MATLAB calendar_clear)."""
        self._sel_from = None
        self._sel_to = None
        self._stage = 0
        self._apply()

    def _apply(self) -> None:
        """Store result and accept dialog (MATLAB calendar_apply, minus main-window refresh)."""
        if self._sel_from is None:
            self.result_from = None
            self.result_to = None
        else:
            d1 = self._sel_from
            d2 = self._sel_to if self._sel_to is not None else d1
            # MATLAB: if d2 < d1, t=d1; d1=d2; d2=t; end
            if d2 < d1:
                d1, d2 = d2, d1
            self.result_from = d1
            self.result_to = d2
        self.accept()


# ---------------------------------------------------------------------------
# Public entry point (MATLAB open_calendar_dialog)
# ---------------------------------------------------------------------------

def open_calendar_dialog(
    parent: QWidget,
    avail_days: list[datetime],
    date_from: Optional[datetime] = None,
    date_to: Optional[datetime] = None,
) -> tuple[Optional[datetime], Optional[datetime]] | None:
    """Open the modal calendar dialog; return (d1, d2) or None if cancelled.

    The caller is responsible for refreshing the main window (refresh_defect_list
    equivalent) after this call returns.
    """
    if not avail_days:
        QMessageBox.information(
            parent,
            "Calendario",
            "Nessun giorno disponibile (carica prima una tratta).",
        )
        return None

    dlg = CalendarDialog(parent, avail_days, date_from, date_to)
    if dlg.exec() == QDialog.DialogCode.Accepted:
        return dlg.result_from, dlg.result_to
    return None


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

def _font(size: int, bold: bool = False) -> QFont:
    """Return a QFont with given size and optional bold."""
    f = QFont()
    f.setPointSize(size)
    f.setBold(bold)
    return f


def _make_pick_cb(dlg: CalendarDialog, d: datetime):
    """Closure factory — avoids late-binding bug in loop (MATLAB @(s,e) calendar_pick(dlg,d))."""
    def _cb() -> None:
        dlg._pick(d)
    return _cb
