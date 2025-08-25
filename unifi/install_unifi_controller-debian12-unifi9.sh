#!/bin/bash
set -e

echo "=== PCHelp Standard Tools installieren ==="
apt-get update
apt-get install -y vim net-tools dnsutils open-vm-tools nmap iftop iptraf apt-transport-https ntp gnupg ca-certificates curl

echo "=== VIM Konfiguration anpassen ==="
cat > /etc/vim/vimrc.local <<'EOF'
source $VIMRUNTIME/defaults.vim
let skip_defaults_vim = 1
if has('mouse')
 set mouse=r
endif
EOF

echo "=== Profilanpassungen für Benutzer root und pchfw ==="
for user in root pchfw; do
    if [ -f /home/$user/.bashrc ] || [ "$user" = "root" ]; then
        target="/root/.bashrc"
        [ "$user" != "root" ] && target="/home/$user/.bashrc"
        cat >> "$target" <<'EOF'

# PCHelp Komfort-Anpassungen
alias su='su -l'
alias ll='ls $LS_OPTIONS -alh'
EOF
    fi
done

echo "=== MongoDB 4.4 Quelle hinzufügen ==="
echo "deb [ arch=amd64,arm64 ] http://repo.mongodb.org/apt/debian bullseye/mongodb-org/4.4 main" | tee /etc/apt/sources.list.d/mongodb-org-4.4.list
curl -fsSL https://pgp.mongodb.com/server-4.4.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/mongodb-org-4.4.gpg

echo "=== libssl1.1 installieren ==="
cd /tmp
wget http://ftp.us.debian.org/debian/pool/main/o/openssl/libssl1.1_1.1.1w-0+deb11u1_amd64.deb
dpkg -i libssl1.1_1.1.1w-0+deb11u1_amd64.deb

echo "=== Unifi Repository einbinden ==="
echo 'deb https://www.ui.com/downloads/unifi/debian stable ubiquiti' | tee /etc/apt/sources.list.d/100-ubnt-unifi.list
wget -O /etc/apt/trusted.gpg.d/unifi-repo.gpg https://dl.ui.com/unifi/unifirepo.gpg

echo "=== Unifi 9 Installation starten ==="
apt-get update
apt-get install -y unifi

echo "=== Installation abgeschlossen! ==="
systemctl status unifi --no-pager
