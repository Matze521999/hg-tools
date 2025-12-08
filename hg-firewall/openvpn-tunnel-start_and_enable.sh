#!/bin/bash

##############################################################################################################################################
# Dieses Script sucht nach Tunnelpaaren (*.conf + *.key) überprüft deren Status (läuft + läuft als Service), und bietet ggf. einen Start an. #
##############################################################################################################################################

# Verzeichnis mit OpenVPN-Dateien
DIR="${1:-/etc/openvpn}"

# Farben für Konsole
RED="\e[31m"
GREEN="\e[32m"
NC="\e[0m"   # No Color

printf "%-20s %-10s %-15s %-12s\n" "NAME" "PAIR" "SERVICE" "ENABLED"
printf "%-20s %-10s %-15s %-12s\n" "--------------------" "----------" "---------------" "------------"

shopt -s nullglob

# Arrays
declare -a to_start
declare -a to_enable

##############################################
# 1. Alle CONF-Dateien prüfen
##############################################
for conf_file in "$DIR"/*.conf; do
    [ -e "$conf_file" ] || continue

    name="${conf_file##*/}"
    name="${name%.conf}"
    key_file="$DIR/${name}.key"

    if [[ -f "$key_file" ]]; then
        pair_status="conf+key"

        # Service-Status
        if systemctl is-active --quiet "openvpn@${name}"; then
            svc_status="running"
            svc_out="${GREEN}running${NC}"
        else
            svc_status="not-running"
            svc_out="${RED}not-running${NC}"
            to_start+=("$name")
        fi

        # Enable-Status
        if systemctl is-enabled "openvpn@${name}" &>/dev/null; then
            enabled_status="enabled"
            enabled_out="${GREEN}enabled${NC}"
        else
            enabled_status="not-enabled"
            enabled_out="${RED}not-enabled${NC}"
            to_enable+=("$name")
        fi
    else
        pair_status="no-key"
        svc_status="-"
        svc_out="-"
        enabled_status="-"
        enabled_out="-"
    fi

    # Konsole (farbig)
    printf "%-20s %-10s %-15b %-12b\n" "$name" "$pair_status" "$svc_out" "$enabled_out"

done

##############################################
# 2. KEY ohne CONF
##############################################
for key_file in "$DIR"/*.key; do
    name="${key_file##*/}"
    name="${name%.key}"

    conf_file="$DIR/${name}.conf"

    if [[ ! -f "$conf_file" ]]; then
        pair_status="no-conf"
        svc_status="-"
        enabled_status="-"

        printf "%-20s %-10s %-15s %-12s\n" "$name" "$pair_status" "-" "-" 
    fi
done

##############################################
# 3. Rückfrage: Tunnel starten
##############################################
echo
if [[ ${#to_start[@]} -eq 0 ]]; then
    echo -e "${GREEN}Alle vollständigen Tunnel laufen bereits.${NC}"
else
    echo "Folgende Tunnel sind vollständig (conf+key), aber laufen NICHT:"
    for name in "${to_start[@]}"; do
        echo -e " - ${RED}${name}${NC}"
    done

    echo
    read -rp "Sollen diese Tunnel jetzt gestartet werden? (j/n): " answer_start

    if [[ "$answer_start" =~ ^[JjYy]$ ]]; then
        echo
        echo "Starte Tunnel..."
        for name in "${to_start[@]}"; do
            echo " -> systemctl start openvpn@${name}"
            systemctl start "openvpn@${name}"
        done
        echo -e "${GREEN}Start-Vorgang abgeschlossen.${NC}"
    else
        echo "Keine Tunnel gestartet."
    fi
fi

##############################################
# 4. Rückfrage: Tunnel für Autostart registrieren (enable)
##############################################
echo
if [[ ${#to_enable[@]} -eq 0 ]]; then
    echo -e "${GREEN}Alle vollständigen Tunnel sind bereits für Autostart aktiviert (enabled).${NC}"
else
    echo "Folgende Tunnel sind vollständig (conf+key), aber NICHT per systemctl enable registriert:"
    for name in "${to_enable[@]}"; do
        echo -e " - ${RED}${name}${NC}"
    done

    echo
    read -rp "Sollen diese Tunnel jetzt für Autostart aktiviert werden (systemctl enable)? (j/n): " answer_enable

    if [[ "$answer_enable" =~ ^[JjYy]$ ]]; then
        echo
        echo "Aktiviere Autostart..."
        for name in "${to_enable[@]}"; do
            echo " -> systemctl enable openvpn@${name}"
            systemctl enable "openvpn@${name}"
        done
        echo -e "${GREEN}Enable-Vorgang abgeschlossen.${NC}"
    else
        echo "Keine Tunnel aktiviert."
    fi
fi

echo
echo "Fertig."
