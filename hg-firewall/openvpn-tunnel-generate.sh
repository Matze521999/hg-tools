#!/bin/bash
# Erstellt auf Basis der vorhandenen OpenVPN-Konfigurationen
# den nächsten Road-Warrior-Tunnel:
# - ermittelt höchsten belegten Port (netstat, fallback: .conf)
# - nimmt die Konfig mit diesem Port als Vorlage
# - berechnet das nächste /30-Netz in 192.168.200.x
# - erstellt neue .conf + .key
# - kopiert .conf/.key nach /home/pchfw und setzt chown pchfw
# - optional: systemctl start/enable openvpn@NAME
#
# Optionaler Dry-Run:
#   openvpn-create-next-roadwarrior.sh --dry-run [NAME]
#   openvpn-create-next-roadwarrior.sh -n [NAME]

set -euo pipefail

OPENVPN_DIR="/etc/openvpn"
CLIENT_DIR="/home/pchfw"

# Farben
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
RED=$'\e[31m'
NC=$'\e[0m'

DRY_RUN=0

# ---------------------------------------------------------
# 0) Parameter auswerten (Dry-Run / Name)
# ---------------------------------------------------------
if [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]]; then
    DRY_RUN=1
    shift
    echo "${YELLOW}*** DRY-RUN: Es werden KEINE Änderungen vorgenommen. ***${NC}"
    echo
fi

NEW_NAME="${1:-}"

echo "=== OpenVPN Road-Warrior Auto-Creator ==="
echo

# ---------------------------------------------------------
# 1) Neuen Namen abfragen
# ---------------------------------------------------------
if [[ -z "$NEW_NAME" ]]; then
    read -rp "Name der neuen Konfiguration (ohne .conf/.key): " NEW_NAME
fi

if [[ -z "$NEW_NAME" ]]; then
    echo "Kein Name angegeben, Abbruch."
    exit 1
fi

if [[ -e "${OPENVPN_DIR}/${NEW_NAME}.conf" || -e "${OPENVPN_DIR}/${NEW_NAME}.key" ]]; then
    echo "${RED}Fehler:${NC} Es existiert bereits eine Konfiguration oder ein Key mit diesem Namen:"
    ls -1 "${OPENVPN_DIR}/${NEW_NAME}."* 2>/dev/null || true
    exit 1
fi

# ---------------------------------------------------------
# 2) Höchsten Port via netstat ermitteln
# ---------------------------------------------------------
max_port=0

if command -v netstat >/dev/null 2>&1; then
    echo "Lese belegte OpenVPN-Ports via netstat ..."
    while read -r line; do
        # Beispiel Spalte: 0.0.0.0:1194 oder [::]:1194
        addr_field=$(echo "$line" | awk '{print $4}')
        port_candidate="${addr_field##*:}"
        [[ "$port_candidate" =~ ^[0-9]+$ ]] || continue
        (( port_candidate > max_port )) && max_port=$port_candidate
    done < <(netstat -tupan 2>/dev/null | grep openvpn || true)
fi

