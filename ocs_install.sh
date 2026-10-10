#!/bin/bash
# OCS Inventory NG Server 2.x paigalduse abiskript Ubuntu jaoks.
# Mõeldud õppe-VM-i jaoks.
#
# Skript:
#  - paigaldab Apache, MariaDB, PHP ja vajalikud Perl/PHP paketid;
#  - loob OCS-i jaoks eraldi andmebaasi ja kasutaja;
#  - laadib alla OCS Inventory Server 2.12.6;
#  - loob setup.answers faili;
#  - käivitab OCS-i ametliku setup.sh paigaldaja;
#  - lubab loodud Apache konfiguratsioonid ja kuvab OCS-i veebiaadressi.
#
# NB! OCS-i setup.sh jääb osaliselt interaktiivseks.
# Enamiku küsimuste puhul sobivad Ubuntu õppe-VM-is vaikimisi vastused.

set -euo pipefail

OCS_VERSION="2.12.6"
OCS_DB="ocsweb"
OCS_DB_USER="ocsuser"
DOWNLOAD_DIR="/usr/local/src"
OCS_ARCHIVE="OCSNG_UNIX_SERVER-${OCS_VERSION}.tar.gz"
OCS_URL="https://github.com/OCSInventory-NG/OCSInventory-ocsreports/releases/download/${OCS_VERSION}/${OCS_ARCHIVE}"
OCS_DIR="${DOWNLOAD_DIR}/OCSNG_UNIX_SERVER-${OCS_VERSION}"
INFO_FILE="/root/ocs-install-info.txt"

if [ "${EUID}" -ne 0 ]; then
    echo "VIGA: käivita skript root-õigustes:"
    echo "sudo ./ocs_install.sh"
    exit 1
fi

echo "=============================================="
echo " OCS Inventory NG ${OCS_VERSION} paigaldus"
echo "=============================================="

# Hoiatus, kui samas masinas on WordPressi kataloog.
if [ -d "/var/www/wordpress" ]; then
    echo
    echo "MÄRKUS: /var/www/wordpress on olemas."
    echo "Skript ei kustuta ega muuda WordPressi faile."
    echo "OCS saab kasutada sama Apache/MariaDB serverit, kuid eraldi andmebaasi."
    echo
fi

# Genereerime OCS-i andmebaasi kasutajale parooli.
# Kasutame ainult tähti ja numbreid, et SQL-käsus ei tekiks erimärkidega probleeme.
OCS_DB_PASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 || true)"
if [ -z "$OCS_DB_PASS" ]; then
    echo "VIGA: andmebaasi parooli genereerimine ebaõnnestus."
    exit 1
fi

echo "[1/7] Pakettide nimekirja uuendamine..."
apt-get update

echo "[2/7] Apache, MariaDB, PHP ja Perl moodulite paigaldamine..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apache2 mariadb-server mariadb-client \
    php libapache2-mod-php php-mbstring php-xml php-mysql php-zip php-pclzip \
    php-gd php-soap php-curl \
    perl curl wget git make gcc cmake composer \
    libapache2-mod-perl2 libapache2-mod-perl2-dev \
    libapache-dbi-perl libarchive-zip-perl \
    libxml-simple-perl libcompress-zlib-perl libdbi-perl \
    libdbd-mysql-perl libnet-ip-perl libsoap-lite-perl libio-compress-perl

# Mõned lisamoodulid on Ubuntu versiooniti erineva paketinimega.
# Paigaldame need ainult siis, kui pakett on saadaval.
OPTIONAL_PACKAGES=(
    libxml-entities-perl
    libmojolicious-perl
    libswitch-perl
    libplack-perl
)

for pkg in "${OPTIONAL_PACKAGES[@]}"; do
    if apt-cache show "$pkg" >/dev/null 2>&1; then
        apt-get install -y "$pkg"
    fi
done

systemctl enable --now apache2
systemctl enable --now mariadb

