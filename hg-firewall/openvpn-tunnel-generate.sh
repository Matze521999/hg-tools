#!/bin/bash
# Erstellt auf Basis der vorhandenen OpenVPN-Konfigurationen
# den nÃ¤chsten Road-Warrior-Tunnel:
# - ermittelt hÃ¶chsten belegten Port (netstat, fallback: .conf)
# - nimmt die Konfig mit diesem Port als Vorlage
# - berechnet das nÃ¤chste /30-Netz in 192.168.200.x
# - erstellt neue .conf + .key
# - kopiert .conf/.key nach /home/pchfw und setzt chown pchfw
# - optional: systemctl start/enable openvpn@NAME
# - optional: Client-OVPN (.ovpn) unter /home/pchfw erzeugen
#
# Optionaler Dry-Run:
#   openvpn-create-next-roadwarrior.sh --dry-run [NAME]
#   openvpn-create-next-roadwarrior.sh -n [NAME]

set -euo pipefail

OPENVPN_DIR="/etc/openvpn"
CLIENT_DIR="/home/pchfw"
STD_FILE="/etc/pch-router-vpnstandardwerte"

# Farben
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
RED=$'\e[31m'
NC=$'\e[0m'

DRY_RUN=0
FIRST_TUNNEL=0

###############################################################################
# Funktion: Client-OVPN fuer bestehendes Konfig-Paar erzeugen
###############################################################################
generate_client_ovpn() {
    local NAME="$1"

    echo
    echo "=== Client-OVPN-Generator fuer '${NAME}' ==="

    local conf_file="${OPENVPN_DIR}/${NAME}.conf"
    local key_file="${OPENVPN_DIR}/${NAME}.key"
    local ovpn_file="${CLIENT_DIR}/${NAME}.ovpn"

#    if [[ ! -f "$conf_file" ]]; then
#        echo "Konfigurationsdatei nicht gefunden: $conf_file"
#        return 1
#    fi
#
#    if [[ ! -f "$key_file" ]]; then
#        echo "Key-Datei nicht gefunden: $key_file"
#        return 1
#    fi

    if [[ ! -f "$conf_file" ]]; then
    if (( DRY_RUN )); then
        echo "${YELLOW}[DRY-RUN] Konfigurationsdatei existiert (noch) nicht: ${conf_file}${NC}"
        echo "${YELLOW}[DRY-RUN] Wuerde Client-OVPN auf Basis der neu angelegten Server-Konfiguration erzeugen.${NC}"
        return 0
    fi
    echo "Konfigurationsdatei nicht gefunden: $conf_file"
    return 1
fi

if [[ ! -f "$key_file" ]]; then
    if (( DRY_RUN )); then
        echo "${YELLOW}[DRY-RUN] Key-Datei existiert (noch) nicht: ${key_file}${NC}"
        echo "${YELLOW}[DRY-RUN] Wuerde Client-OVPN mit diesem Key referenzieren.${NC}"
        return 0
    fi
    echo "Key-Datei nicht gefunden: $key_file"
    return 1
fi



    mkdir -p "$CLIENT_DIR"

    echo
    echo "Lese vorhandene Werte aus: $conf_file"
    echo

    # Port aus .conf lesen
    local port_conf
    port_conf="$(grep -E '^[[:space:]]*port[[:space:]]+' "$conf_file" | awk '{print $2}' | head -n1 || true)"

    # ifconfig aus .conf lesen (Server-Seite)
    local ifconfig_line
    ifconfig_line="$(grep -E '^[[:space:]]*ifconfig[[:space:]]+' "$conf_file" | head -n1 || true)"
    local conf_ip1 conf_ip2
    conf_ip1="$(echo "$ifconfig_line" | awk '{print $2}')"  # A (Server-IP)
    conf_ip2="$(echo "$ifconfig_line" | awk '{print $3}')"  # B (Client-IP)

    # route aus .conf lesen (falls vorhanden)
    local route_line
    route_line="$(grep -E '^[[:space:]]*route[[:space:]]+' "$conf_file" | head -n1 || true)"
    local route_net_conf route_mask_conf route_gw_conf
    route_net_conf="$(echo "$route_line" | awk '{print $2}')"
    route_mask_conf="$(echo "$route_line" | awk '{print $3}')"
    route_gw_conf="$(echo "$route_line" | awk '{print $4}')"

    # dhcp-option DNS/DOMAIN
    local dns_conf domain_conf
    dns_conf="$(grep -E '^[[:space:]]*dhcp-option[[:space:]]+DNS[[:space:]]+' "$conf_file" | awk '{print $3}' | head -n1 || true)"
    domain_conf="$(grep -E '^[[:space:]]*dhcp-option[[:space:]]+DOMAIN[[:space:]]+' "$conf_file" | awk '{print $3}' | head -n1 || true)"

    ########################################
    # 1) Basis-Defaults aus .conf ableiten
    ########################################

    # Nicht persistierte Werte:
    local default_client_ip default_peer_ip default_port default_route_gw
    default_client_ip="${conf_ip2:-192.168.200.2}"   # Client = zweite IP aus conf
    default_peer_ip="${conf_ip1:-192.168.200.1}"     # Peer   = erste IP aus conf
    default_port="${port_conf:-1194}"
    default_route_gw="${route_gw_conf:-$default_peer_ip}"

    # Persistierte Standardwerte:
    local default_remote_host=""
    local default_route_net="${route_net_conf:-172.16.1.0}"
    local default_route_mask="${route_mask_conf:-255.255.255.0}"
    local default_dns_server=""
    local default_dns_domain="${domain_conf:-example.local}"

    ########################################
    # 2) Standardwerte-Datei einlesen (falls vorhanden)
    ########################################

    local loaded_from_stdfile_remote=""
    local loaded_from_stdfile_routenet=""
    local loaded_from_stdfile_routemask=""
    local loaded_from_stdfile_dns=""
    local loaded_from_stdfile_domain=""

    if [[ -f "$STD_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$STD_FILE"

        [[ -n "$default_remote_host" ]] && loaded_from_stdfile_remote=1
        [[ -n "$default_route_net"   ]] && loaded_from_stdfile_routenet=1
        [[ -n "$default_route_mask"  ]] && loaded_from_stdfile_routemask=1
        [[ -n "$default_dns_server"  ]] && loaded_from_stdfile_dns=1
        [[ -n "$default_dns_domain"  ]] && loaded_from_stdfile_domain=1
    fi

    # Falls aus STD_FILE nichts kam, sinnvolle Fallbacks ergÃ¤nzen
    [[ -z "$default_dns_server" ]] && default_dns_server="${dns_conf:-$default_route_gw}"

    ########################################
    # 3) Interaktive Abfragen
    ########################################

    local remote_host client_ip peer_ip port route_net route_mask route_gw dns_server dns_domain

    # REMOTE HOST
    if [[ -n "$default_remote_host" ]]; then
        local prompt_remote
        if [[ -n "$loaded_from_stdfile_remote" ]]; then
            prompt_remote="${YELLOW}${default_remote_host}${NC}"
        else
            prompt_remote="${default_remote_host}"
        fi
        read -rp "Remote Host (z.B. irgendwas.dyndns.org) [${prompt_remote}]: " remote_host_input
        remote_host="${remote_host_input:-$default_remote_host}"
    else
        read -rp "Remote Host (z.B. irgendwas.dyndns.org): " remote_host
    fi

    echo
    echo "Virtuelle IP-Adressen (ifconfig):"
    # IPs werden NICHT persistiert â†’ immer normale Anzeige
    read -rp "Client-IP [${default_client_ip}]: " client_ip_input
    client_ip="${client_ip_input:-$default_client_ip}"

    read -rp "Peer-IP (Gegenstelle) [${default_peer_ip}]: " peer_ip_input
    peer_ip="${peer_ip_input:-$default_peer_ip}"

    # Port (nicht persistiert)
    echo
    read -rp "Port [${default_port}]: " port_input
    port="${port_input:-$default_port}"

    # Routing-Netz
    echo
    echo "Routing-Einstellungen:"

    # Route-Netz
    local prompt_routenet
    if [[ -n "$loaded_from_stdfile_routenet" ]]; then
        prompt_routenet="${YELLOW}${default_route_net}${NC}"
    else
        prompt_routenet="${default_route_net}"
    fi
    read -rp "Zielnetz (route) [${prompt_routenet}]: " route_net_input
    route_net="${route_net_input:-$default_route_net}"

    # Route-Maske
    local prompt_routemask
    if [[ -n "$loaded_from_stdfile_routemask" ]]; then
        prompt_routemask="${YELLOW}${default_route_mask}${NC}"
    else
        prompt_routemask="${default_route_mask}"
    fi
    read -rp "Netzmaske [${prompt_routemask}]: " route_mask_input
    route_mask="${route_mask_input:-$default_route_mask}"

    # Gateway (NICHT persistiert)
    default_route_gw="${default_route_gw:-$peer_ip}"
    read -rp "Gateway (Tunnel-GW) [${default_route_gw}]: " route_gw_input
    route_gw="${route_gw_input:-$default_route_gw}"

    # DHCP Optionen
    echo
    echo "DHCP-Optionen:"

    # DNS-Server
    local prompt_dns
    if [[ -n "$loaded_from_stdfile_dns" ]]; then
        prompt_dns="${YELLOW}${default_dns_server}${NC}"
    else
        prompt_dns="${default_dns_server}"
    fi
    read -rp "DNS-Server [${prompt_dns}]: " dns_server_input
    dns_server="${dns_server_input:-$default_dns_server}"

    # DNS-Domain
    local prompt_domain
    if [[ -n "$loaded_from_stdfile_domain" ]]; then
        prompt_domain="${YELLOW}${default_dns_domain}${NC}"
    else
        prompt_domain="${default_dns_domain}"
    fi
    read -rp "DNS-Domain [${prompt_domain}]: " dns_domain_input
    dns_domain="${dns_domain_input:-$default_dns_domain}"

    ########################################
    # 4) .ovpn-Datei schreiben
    ########################################

    echo
    if (( DRY_RUN )); then
        echo "${YELLOW}[DRY-RUN] Wuerde Client-OVPN erzeugen:${NC}"
        echo "  ${ovpn_file}"
        echo "${YELLOW}[DRY-RUN] Inhalt (verkuerzt):${NC}"
        echo "  remote ${remote_host}"
        echo "  ifconfig ${client_ip} ${peer_ip}"
        echo "  port ${port}"
        echo "  route ${route_net} ${route_mask} ${route_gw}"
    else
        echo "Erzeuge Client-Konfiguration: $ovpn_file"
        echo

        cat > "$ovpn_file" <<EOF
##################################################################
# c:\\programm files\\openvpn\\config
# Open VPN Konfiguration Roadwarrior
######################################

# Remote Host
remote ${remote_host}

# Schnittstelle
dev tun

# Virtuelle Interfaces
ifconfig ${client_ip} ${peer_ip}

# Schluesseldatei
secret ${NAME}.key

# Keep Alive
ping 20
ping-restart 45
ping-timer-rem
persist-tun
persist-key
resolv-retry infinite

# Log
verb 1

# Port
port ${port}

# Routing
route-method exe
route-delay 2
route ${route_net} ${route_mask} ${route_gw}

# DHCP Optionen
dhcp-option DNS ${dns_server}
dhcp-option DOMAIN ${dns_domain}

# MTU Einstellungen
tun-mtu 1500
tun-mtu-extra 32

# Kein Passwort Caching
auth-nocache

# AES-256-CBC Krypto
cipher AES-256-CBC
EOF
    fi

    ########################################
    # 5) .conf/.key kopieren und Rechte setzen
    ########################################

    echo
    if (( DRY_RUN )); then
        echo "${YELLOW}[DRY-RUN] Wuerde Key- und Config-Datei ins Client-Verzeichnis kopieren und chown setzen:${NC}"
        echo "  cp -n ${key_file} ${CLIENT_DIR}/"
        echo "  cp -n ${conf_file} ${CLIENT_DIR}/"
        echo "  chown pchfw ${CLIENT_DIR}/${NAME}.ovpn"
        echo "  chown pchfw ${CLIENT_DIR}/${NAME}.key"
        echo "  chown pchfw ${CLIENT_DIR}/${NAME}.conf"
    else
        echo "Kopiere Key- und Config-Datei in das Client-Verzeichnis ..."
        cp -n "$key_file" "$CLIENT_DIR/" && echo "Key-Datei nach ${CLIENT_DIR}/$(basename "$key_file") kopiert."
        cp -n "$conf_file" "$CLIENT_DIR/" && echo "Config-Datei nach ${CLIENT_DIR}/$(basename "$conf_file") kopiert."

        echo
        echo "Setze Besitzrechte auf pchfw ..."
        chown pchfw "${CLIENT_DIR}/${NAME}.ovpn"
        chown pchfw "${CLIENT_DIR}/${NAME}.key"
        chown pchfw "${CLIENT_DIR}/${NAME}.conf"
        echo "Besitzrechte gesetzt."
    fi

    ########################################
    # 6) Standardwerte-Datei aktualisieren (nur 5 Felder)
    ########################################
    echo
    if (( DRY_RUN )); then
        echo "${YELLOW}[DRY-RUN] Wuerde Standardwerte-Datei ${STD_FILE} wie folgt aktualisieren:${NC}"
        cat <<EOF
default_remote_host="${remote_host}"
default_route_net="${route_net}"
default_route_mask="${route_mask}"
default_dns_server="${dns_server}"
default_dns_domain="${dns_domain}"
EOF
    else
        echo "Aktualisiere Standardwerte in ${STD_FILE} ..."

        cat > "$STD_FILE" <<EOF
default_remote_host="${remote_host}"
default_route_net="${route_net}"
default_route_mask="${route_mask}"
default_dns_server="${dns_server}"
default_dns_domain="${dns_domain}"
EOF

        echo "Standardwerte aktualisiert."

        echo
        echo "Fertig. Alle Dateien unter ${CLIENT_DIR}/"
        echo " - ${NAME}.ovpn"
        echo " - ${NAME}.conf"
        echo " - ${NAME}.key"
        echo
        echo "Standardwerte fuer zukuenftige Runs: ${STD_FILE}"
    fi
}

###############################################################################
# HAUPTSKRIPT: Server-Konfig + Key + optionaler Client-OVPN
###############################################################################

# ---------------------------------------------------------
# 0) Parameter auswerten (Dry-Run / Name)
# ---------------------------------------------------------
if [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]]; then
    DRY_RUN=1
    shift
    echo "${YELLOW}*** DRY-RUN: Es werden KEINE Ã„nderungen vorgenommen. ***${NC}"
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
# 2) Hoechsten Port via netstat ermitteln
# ---------------------------------------------------------
max_port=0

if command -v netstat >/dev/null 2>&1; then
    echo "Lese belegte OpenVPN-Ports via netstat ..."
    while read -r line; do
        addr_field=$(echo "$line" | awk '{print $4}')
        port_candidate="${addr_field##*:}"
        [[ "$port_candidate" =~ ^[0-9]+$ ]] || continue
        (( port_candidate > max_port )) && max_port=$port_candidate
    done < <(netstat -tupan 2>/dev/null | grep openvpn || true)
fi

# Fallback: Ports aus .conf-Dateien lesen, falls netstat nichts fand
if (( max_port == 0 )); then
    echo "Keine Ports ueber netstat gefunden, lese Ports aus *.conf ..."
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
    echo "HÃ¶chster gefundener Port: ${GREEN}${max_port}${NC}"
fi

NEW_PORT=$(( max_port + 1 ))
echo "NÃ¤chster Port wird: ${GREEN}${NEW_PORT}${NC}"
echo

NEW_CONF="${OPENVPN_DIR}/${NEW_NAME}.conf"
NEW_KEY="${OPENVPN_DIR}/${NEW_NAME}.key"

# ---------------------------------------------------------
# 3) Vorlage-Konfig zu diesem Port finden
# ---------------------------------------------------------
template_conf=$(grep -l "^[[:space:]]*port[[:space:]]${max_port}\b" "${OPENVPN_DIR}"/*.conf 2>/dev/null | head -n1 || true)

if [[ -z "$template_conf" ]]; then
    echo "${YELLOW}Es wurde keine Vorlage-Konfiguration gefunden.${NC}"
    echo "${YELLOW}Erstelle ersten Road-Warrior-Tunnel mit Basiswerten.${NC}"
    FIRST_TUNNEL=1
else
    echo "Verwende Vorlage-Konfiguration:"
    echo "  ${YELLOW}${template_conf}${NC}"
    echo
fi

# ---------------------------------------------------------
# 4) ifconfig/Netz bestimmen
# ---------------------------------------------------------
if (( FIRST_TUNNEL )); then
    prefix="192.168.200"
    NEW_NET="${prefix}.0"
    NEW_ROUTER_IP="${prefix}.1"
    NEW_CLIENT_IP="${prefix}.2"

    echo "Erster Tunnel â€“ verwende Standardnetz:"
    echo "  Netz:      ${GREEN}${NEW_NET}${NC}"
    echo "  Router:    ${GREEN}${NEW_ROUTER_IP}${NC}"
    echo "  Road-War.: ${GREEN}${NEW_CLIENT_IP}${NC}"
    echo
else
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

    prefix="${old_ip1%.*}"        # 192.168.200
    last_octet="${old_ip1##*.}"   # z.B. 33

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
fi

# ---------------------------------------------------------
# 5) Neue Konfigurationsdatei erstellen / simulieren
# ---------------------------------------------------------
if (( DRY_RUN )); then
    echo "${YELLOW}[DRY-RUN] Wuerde neue Konfigurationsdatei erstellen:${NC}"
    echo "  ${NEW_CONF}"
    echo "${YELLOW}[DRY-RUN] Wuerde in dieser Datei setzen:${NC}"
    echo "  port ${NEW_PORT}"
    echo "  ifconfig ${NEW_ROUTER_IP} ${NEW_CLIENT_IP}"
    echo "  secret /etc/openvpn/${NEW_NAME}.key"
    echo
else
    echo "Erstelle neue Konfiguration:"
    echo "  ${NEW_CONF}"

    if (( FIRST_TUNNEL )); then
        cat > "$NEW_CONF" <<EOF
##################################################################
# /etc/openvpn/                                                  #
# Open VPN Konfiguration PCH-Roadwarrior (PCH Router)            #
##################################################################

# Schnittstelle
dev tun

# Virtuelle Interfaces
ifconfig ${NEW_ROUTER_IP} ${NEW_CLIENT_IP}

# Schluesseldatei
secret /etc/openvpn/${NEW_NAME}.key

# Keep Alive
ping 20
ping-restart 45
ping-timer-rem
persist-tun
persist-key
resolv-retry infinite

# Log
verb 3

# Port
port ${NEW_PORT}

# MTU
tun-mtu 1500
tun-mtu-extra 32

# AES-256-CBC Krypto
cipher AES-256-CBC
EOF
    else
        cp "$template_conf" "$NEW_CONF"

        sed -i "s/^[[:space:]]*port[[:space:]]\+[0-9]\+/port ${NEW_PORT}/" "$NEW_CONF"
        sed -i "s/^[[:space:]]*ifconfig[[:space:]]\+${old_ip1}[[:space:]]\+${old_ip2}/ifconfig ${NEW_ROUTER_IP} ${NEW_CLIENT_IP}/" "$NEW_CONF"
        sed -i "s#^\([[:space:]]*secret[[:space:]]\+\).*#\1/etc/openvpn/${NEW_NAME}.key#" "$NEW_CONF"
    fi

    echo "${GREEN}Neue Konfigurationsdatei erstellt und angepasst.${NC}"
    echo
fi

# ---------------------------------------------------------
# 6) Neuen Key erzeugen / simulieren
# ---------------------------------------------------------
if (( DRY_RUN )); then
    echo "${YELLOW}[DRY-RUN] Wuerde neuen Key erzeugen:${NC}"
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
    echo "${YELLOW}[DRY-RUN] Wuerde Dateien nach ${CLIENT_DIR} kopieren und Owner setzen:${NC}"
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
# 8) Tunnel starten / enable? + Client-OVPN (nur wenn NICHT Dry-Run)
# ---------------------------------------------------------
SERVICE_NAME="openvpn@${NEW_NAME}"

if (( DRY_RUN )); then
    echo "${YELLOW}[DRY-RUN] Wuerde jetzt folgendes anbieten:${NC}"
    echo "  systemctl start ${SERVICE_NAME}"
    echo "  systemctl enable ${SERVICE_NAME}"
    echo
    echo "${YELLOW}[DRY-RUN] Wuerde zusÃ¤tzlich Client-OVPN fuer '${NEW_NAME}' erzeugen:${NC}"
    generate_client_ovpn "${NEW_NAME}"
    echo
    echo "${GREEN}DRY-RUN abgeschlossen. Es wurden keine Ã„nderungen vorgenommen.${NC}"
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

    read -rp "Tunnel fuer Autostart (systemctl enable) registrieren? (j/n): " answer_enable
    if [[ "$answer_enable" =~ ^[JjYy]$ ]]; then
        echo "Aktiviere Autostart fuer ${SERVICE_NAME} ..."
        if systemctl enable "$SERVICE_NAME"; then
            echo "${GREEN}Tunnel fuer Autostart registriert.${NC}"
        else
            echo "${RED}Fehler bei systemctl enable.${NC}"
        fi
    else
        echo "Tunnel wurde nicht fuer Autostart registriert."
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
    echo "Kopie fuer pchfw:"
    echo "  ${CLIENT_DIR}/${NEW_NAME}.conf"
    echo "  ${CLIENT_DIR}/${NEW_NAME}.key"
    echo
    echo "${RED}tun-device und Port unter /etc/sysconfig/SuSEfirewall2 freigeben nicht vergessen!.${NC}"
    echo

    # Abfrage, ob OVPN generitert werden soll
    read -rp "Client-OVPN-Konfiguration fuer diesen Tunnel erzeugen? (j/n): " answer_ovpn
    if [[ "$answer_ovpn" =~ ^[JjYy]$ ]]; then
        generate_client_ovpn "${NEW_NAME}"
    else
        echo "Keine Client-Konfiguration erzeugt."
    fi
fi
