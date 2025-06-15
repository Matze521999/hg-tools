
# HG Tools

Dieses Repository enthält verschiedene Hilfsskripte für Systemadministration und IT-Infrastruktur. Die Skripte sind thematisch in folgende Bereiche gegliedert:

- `unifi/` – Skripte zur Abfrage und Verwaltung von UniFi-Controllern
- `vmware/` – Automatisierungen und Abfragen für VMware-Umgebungen
- `veeam/` – Hilfen für Backup-Management mit Veeam

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
Das Skript stellt eine Verbindung zu einem UniFi Controller her, liest die aktuelle Controller-Version, alle Sites sowie alle adoptieren Access Points aus und speichert folgende Informationen in eine CSV-Datei:

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

> In Arbeit – Hier sollen Skripte zur Abfrage und Automatisierung von vSphere-/ESXi-Umgebungen entstehen (z. B. VM-Status, Snapshots, Hostinformationen).

---

## 📂 Ordner: `veeam`

> In Arbeit – Geplant sind Skripte zur Auswertung von Backup-Jobs, Reportings oder Benachrichtigungen auf Basis der Veeam REST-API.

---

## 📜 Lizenz

MIT License – frei zur privaten und beruflichen Nutzung.

---

## 🙋 Support

Pull Requests und Issues sind willkommen!
