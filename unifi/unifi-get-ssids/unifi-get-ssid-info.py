#!/usr/bin/env python
# coding: utf-8

# In[13]:


import requests
import urllib3
import csv
import os
from datetime import timedelta

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

def login(controller_ip, username, password):
    base_url = f"https://{controller_ip}:8443"
    login_url = f"{base_url}/api/login"

    session = requests.Session()
    session.verify = False

    response = session.post(login_url, json={
        "username": username,
        "password": password
    })

    if response.status_code == 200 and response.json().get("meta", {}).get("rc") == "ok":
        print("[+] Login erfolgreich.")
        return session, base_url
    else:
        print("[-] Login fehlgeschlagen:", response.text)
        return None, None

def get_sites(session, base_url):
    url = f"{base_url}/api/self/sites"
    response = session.get(url)
    return response.json().get("data", []) if response.status_code == 200 else []

def get_accesspoints(session, base_url, site_name):
    url = f"{base_url}/api/s/{site_name}/stat/device"
    response = session.get(url)
    if response.status_code != 200:
        return []
    return [d for d in response.json().get("data", []) if d.get("type") == "uap"]

def extract_ssid_lines(ap, site_desc):
    lines = []
    wlan_table = ap.get("vap_table", [])
    name = ap.get("name", "")
    mac = ap.get("mac", "")
    ip = ap.get("ip", "")
    firmware = ap.get("version", "")
    model = ap.get("model", "")
    uptime_seconds = ap.get("uptime", 0)
    uptime_days = round(uptime_seconds / 86400, 1)
    status = "Online" if ap.get("state", 0) == 1 else "Offline"
    device_name = ap.get("device_display_name") or model

    for vap in wlan_table:
        ssid = vap.get("essid", "")
        radio = vap.get("radio", "")
        if not ssid:
            continue

        band = {
            "ng": "2.4GHz",
            "na": "5GHz",
            "ac": "5GHz"
        }.get(radio, radio)

        lines.append([
            site_desc, name, mac, ip, firmware, device_name, uptime_days, status, ssid, band
        ])

    return lines

def write_csv(rows, filename="unifi_ap_ssid_report.csv"):
    header = [
        "Site", "Name", "MAC", "IP", "Firmware", "Modell", "Uptime (Tage)", "Status", "SSID", "Band"
    ]
    with open(filename, mode="w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)
    print(f"[+] CSV gespeichert: {os.path.abspath(filename)}")

def main():
    controller_ip = input("Controller-IP: ").strip()
    username = input("Benutzername: ").strip()
    password = input("Passwort: ").strip()

    session, base_url = login(controller_ip, username, password)
    if not session:
        return

    sites = get_sites(session, base_url)
    all_rows = []

    for site in sites:
        site_desc = site.get("desc", "")
        site_name = site.get("name", "")
        aps = get_accesspoints(session, base_url, site_name)

        for ap in aps:
            lines = extract_ssid_lines(ap, site_desc)
            all_rows.extend(lines)

    write_csv(all_rows)

if __name__ == "__main__":
    main()


# In[ ]:





# In[ ]:




