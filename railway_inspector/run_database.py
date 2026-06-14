"""
run_database.py
===============
Entry point replicating Database_Allineamento_nomax.m lines 6-130, 786, 1393-1394.

Usage:
    python -m railway_inspector.run_database
    # or
    python railway_inspector/run_database.py
"""

from __future__ import annotations

import os
import time

import numpy as np

from railway_inspector.config import default_config
from railway_inspector.io.excel_loader import load_infrastructure_map, load_joints_map
from railway_inspector.io.database_io import save_master_db
from railway_inspector.database.builder import build_database_for_route


def main() -> None:
    t_start = time.perf_counter()

    cfg = default_config()

    # =========================================================================
    # 2. CARICAMENTO MAPPA INFRASTRUTTURA (MATLAB lines 72-86)
    # =========================================================================
    print("Caricamento mappa deviatoi e raccordi...")
    try:
        track_map_raw = load_infrastructure_map(cfg.excel_path, cfg.TRACK_TYPE)
        # Convert to list-of-dicts for builder
        if hasattr(track_map_raw, "to_dict"):
            track_map = track_map_raw.to_dict("records")
        else:
            track_map = list(track_map_raw) if track_map_raw is not None else []
        print(f"Mappa caricata: {len(track_map)} elementi trovati.")
    except Exception as exc:
        print(f"Attenzione: procedo senza matching infrastruttura: {exc}")
        track_map = []

    joints_map = None
    if cfg.ONLY_JOINTS:
        try:
            joints_map = load_joints_map(cfg.JOINTS_EXCEL, cfg.TRACK_TYPE)
            print(f"Mappa giunti caricata: {len(joints_map)} giunti totali.")
        except Exception as exc:
            print(f"Attenzione: impossibile caricare mappa giunti: {exc}")
            joints_map = None

    # =========================================================================
    # 3. LOOP PRINCIPALE (MATLAB lines 91-103)
    # =========================================================================
    if not os.path.isdir(cfg.root_folder):
        print(f"ERRORE: root_folder non trovata: {cfg.root_folder}")
        return

    sub_dirs = [
        d for d in os.listdir(cfg.root_folder)
        if os.path.isdir(os.path.join(cfg.root_folder, d))
    ]
    sub_dirs = sorted(sub_dirs)

    # Route filter (MATLAB lines 95-103)
    if cfg.ROUTE_FILTER:
        sub_dirs = [d for d in sub_dirs if cfg.ROUTE_FILTER.lower() in d.lower()]
        if not sub_dirs:
            print(f"Nessuna tratta corrisponde al filtro \"{cfg.ROUTE_FILTER}\".")
            return
        print(
            f"Filtro tratta attivo \"{cfg.ROUTE_FILTER}\": "
            f"{len(sub_dirs)} tratte selezionate."
        )

    os.makedirs(cfg.save_folder, exist_ok=True)

    for route_name in sub_dirs:
        route_path = os.path.join(cfg.root_folder, route_name)
        print(f"\nSTART TRATTA: {route_name}")

        # --- Giunti di questa tratta (MATLAB lines 113-127) ---
        route_joints = None
        route_joint_labels = None

        if cfg.ONLY_JOINTS and joints_map is not None:
            # Filter joints for this route
            try:
                if hasattr(joints_map, "iterrows"):
                    # pandas DataFrame
                    mask = joints_map["Stations"].str.strip().str.lower() == route_name.strip().lower()
                    jt = joints_map[mask].copy()
                    if len(jt) == 0:
                        print(f"   Nessun giunto per \"{route_name}\": skip tratta.")
                        continue
                    jt = jt.sort_values("Position")
                    route_joints = jt["Position"].tolist()
                    route_joint_labels = jt["Joint"].tolist()
                    print(f"   Giunti in tratta: {len(route_joints)}")
                else:
                    # list-of-dicts fallback
                    filtered = [
                        j for j in joints_map
                        if str(j.get("Stations", "")).strip().lower() == route_name.strip().lower()
                    ]
                    if not filtered:
                        print(f"   Nessun giunto per \"{route_name}\": skip tratta.")
                        continue
                    filtered.sort(key=lambda j: float(j.get("Position", 0)))
                    route_joints = [float(j["Position"]) for j in filtered]
                    route_joint_labels = [str(j.get("Joint", "")) for j in filtered]
                    print(f"   Giunti in tratta: {len(route_joints)}")
            except Exception as exc:
                print(f"   WARN giunti per {route_name}: {exc}")

        # --- Gather .mat files (MATLAB lines 129-132) ---
        mat_files: list[str] = []
        for root, _dirs, fnames in os.walk(route_path):
            for fn in fnames:
                if not fn.endswith(".mat"):
                    continue
                if fn.startswith("."):
                    continue
                if "Database_damage" in fn:
                    continue
                mat_files.append(os.path.join(root, fn))

        if not mat_files:
            print("   Nessun file .mat trovato: skip tratta.")
            continue

        mat_files.sort()
        print(f"   File trovati: {len(mat_files)}")

        # --- Build database ---
        master_db = build_database_for_route(
            files=mat_files,
            route_name=route_name,
            cfg=cfg,
            track_map=track_map if track_map else None,
            route_joints=route_joints,
            route_joint_labels=route_joint_labels,
        )

        # --- Save (MATLAB line 786) ---
        if master_db:
            out_path = os.path.join(cfg.save_folder, f"Database_damage_{route_name}.pkl")
            save_master_db(master_db, out_path)
            print(f"   Salvato: {out_path} ({len(master_db)} difetti).")
        else:
            print("   Nessun difetto trovato per questa tratta.")

    t_end = time.perf_counter()
    elapsed = t_end - t_start
    print(f"\nCompletato in {elapsed:.1f} s ({elapsed / 60:.1f} min).")


if __name__ == "__main__":
    main()
