#!/bin/bash

##########################################################################################################
# Dieses Script generiert *.ovpn-Files für Clients zu einem vorhandenen VPN-Konfigpaar (*.conf + *.key). #
##########################################################################################################

# Basisverzeichnisse
SERVER_DIR="/etc/openvpn"
CLIENT_DIR="/home/pchfw"
STD_FILE="/etc/pch-router-vpnstandardwerte"

# Optionaler Parameter: Name der Verbindung
NAME="$1"

if [[ -z "$NAME" ]]; then
    read -rp "Name der Verbindung (Basename von .conf/.key): " NAME
fi

if [[ -z "$NAME" ]]; then
    echo "Kein Name angegeben. Abbruch."
    exit 1
fi

conf_file="${SERVER_DIR}/${NAME}.conf"
key_file="${SERVER_DIR}/${NAME}.key"
ovpn_file="${CLIENT_DIR}/${NAME}.ovpn"

if [[ ! -f "$conf_file" ]]; then
    echo "Konfigurationsdatei nicht gefunden: $conf_file"
    exit 1
fi

if [[ ! -f "$key_file" ]]; then
    echo "Key-Datei nicht gefunden: $key_file"
    exit 1
fi

mkdir -p "$CLIENT_DIR"

echo
echo "Lese vorhandene Werte aus: $conf_file"
echo

# Port aus .conf lesen
port_conf="$(grep -E '^[[:space:]]*port[[:space:]]+' "$conf_file" | awk '{print $2}' | head -n1)"

# ifconfig aus .conf lesen (Server-Seite)
ifconfig_line="$(grep -E '^[[:space:]]*ifconfig[[:space:]]+' "$conf_file" | head -n1)"
conf_ip1="$(echo "$ifconfig_line" | awk '{print $2}')"  # A (Server-IP)
conf_ip2="$(echo "$ifconfig_line" | awk '{print $3}')"  # B (Client-IP)

# route aus .conf lesen (falls vorhanden)
route_line="$(grep -E '^[[:space:]]*route[[:space:]]+' "$conf_file" | head -n1)"
route_net_conf="$(echo "$route_line" | awk '{print $2}')"
route_mask_conf="$(echo "$route_line" | awk '{print $3}')"
route_gw_conf="$(echo "$route_line" | awk '{print $4}')"

# dhcp-option DNS/DOMAIN
dns_conf="$(grep -E '^[[:space:]]*dhcp-option[[:space:]]+DNS[[:space:]]+' "$conf_file" | awk '{print $3}' | head -n1)"
domain_conf="$(grep -E '^[[:space:]]*dhcp-option[[:space:]]+DOMAIN[[:space:]]+' "$conf_file" | awk '{print $3}' | head -n1)"

########################################
# 1) Basis-Defaults aus .conf ableiten
########################################

# Dinge, die NICHT persistiert werden:
default_client_ip="${conf_ip2:-192.168.200.2}"           # Client = zweite IP aus conf
default_peer_ip="${conf_ip1:-192.168.200.1}"             # Peer   = erste IP aus conf
default_port="${port_conf:-1194}"
default_route_gw="${route_gw_conf:-$default_peer_ip}"

# Dinge, die als Standardwerte-Datei verwaltet werden:
default_remote_host=""
default_route_net="${route_net_conf:-172.16.1.0}"
default_route_mask="${route_mask_conf:-255.255.255.0}"
default_dns_server=""   # wird unten noch gefüllt, falls leer
default_dns_domain="${domain_conf:-example.local}"

########################################
# 2) Standardwerte-Datei einlesen (falls vorhanden)
########################################

if [[ -f "$STD_FILE" ]]; then
    # Datei enthält NUR:
    # default_remote_host="..."
    # default_route_net="..."
    # default_route_mask="..."
    # default_dns_server="..."
    # default_dns_domain="..."
    # shellcheck source=/dev/null
    source "$STD_FILE"
fi

# Falls aus STD_FILE nichts kam, sinnvolle Fallbacks ergänzen
[[ -z "$default_dns_server" ]] && default_dns_server="${dns_conf:-$default_route_gw}"

########################################
# 3) Interaktive Abfragen mit farbigen STD_FILE-Defaults
########################################

# REMOTE HOST
if [[ -n "$default_remote_host" ]]; then
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
# IPs werden NICHT persistiert → immer normale Anzeige
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
if [[ -n "$loaded_from_stdfile_routenet" ]]; then
    prompt_routenet="${YELLOW}${default_route_net}${NC}"
else
    prompt_routenet="${default_route_net}"
fi
read -rp "Zielnetz (route) [${prompt_routenet}]: " route_net_input
route_net="${route_net_input:-$default_route_net}"

# Route-Maske
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
if [[ -n "$loaded_from_stdfile_dns" ]]; then
    prompt_dns="${YELLOW}${default_dns_server}${NC}"
else
    prompt_dns="${default_dns_server}"
fi
read -rp "DNS-Server [${prompt_dns}]: " dns_server_input
dns_server="${dns_server_input:-$default_dns_server}"

# DNS-Domain
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

########################################
# 5) .conf/.key kopieren und Rechte setzen
########################################

echo
echo "Kopiere Key- und Config-Datei in das Client-Verzeichnis ..."

cp -n "$key_file" "$CLIENT_DIR/" && echo "Key-Datei nach ${CLIENT_DIR}/$(basename "$key_file") kopiert."
cp -n "$conf_file" "$CLIENT_DIR/" && echo "Config-Datei nach ${CLIENT_DIR}/$(basename "$conf_file") kopiert."

echo
echo "Setze Besitzrechte auf pchfw ..."
chown pchfw "${CLIENT_DIR}/${NAME}.ovpn"
chown pchfw "${CLIENT_DIR}/${NAME}.key"
chown pchfw "${CLIENT_DIR}/${NAME}.conf"
echo "Besitzrechte gesetzt."

########################################
# 6) Standardwerte-Datei aktualisieren (nur 5 Felder)
########################################

echo
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
echo "Standardwerte für zukünftige Runs: ${STD_FILE}"
