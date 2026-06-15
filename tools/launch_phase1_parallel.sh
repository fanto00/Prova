#!/bin/bash
# Lancia 5 traduzioni parallele (Fase 1, moduli indipendenti)
# Usa Google Gemini API (freemium)

set -e

echo "==============================================="
echo "Fase 1: Traduzioni Parallele (5 Moduli)"
echo "==============================================="
echo ""
echo "Prerequisiti:"
echo "  ✓ GEMINI_API_KEY env var set (vedi SETUP_GEMINI.md)"
echo "  ✓ google-generativeai installed (pip install google-generativeai)"
echo ""

if [ -z "$GEMINI_API_KEY" ]; then
    echo "ERROR: GEMINI_API_KEY not set!"
    echo "Run: export GEMINI_API_KEY='<your-key>'"
    exit 1
fi

PYTHON_SCRIPT="tools/run_parallel_translations.py"

if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "ERROR: Script not found: $PYTHON_SCRIPT"
    exit 1
fi

echo "Starting 5 parallel processes..."
echo ""

# Lancia 5 process in background
(python "$PYTHON_SCRIPT" --module 1) > /tmp/module_1.log 2>&1 &
PID_1=$!
echo "  [1] PID $PID_1 → app/analysis/drawing.py"

(python "$PYTHON_SCRIPT" --module 2) > /tmp/module_2.log 2>&1 &
PID_2=$!
echo "  [2] PID $PID_2 → app/ui/dialogs.py"

(python "$PYTHON_SCRIPT" --module 3) > /tmp/module_3.log 2>&1 &
PID_3=$!
echo "  [3] PID $PID_3 → app/ui/datatips.py"

(python "$PYTHON_SCRIPT" --module 4) > /tmp/module_4.log 2>&1 &
PID_4=$!
echo "  [4] PID $PID_4 → app/ui/data_loading.py"

(python "$PYTHON_SCRIPT" --module 5) > /tmp/module_5.log 2>&1 &
PID_5=$!
echo "  [5] PID $PID_5 → app/ui/export.py"

echo ""
echo "Waiting for all processes..."
echo ""

# Aspetta che tutti finiscano
wait $PID_1 $PID_2 $PID_3 $PID_4 $PID_5

echo ""
echo "==============================================="
echo "✓ Fase 1 Complete!"
echo "==============================================="
echo ""
echo "Logs:"
echo "  Module 1: tail -f /tmp/module_1.log"
echo "  Module 2: tail -f /tmp/module_2.log"
echo "  Module 3: tail -f /tmp/module_3.log"
echo "  Module 4: tail -f /tmp/module_4.log"
echo "  Module 5: tail -f /tmp/module_5.log"
echo ""
echo "Next: Run TDD tests and math reviews"
echo "  python -m pytest tests/test_app_*.py -v"
echo ""