echo "[3/7] OCS-i andmebaasi loomine..."
mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${OCS_DB}\`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${OCS_DB_USER}'@'localhost'
  IDENTIFIED BY '${OCS_DB_PASS}';
ALTER USER '${OCS_DB_USER}'@'localhost'
  IDENTIFIED BY '${OCS_DB_PASS}';
GRANT ALL PRIVILEGES ON \`${OCS_DB}\`.* TO '${OCS_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

echo "[4/7] PHP põhiseadete kohandamine..."
PHP_VER="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
PHP_INI="/etc/php/${PHP_VER}/apache2/php.ini"

if [ -f "$PHP_INI" ]; then
    sed -i 's/^[;[:space:]]*memory_limit[[:space:]]*=.*/memory_limit = 512M/' "$PHP_INI"
    sed -i 's/^[;[:space:]]*post_max_size[[:space:]]*=.*/post_max_size = 100M/' "$PHP_INI"
    sed -i 's/^[;[:space:]]*upload_max_filesize[[:space:]]*=.*/upload_max_filesize = 100M/' "$PHP_INI"
    sed -i 's/^[;[:space:]]*max_execution_time[[:space:]]*=.*/max_execution_time = 360/' "$PHP_INI"

    if grep -Eq '^[;[:space:]]*date\.timezone[[:space:]]*=' "$PHP_INI"; then
        sed -i 's|^[;[:space:]]*date\.timezone[[:space:]]*=.*|date.timezone = Europe/Tallinn|' "$PHP_INI"
    else
        echo 'date.timezone = Europe/Tallinn' >> "$PHP_INI"
    fi
fi

systemctl restart apache2

echo "[5/7] OCS Inventory Serveri allalaadimine..."
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

rm -f "$OCS_ARCHIVE"
curl -fL "$OCS_URL" -o "$OCS_ARCHIVE"

rm -rf "$OCS_DIR"
tar -xzf "$OCS_ARCHIVE"

if [ ! -d "$OCS_DIR" ]; then
    echo "VIGA: oodatud kataloogi $OCS_DIR ei tekkinud."
    echo "Kontrolli OCS-i versiooni ja allalaaditud arhiivi."
    exit 1
fi

cd "$OCS_DIR"

echo "[6/7] setup.answers faili loomine..."
cat > setup.answers <<EOF
DB_SERVER_HOST="localhost"
DB_SERVER_PORT="3306"
DB_SERVER_USER="${OCS_DB_USER}"
DB_SERVER_PWD="${OCS_DB_PASS}"
APACHE_USER="www-data"
APACHE_GROUP="www-data"
EOF

chmod 600 setup.answers

cat > "$INFO_FILE" <<EOF
OCS Inventory NG ${OCS_VERSION}

Andmebaas: ${OCS_DB}
Andmebaasi kasutaja: ${OCS_DB_USER}
Andmebaasi parool: ${OCS_DB_PASS}

Paigalduse lähtekataloog:
${OCS_DIR}

Pärast setup.sh lõpetamist:
http://SERVERI_IP/ocsreports
EOF
chmod 600 "$INFO_FILE"

echo
echo "=============================================="
echo " Käivitan OCS-i ametliku setup.sh paigaldaja"
echo "=============================================="
echo
echo "Enamiku küsimuste puhul sobib vaikimisi vastus."
echo "Andmebaasiserver on localhost."
echo
read -r -p "Vajuta ENTER, et setup.sh käivitada..."

# OCS setup kasutab mõnes versioonis Bashi süntaksit,
# seetõttu käivitame selle bashiga.
bash ./setup.sh

echo "[7/7] Apache konfiguratsioonide lubamine..."

for conf in ocsinventory-server ocsinventory-reports ocsinventory-restapi; do
    if [ -f "/etc/apache2/conf-available/${conf}.conf" ]; then
        a2enconf "$conf" >/dev/null
    fi
done

if [ -d "/var/lib/ocsinventory-reports" ]; then
    chown -R www-data:www-data /var/lib/ocsinventory-reports
fi

apache2ctl configtest
systemctl restart apache2

SERVER_IP="$(hostname -I | awk '{print $1}')"

echo
echo "=============================================="
echo " OCS-i serveriosa paigaldus on lõpetatud"
echo "=============================================="
echo
echo "Ava brauseris:"
echo "http://${SERVER_IP}/ocsreports"
echo
echo "Andmebaasi andmed on salvestatud faili:"
echo "$INFO_FILE"
echo
echo "Pärast OCS-i veebipaigalduse lõpetamist eemalda install.php:"
echo "mv /usr/share/ocsinventory-reports/ocsreports/install.php \\"
echo "   /usr/share/ocsinventory-reports/ocsreports/install.php.bak"
echo
echo "Kontrolli teenuseid:"
echo "systemctl status apache2"
echo "systemctl status mariadb"
echo
