### 🔍 Skript: `unifi-get-ssid-info.py`

**Zweck:**  
Das Skript stellt eine Verbindung zu einem UniFi Controller her, liest alle Sites sowie alle adoptieren AccessPoints aus und speichert folgende Informationen in eine CSV-Datei:

**Anwendung:**
```bash
pip install -r requirements.txt
```
```bash
python unifi-get-ssid-info.py
```

**Ablauf:**

1. Es wird die IP-Adresse des UniFi Controllers abgefragt.
2. Danach erfolgt die Anmeldung (Benutzername & Passwort).
3. Das Skript generiert automatisch eine `unifi_ap_report.csv`.

**Voraussetzungen:**

- Python 3.8+
- Abhängigkeiten: siehe [requirements.txt](./requirements.txt)

---

## 🙋 Support

Gibt es nicht ;)