# Fallback: Ports aus .conf-Dateien lesen, falls netstat nichts fand
if (( max_port == 0 )); then
    echo "Keine Ports über netstat gefunden, lese Ports aus *.conf ..."
    shopt -s nullglob
    for f in "${OPENVPN_DIR}"/*.conf; do
        p=$(grep -E '^[[:space:]]*port[[:space:]]+[0-9]+' "$f" | awk '{print $2}' | head -n1 || true)
        [[ "$p" =~ ^[0-9]+$ ]] || continue
        (( p > max_port )) && max_port=$p
    done
    shopt -u nullglob
fi

if (( max_port == 0 )); then
    echo "Es wurde kein existierender Port gefunden. Starte bei 1194."
    max_port=1193
else
    echo "Höchster gefundener Port: ${GREEN}${max_port}${NC}"
fi

NEW_PORT=$(( max_port + 1 ))
echo "Nächster Port wird: ${GREEN}${NEW_PORT}${NC}"
echo

# ---------------------------------------------------------
# 3) Vorlage-Konfig zu diesem Port finden
# ---------------------------------------------------------
template_conf=$(grep -l "^[[:space:]]*port[[:space:]]${max_port}\b" "${OPENVPN_DIR}"/*.conf 2>/dev/null | head -n1 || true)

if [[ -z "$template_conf" ]]; then
    echo "${RED}Fehler:${NC} Keine Vorlage-Konfiguration mit port ${max_port} gefunden."
    exit 1
fi

echo "Verwende Vorlage-Konfiguration:"
echo "  ${YELLOW}${template_conf}${NC}"
echo

# ---------------------------------------------------------
# 4) ifconfig aus Vorlage lesen und nächstes /30-Netz berechnen
# ---------------------------------------------------------
ifconfig_line=$(grep -E '^[[:space:]]*ifconfig[[:space:]]+' "$template_conf" | head -n1 || true)
if [[ -z "$ifconfig_line" ]]; then
    echo "${RED}Fehler:${NC} Keine ifconfig-Zeile in Vorlage gefunden."
    exit 1
fi

old_ip1=$(echo "$ifconfig_line" | awk '{print $2}')  # Router-IP alt
old_ip2=$(echo "$ifconfig_line" | awk '{print $3}')  # Road-Warrior-IP alt

echo "Alte ifconfig-Zeile: $ifconfig_line"
echo "  Router alt:      $old_ip1"
echo "  Road-Warrior alt:$old_ip2"
echo

# Netz aus old_ip1 ableiten (z.B. 192.168.200.X) und nächstes /30-Netz berechnen
prefix="${old_ip1%.*}"        # 192.168.200
last_octet="${old_ip1##*.}"   # z.B. 33

# /30-Blöcke = 0,4,8,...; Router = +1, Client = +2, Broadcast = +3
current_block=$(( last_octet / 4 ))
next_block=$(( current_block + 1 ))
net_octet=$(( next_block * 4 ))   # Netzadresse
router_octet=$(( net_octet + 1 ))
client_octet=$(( net_octet + 2 ))

NEW_NET="${prefix}.${net_octet}"
NEW_ROUTER_IP="${prefix}.${router_octet}"
NEW_CLIENT_IP="${prefix}.${client_octet}"

echo "Neues /30-Netz:"
echo "  Netz:      ${GREEN}${NEW_NET}${NC}"
echo "  Router:    ${GREEN}${NEW_ROUTER_IP}${NC}"
echo "  Road-War.: ${GREEN}${NEW_CLIENT_IP}${NC}"
echo

NEW_CONF="${OPENVPN_DIR}/${NEW_NAME}.conf"
NEW_KEY="${OPENVPN_DIR}/${NEW_NAME}.key"

# ---------------------------------------------------------
# 5) Neue Konfigurationsdatei erstellen / simulieren
# ---------------------------------------------------------
if (( DRY_RUN )); then
    echo "${YELLOW}[DRY-RUN] Würde neue Konfigurationsdatei erstellen:${NC}"
    echo "  ${NEW_CONF}"
    echo "${YELLOW}[DRY-RUN] Würde in dieser Datei setzen:${NC}"
    echo "  port ${NEW_PORT}"
    echo "  ifconfig ${NEW_ROUTER_IP} ${NEW_CLIENT_IP}"
    echo "  secret /etc/openvpn/${NEW_NAME}.key"
    echo
else
    echo "Erstelle neue Konfiguration:"
    echo "  ${NEW_CONF}"
    cp "$template_conf" "$NEW_CONF"

    # Port ersetzen
    sed -i "s/^[[:space:]]*port[[:space:]]\+[0-9]\+/port ${NEW_PORT}/" "$NEW_CONF"

    # ifconfig-Zeile ersetzen
    sed -i "s/^[[:space:]]*ifconfig[[:space:]]\+${old_ip1}[[:space:]]\+${old_ip2}/ifconfig ${NEW_ROUTER_IP} ${NEW_CLIENT_IP}/" "$NEW_CONF"

    # secret-Zeile auf neuen Key setzen
    sed -i "s#^\([[:space:]]*secret[[:space:]]\+\).*#\1/etc/openvpn/${NEW_NAME}.key#" "$NEW_CONF"

    echo "${GREEN}Neue Konfigurationsdatei erstellt und angepasst.${NC}"
    echo
fi

# ---------------------------------------------------------
# 6) Neuen Key erzeugen / simulieren
# ---------------------------------------------------------
if (( DRY_RUN )); then
    echo "${YELLOW}[DRY-RUN] Würde neuen Key erzeugen:${NC}"
    echo "  openvpn --genkey secret ${NEW_KEY}"
    echo
else
    echo "Erzeuge neuen Key:"
    echo "  ${NEW_KEY}"
    openvpn --genkey secret "$NEW_KEY"
    echo "${GREEN}Key erzeugt.${NC}"
    echo
fi

# ---------------------------------------------------------
# 7) .conf und .key nach /home/pchfw kopieren & chown / simulieren
# ---------------------------------------------------------
if (( DRY_RUN )); then
    echo "${YELLOW}[DRY-RUN] Würde Dateien nach ${CLIENT_DIR} kopieren und Owner setzen:${NC}"
    echo "  cp ${NEW_CONF} ${CLIENT_DIR}/"
    echo "  cp ${NEW_KEY}  ${CLIENT_DIR}/"
    echo "  chown pchfw ${CLIENT_DIR}/${NEW_NAME}.conf"
    echo "  chown pchfw ${CLIENT_DIR}/${NEW_NAME}.key"
    echo
else
    mkdir -p "$CLIENT_DIR"

    cp "$NEW_CONF" "$CLIENT_DIR/"
    cp "$NEW_KEY" "$CLIENT_DIR/"

    chown pchfw "${CLIENT_DIR}/${NEW_NAME}.conf"
    chown pchfw "${CLIENT_DIR}/${NEW_NAME}.key"

    echo "Kopiert nach ${CLIENT_DIR} und Owner auf pchfw gesetzt:"
    echo "  ${CLIENT_DIR}/${NEW_NAME}.conf"
    echo "  ${CLIENT_DIR}/${NEW_NAME}.key"
    echo
fi

# ---------------------------------------------------------
# 8) Tunnel starten / enable? (nur wenn NICHT Dry-Run)
# ---------------------------------------------------------
SERVICE_NAME="openvpn@${NEW_NAME}"

if (( DRY_RUN )); then
    echo "${YELLOW}[DRY-RUN] Würde jetzt folgendes anbieten:${NC}"
    echo "  systemctl start ${SERVICE_NAME}"
    echo "  systemctl enable ${SERVICE_NAME}"
    echo
    echo "${GREEN}DRY-RUN abgeschlossen. Es wurden keine Änderungen vorgenommen.${NC}"
else
    read -rp "Tunnel jetzt starten? (j/n): " answer_start
    if [[ "$answer_start" =~ ^[JjYy]$ ]]; then
        echo "Starte ${SERVICE_NAME} ..."
        if systemctl start "$SERVICE_NAME"; then
            echo "${GREEN}Tunnel gestartet.${NC}"
        else
            echo "${RED}Fehler beim Start des Tunnels.${NC}"
        fi
    else
        echo "Tunnel wurde nicht gestartet."
    fi

    read -rp "Tunnel für Autostart (systemctl enable) registrieren? (j/n): " answer_enable
    if [[ "$answer_enable" =~ ^[JjYy]$ ]]; then
        echo "Aktiviere Autostart für ${SERVICE_NAME} ..."
        if systemctl enable "$SERVICE_NAME"; then
            echo "${GREEN}Tunnel für Autostart registriert.${NC}"
        else
            echo "${RED}Fehler bei systemctl enable.${NC}"
        fi
    else
        echo "Tunnel wurde nicht für Autostart registriert."
    fi

    echo
    echo "Fertig. Neue Road-Warrior-Konfiguration:"
    echo "  Name:        ${GREEN}${NEW_NAME}${NC}"
    echo "  Port:        ${GREEN}${NEW_PORT}${NC}"
    echo "  Router-IP:   ${GREEN}${NEW_ROUTER_IP}${NC}"
    echo "  Road-War-IP: ${GREEN}${NEW_CLIENT_IP}${NC}"
    echo
    echo "Konfig & Key liegen unter:"
    echo "  ${OPENVPN_DIR}/${NEW_NAME}.conf"
    echo "  ${OPENVPN_DIR}/${NEW_NAME}.key"
    echo "Kopie für pchfw:"
    echo "  ${CLIENT_DIR}/${NEW_NAME}.conf"
    echo "  ${CLIENT_DIR}/${NEW_NAME}.key"
    echo
    echo
    echo "${RED}tun-device und Port unter /etc/sysconfig/SuSEfirewall2 freigeben nicht vergessen!.${NC}"
fi
