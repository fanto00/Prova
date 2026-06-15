# Setup Google Gemini API per Traduzioni Parallele

## 1. Ottieni la Chiave API Gratuita

Vai a: https://aistudio.google.com/app/apikey

- Clicca "Create API key in new project"
- Copia la chiave (stringa lunga)
- **NON fare commit di questa chiave** — salvala in `.env` o `.claude/settings.local.json`

## 2. Installa Dipendenze

```bash
pip install google-generativeai
```

## 3. Configura la Chiave

**Opzione A: File `.env` locale (sicuro)**
```
GEMINI_API_KEY=<tua-chiave-qui>
```

**Opzione B: `.claude/settings.local.json`** (se usi Claude Code)
```json
{
  "env": {
    "GEMINI_API_KEY": "<tua-chiave-qui>"
  }
}
```

**Opzione C: Variable d'ambiente PowerShell**
```powershell
$env:GEMINI_API_KEY="<tua-chiave-qui>"
```

## 4. Verifica la Chiave

```bash
python -c "import google.generativeai as genai; genai.configure(api_key='<chiave>'); print('OK')"
```

Se stampa "OK" → pronto!

## Note

- **Limite gratis:** 2M token/mese (~50K moderate-complexity requests)
- **Modelli disponibili:** `gemini-2.0-flash` (consigliato per velocità), `gemini-1.5-pro` (qualità)
- **Costo dopo limite:** ~$0.075 per milione di token input
- **Per questa Fase 1:** ~5 moduli × 250-800 LOC = ~300K token totali (ben sotto limite gratis)

