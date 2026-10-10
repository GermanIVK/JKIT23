#!/usr/bin/env bash
set -euo pipefail

# WordPressi automaatne paigaldus Ubuntu serverisse.
# Paigaldab Apache, MariaDB, PHP ja WP-CLI,
# loob andmebaasi ning kasutaja, paigaldab WordPressi
# ja seadistab Apache veebiserveri.

if [[ $EUID -ne 0 ]]; then
    echo "VIGA: käivita skript root-õigustes: sudo ./wordpress_full_install.sh"
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "VIGA: see skript on mõeldud Ubuntu/Debiani põhisele süsteemile."
    exit 1
fi

clear
echo "============================================"
echo "WordPressi täielik paigaldus"
echo "============================================"

# ----- Kasutaja sisend -----
read -rp "Andmebaasi nimi [wordpress]: " DB_NAME
DB_NAME=${DB_NAME:-wordpress}

read -rp "Andmebaasi kasutaja [wpuser]: " DB_USER
DB_USER=${DB_USER:-wpuser}

if [[ ! "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "VIGA: andmebaasi nimi võib sisaldada ainult tähti, numbreid ja alakriipsu."
    exit 1
fi

if [[ ! "$DB_USER" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "VIGA: andmebaasi kasutaja võib sisaldada ainult tähti, numbreid ja alakriipsu."
    exit 1
fi

read -rp "WordPressi saidi nimi [Minu WordPress]: " SITE_TITLE
SITE_TITLE=${SITE_TITLE:-Minu WordPress}

read -rp "WordPressi administraatori kasutajanimi [admin]: " WP_ADMIN
WP_ADMIN=${WP_ADMIN:-admin}

read -rsp "WordPressi administraatori parool: " WP_ADMIN_PASS
echo
if [[ -z "$WP_ADMIN_PASS" ]]; then
    echo "VIGA: administraatori parool ei tohi olla tühi."
    exit 1
fi

read -rp "Administraatori e-post [admin@example.local]: " WP_ADMIN_EMAIL
WP_ADMIN_EMAIL=${WP_ADMIN_EMAIL:-admin@example.local}

SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
SERVER_IP=${SERVER_IP:-127.0.0.1}
DEFAULT_URL="http://${SERVER_IP}"
read -rp "WordPressi aadress [${DEFAULT_URL}]: " SITE_URL
SITE_URL=${SITE_URL:-$DEFAULT_URL}
SITE_URL=${SITE_URL%/}

WEB_ROOT="/var/www/wordpress"
DB_PASS=$(openssl rand -hex 24)

if [[ -e "$WEB_ROOT/wp-config.php" ]]; then
    echo "VIGA: $WEB_ROOT sisaldab juba WordPressi seadistust."
    echo "Skript katkestati, et olemasolevat veebilehte mitte üle kirjutada."
    exit 1
fi

echo
echo "Paigaldus algab..."

# ----- Paketid -----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
    apache2 \
    mariadb-server \
    libapache2-mod-php \
    php \
    php-cli \
    php-mysql \
    php-curl \
    php-gd \
    php-mbstring \
    php-xml \
    php-zip \
    php-intl \
    php-bcmath \
    curl \
    ca-certificates \
    openssl

systemctl enable --now apache2
systemctl enable --now mariadb

# ----- WP-CLI -----
if ! command -v wp >/dev/null 2>&1; then
    echo "Paigaldan WP-CLI..."
    curl -fsSL -o /tmp/wp-cli.phar \
        https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    php /tmp/wp-cli.phar --info >/dev/null
    install -m 0755 /tmp/wp-cli.phar /usr/local/bin/wp
    rm -f /tmp/wp-cli.phar
fi

# ----- MariaDB -----
echo "Loon WordPressi andmebaasi ja kasutaja..."
mariadb <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# ----- WordPress -----
echo "Laadin WordPressi alla..."
mkdir -p "$WEB_ROOT"
wp core download \
    --path="$WEB_ROOT" \
    --allow-root

echo "Loon wp-config.php faili..."
wp config create \
    --path="$WEB_ROOT" \
    --dbname="$DB_NAME" \
    --dbuser="$DB_USER" \
    --dbpass="$DB_PASS" \
    --dbhost="localhost" \
    --dbcharset="utf8mb4" \
    --allow-root

echo "Lõpetan WordPressi paigalduse..."
wp core install \
    --path="$WEB_ROOT" \
    --url="$SITE_URL" \
    --title="$SITE_TITLE" \
    --admin_user="$WP_ADMIN" \
    --admin_password="$WP_ADMIN_PASS" \
    --admin_email="$WP_ADMIN_EMAIL" \
    --skip-email \
    --allow-root

# ----- Failiõigused -----
chown -R www-data:www-data "$WEB_ROOT"
find "$WEB_ROOT" -type d -exec chmod 755 {} \;
find "$WEB_ROOT" -type f -exec chmod 644 {} \;
chmod 640 "$WEB_ROOT/wp-config.php"

# ----- Apache -----
SERVER_NAME=${SITE_URL#*://}
SERVER_NAME=${SERVER_NAME%%/*}

cat > /etc/apache2/sites-available/wordpress.conf <<APACHE
<VirtualHost *:80>
    ServerName ${SERVER_NAME}
    DocumentRoot ${WEB_ROOT}

    <Directory ${WEB_ROOT}>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/wordpress_error.log
    CustomLog \${APACHE_LOG_DIR}/wordpress_access.log combined
</VirtualHost>
APACHE

a2enmod rewrite >/dev/null
# Uuel õppe-VM-il kasutame WordPressi saiti vaikimisi saidina.
a2dissite 000-default.conf >/dev/null 2>&1 || true
a2ensite wordpress.conf >/dev/null
apache2ctl configtest
systemctl reload apache2

# ----- Kontroll -----
wp core is-installed --path="$WEB_ROOT" --allow-root

# Salvesta genereeritud DB andmed ainult root-kasutajale loetavasse faili.
INFO_FILE="/root/wordpress-install-info.txt"
cat > "$INFO_FILE" <<INFO
WordPress URL: ${SITE_URL}
WordPress admin: ${WP_ADMIN}
Database: ${DB_NAME}
Database user: ${DB_USER}
Database password: ${DB_PASS}
Web root: ${WEB_ROOT}
INFO
chmod 600 "$INFO_FILE"

echo
echo "============================================"
echo "WordPress on paigaldatud."
echo "============================================"
echo "Aadress:       $SITE_URL"
echo "Admin:         ${SITE_URL}/wp-admin/"
echo "Veebikataloog: $WEB_ROOT"
echo "DB andmed:     $INFO_FILE"
echo
echo "NB! See õppeversioon seadistab HTTP ühenduse."
echo "Avalikus/produktsioonikeskkonnas seadista HTTPS (TLS) ja kasuta päris domeeninime."
