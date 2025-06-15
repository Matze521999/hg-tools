
# HG Tools

Dieses Repository enthält verschiedene Hilfsskripte für mich selbst. Die Skripte sind thematisch in folgende Bereiche gegliedert:

- `unifi/` – Hilfen für Unifi Network Controller
- `vmware/` – Hilfen für ESXi
- `veeam/` – Hilfen für Veeam B&R

---

## 🔧 Struktur

```
hg-tools/
│
├── unifi/
│   └── unifi-get-ssid-info.py
│   └── ...
│
├── vmware/
│   └── ...
│
├── veeam/
│   └── ...
```

---

## 📂 Ordner: `unifi`

### 🔍 Skript: `unifi-get-ssid-info.py`

**Zweck:**  
Das Skript stellt eine Verbindung zu einem UniFi Controller her, liest alle Sites sowie alle adoptieren AccessPoints aus und speichert folgende Informationen in eine CSV-Datei:

- Site-Name
- Access Point Name
- IP-Adresse
- MAC-Adresse
- Firmware-Version
- Modell
- Status (online/offline)
- Uptime
- Unterstützte Frequenzbänder (2.4GHz / 5GHz / 6GHz)
- SSIDs, die der AP ausstrahlt

**Anwendungsbeispiel:**

```bash
python unifi-get-ssid-info.py
```

**Ablauf:**

1. Es wird die IP-Adresse des UniFi Controllers abgefragt.
2. Danach erfolgt die Anmeldung (Benutzername & Passwort).
3. Das Skript generiert automatisch eine `unifi_ap_report.csv`.

**Filter & Analyse:**

- Die CSV-Datei ist so strukturiert, dass sie leicht in Excel oder ähnlichen Programmen nach bestimmten Kriterien (z. B. SSID oder Modell) gefiltert oder sortiert werden kann.

**Voraussetzungen:**

- Python 3.8+
- Abhängigkeiten: siehe [requirements.txt](./requirements.txt)

Installation der Abhängigkeiten:

```bash
pip install -r requirements.txt
```

---

## 📂 Ordner: `vmware`

> In Arbeit...

---

## 📂 Ordner: `veeam`

> In Arbeit...

---

## 📜 Lizenz

MIT License – frei zur privaten und beruflichen Nutzung.

---

## 🙋 Support

Gibt es nicht ;)
