#!/bin/bash

# ------------ CONFIGS -----------
REPO_URL_GUACAMOLE_SERVER="https://github.com/apache/guacamole-server.git"
REPO_URL_GUACAMOLE_CLIENT="https://github.com/yasin-pro/fidranet.git"
TARGET_DIR_GUACAMOLE_SERVER="guacamole-server"
WAR_NAME="fidarnet.war"
WEBAPPS_DIR="/opt/tomcat/webapps/"
TOMCAT_VERSION="9.0.88"
TOMCAT_URL="https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"
TOMCAT_INSTALL_DIR="/opt/tomcat"
TOMCAT_USER="tomcat"
TOMCAT_GROUP="tomcat"
SYSTEMD_SERVICE_TOMCAT="/etc/systemd/system/tomcat9.service"
TOMCAT_BIN_SYMLINK="/usr/local/bin/tomcat9"
DB_NAME="fidarnet_db"
DB_USER="F1darnet@dmin_user"
DB_PASS="F1darnetP@ssMss@P_user"
ADMIN_USER="F1darnetP@Madmin"
ADMIN_PASS="P@ssw0rdF1d@rn3t2024!#"

RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; CYAN="\e[36m"; RESET="\e[0m"

echo -e "
${CYAN}----------------------------------------------${RESET}"
echo -e "${CYAN}  Fidarnet PAM Installation Script"
echo -e "----------------------------------------------${RESET}
"

# --- Check Internet ---
echo -e "${YELLOW}[Step] Checking internet connection...${RESET}"
ping -c 1 github.com > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}[Error] No internet connection. Exiting.${RESET}"
    exit 1
fi
echo -e "${GREEN}[Info] Internet connection is OK.${RESET}
"

# --- Install Dependencies ---
echo -e "${YELLOW}[Step] Installing build dependencies...${RESET}"

if command -v apt >/dev/null 2>&1; then
    sudo apt update
    sudo apt install -y \
      autoconf automake build-essential libtool libtool-bin pkg-config \
      libcairo2-dev libjpeg-turbo8-dev libpng-dev uuid-dev libossp-uuid-dev \
      libvncserver-dev freerdp2-dev libwinpr2-dev libpango1.0-dev \
      libssh2-1-dev libtelnet-dev libwebsockets-dev libpulse-dev libssl-dev \
      libvorbis-dev libwebp-dev libavcodec-dev libavformat-dev libavutil-dev \
      libswscale-dev git wget openjdk-11-jdk
elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y epel-release
    sudo yum install -y \
      autoconf automake make gcc libtool pkgconfig cairo-devel \
      libjpeg-turbo-devel libpng-devel uuid-devel ffmpeg-devel \
      freerdp-devel pango-devel libssh2-devel telnet-devel \
      libvncserver-devel libwebsockets-devel pulseaudio-libs-devel \
      openssl-devel libvorbis-devel libwebp-devel git wget java-11-openjdk-devel
elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y epel-release
    sudo dnf install -y \
      autoconf automake make gcc libtool pkgconf-pkg-config \
      cairo-devel libjpeg-turbo-devel libpng-devel ossp-uuid-devel ffmpeg-devel \
      freerdp-devel pango-devel libssh2-devel libtelnet-devel \
      libvncserver-devel libwebsockets-devel pulseaudio-libs-devel \
      openssl-devel libvorbis-devel libwebp-devel git wget java-11-openjdk-devel
else
    echo -e "${RED}[Error] No supported package manager found!${RESET}"
    exit 10
fi
echo -e "${GREEN}[Info] Dependencies installed.${RESET}
"

# --- JAVA 11 Check & Install ---
echo -e "${YELLOW}[Step] Checking Java 11 installation...${RESET}"

INSTALL_JAVA=0
if command -v java >/dev/null 2>&1 && command -v javac >/dev/null 2>&1; then
    JAVA_VER=$(java -version 2>&1 | grep "version" | awk -F '"' '{print $2}')
    if [[ "$JAVA_VER" != 11* ]]; then
        INSTALL_JAVA=1
    fi
else
    INSTALL_JAVA=1
fi
if [ $INSTALL_JAVA -eq 1 ]; then
    echo -e "${YELLOW}[Info] Installing OpenJDK 11...${RESET}"
    if command -v apt >/dev/null 2>&1; then
        sudo apt install openjdk-11-jdk -y
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install java-11-openjdk-devel -y
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install java-11-openjdk-devel -y
    else
        echo -e "${RED}[Error] No supported package manager for Java!${RESET}"; exit 11;
    fi
fi
# -- Set Java as default --
if command -v update-alternatives >/dev/null 2>&1; then
    JAVA_11_BIN=$(update-alternatives --list java 2>/dev/null | grep java-11 | head -n1)
    JAVAC_11_BIN=$(update-alternatives --list javac 2>/dev/null | grep java-11 | head -n1)
    if [ -n "$JAVA_11_BIN" ]; then sudo update-alternatives --set java "$JAVA_11_BIN"; fi
    if [ -n "$JAVAC_11_BIN" ]; then sudo update-alternatives --set javac "$JAVAC_11_BIN"; fi
fi
echo -e "${GREEN}[Info] Java version: $(java -version 2>&1 | head -n1)${RESET}
"

# --- TOMCAT Cleanup & Install ---
echo -e "${YELLOW}[Step] Cleaning old Tomcat 9 installation...${RESET}"

sudo systemctl stop tomcat9 2>/dev/null
sudo systemctl disable tomcat9 2>/dev/null
[ -f "$SYSTEMD_SERVICE_TOMCAT" ] && sudo rm -f "$SYSTEMD_SERVICE_TOMCAT"
id "$TOMCAT_USER" &>/dev/null && sudo userdel -r "$TOMCAT_USER" 2>/dev/null
getent group "$TOMCAT_GROUP" &>/dev/null && sudo groupdel "$TOMCAT_GROUP" 2>/dev/null
[ -d "$TOMCAT_INSTALL_DIR" ] && sudo rm -rf "$TOMCAT_INSTALL_DIR"
[ -L "/usr/local/tomcat9" ] && sudo rm -f "/usr/local/tomcat9"
sudo systemctl daemon-reload
echo -e "${GREEN}[Info] Old Tomcat cleaned up.${RESET}
"

echo -e "${YELLOW}[Step] Downloading and Installing Tomcat $TOMCAT_VERSION...${RESET}"
wget -O /tmp/apache-tomcat-$TOMCAT_VERSION.tar.gz "$TOMCAT_URL"
if [ $? -ne 0 ]; then
    echo -e "${RED}[Error] Failed to download Tomcat!${RESET}"
    exit 21
fi

sudo mkdir -p "$TOMCAT_INSTALL_DIR"
sudo tar -xzf /tmp/apache-tomcat-$TOMCAT_VERSION.tar.gz -C "$TOMCAT_INSTALL_DIR" --strip-components=1
sudo rm -f /tmp/apache-tomcat-$TOMCAT_VERSION.tar.gz
if ! id "$TOMCAT_USER" &>/dev/null; then
    sudo groupadd "$TOMCAT_GROUP"
    sudo useradd -s /bin/false -g "$TOMCAT_GROUP" -d "$TOMCAT_INSTALL_DIR" "$TOMCAT_USER"
fi
sudo chown -R "$TOMCAT_USER":"$TOMCAT_GROUP" "$TOMCAT_INSTALL_DIR"
sudo chmod -R 755 "$TOMCAT_INSTALL_DIR"
sudo ln -sf "$TOMCAT_INSTALL_DIR" /usr/local/tomcat9
echo -e "${GREEN}[Info] Tomcat $TOMCAT_VERSION installed to $TOMCAT_INSTALL_DIR${RESET}
"

# --- Tomcat systemd Service ---
echo -e "${YELLOW}[Step] Setting up Tomcat systemd service...${RESET}"
cat <<EOF | sudo tee $SYSTEMD_SERVICE_TOMCAT >/dev/null
[Unit]
Description=Apache Tomcat 9 Web Application Container
After=network.target

[Service]
Type=forking
User=$TOMCAT_USER
Group=$TOMCAT_GROUP
Environment=JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
Environment=CATALINA_PID=$TOMCAT_INSTALL_DIR/temp/tomcat.pid
Environment=CATALINA_HOME=$TOMCAT_INSTALL_DIR
Environment=CATALINA_BASE=$TOMCAT_INSTALL_DIR
ExecStart=$TOMCAT_INSTALL_DIR/bin/startup.sh
ExecStop=$TOMCAT_INSTALL_DIR/bin/shutdown.sh
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable tomcat9
sudo systemctl start tomcat9
sudo ln -sf "$TOMCAT_INSTALL_DIR/bin/catalina.sh" "$TOMCAT_BIN_SYMLINK"
sudo chmod +x "$TOMCAT_BIN_SYMLINK"
echo -e "${GREEN}[Info] Tomcat service started successfully!${RESET}
"

# --- Guacamole Server Cleanup & Build ---
echo -e "${YELLOW}[Step] Removing old Guacamole server directory if exists...${RESET}"
[ -d "$TARGET_DIR_GUACAMOLE_SERVER" ] && rm -rf "$TARGET_DIR_GUACAMOLE_SERVER"

echo -e "${YELLOW}[Step] Downloading Guacamole server source...${RESET}"
git clone "$REPO_URL_GUACAMOLE_SERVER"
if [ $? -ne 0 ]; then
    echo -e "${RED}[Error] Failed to clone Guacamole server from repository!${RESET}"
    exit 31
fi

cd "$TARGET_DIR_GUACAMOLE_SERVER" || { echo -e "${RED}[Error] Failed to enter $TARGET_DIR_GUACAMOLE_SERVER directory!${RESET}"; exit 32; }
echo -e "${CYAN}[Info] Running autoreconf...${RESET}"
autoreconf -fi || { echo -e "${RED}[Error] autoreconf failed!${RESET}"; exit 33; }
echo -e "${CYAN}[Info] Running configure...${RESET}"
./configure --with-systemd-dir=/usr/local/lib/systemd/system || { echo -e "${RED}[Error] configure failed!${RESET}"; exit 34; }
echo -e "${CYAN}[Info] Running make...${RESET}"
make || { echo -e "${RED}[Error] make failed!${RESET}"; exit 35; }
echo -e "${CYAN}[Info] Running make install...${RESET}"
sudo make install || { echo -e "${RED}[Error] make install failed!${RESET}"; exit 36; }
sudo ldconfig
cd ..
echo -e "${GREEN}[Info] Guacamole server built & installed successfully.${RESET}
"

# --- Install Maven Setup ---
echo -e "${YELLOW}[Step] Installing Maven...${RESET}"
if ! command -v mvn >/dev/null 2>&1; then
    if command -v apt >/dev/null 2>&1; then
        sudo apt install -y maven
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y maven
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y maven
    fi
fi
echo -e "${GREEN}[Info] Maven installed.${RESET}"


# --------- Install Node.js, npm and npx (cross-distribution, with fix for mirrors, registry and npx) ----------
echo -e "${YELLOW}Installing Node.js LTS + npm + npx ...${RESET}"

install_nodejs() {
    NODE_INSTALLED=0
    if command -v node >/dev/null 2>&1; then
        NODE_VERSION=$(node -v | sed 's/v//')
        NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
        if [ "$NODE_MAJOR" -ge 14 ]; then
            NODE_INSTALLED=1
        fi
    fi
    if [ $NODE_INSTALLED -eq 0 ]; then
        if command -v apt >/dev/null 2>&1; then
            curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - && \
            sudo apt-get install -y nodejs
        elif command -v yum >/dev/null 2>&1; then
            curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash - && \
            sudo yum install -y nodejs
        elif command -v dnf >/dev/null 2>&1; then
            curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash - && \
            sudo dnf install -y nodejs
        else
            echo -e "${RED}No supported installer found for Node.js!${RESET}"
            exit 25
        fi
    fi
}

install_nodejs

which node && node -v
which npm  && npm -v
which npx  && npx -v

echo -e "${YELLOW}Upgrading npm to last stable version...${RESET}"
sudo npm install -g npm
npm -v

echo -e "${YELLOW}Setting npm registry mirror to solve common connectivity issues...${RESET}"
npm set registry https://registry.npmmirror.com

echo -e "${YELLOW}Cleaning npm cache...${RESET}"
npm cache clean --force

echo -e "${GREEN}Node.js, npm, npx setup completed successfully.${RESET}\n"


# ---------- 2. Node/NPM Version & nvm ----------
echo -e "${CYAN}2. Checking and Configuring Node.js (via nvm)...${RESET}"
REQUIRED_NODE_VER="18.20.8"
if ! command -v nvm >/dev/null 2>&1; then
    echo -e "${YELLOW}nvm not found, installing...${RESET}"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
fi
export NVM_DIR="$HOME/.nvm"
. "$NVM_DIR/nvm.sh"

nvm install $REQUIRED_NODE_VER
nvm use $REQUIRED_NODE_VER

NODE_VER=$(node -v)
NPM_VER=$(npm -v)
echo -e "${YELLOW}Node.js version: $NODE_VER${RESET}"
echo -e "${YELLOW}NPM version: $NPM_VER${RESET}"

echo -e "${CYAN}3. Toughening npm (for network issues)...${RESET}"
npm set fetch-timeout 120000
npm set fetch-retries 5
npm set fetch-retry-mintimeout 20000
npm set fetch-retry-maxtimeout 180000
npm config set registry https://registry.npmmirror.com/

# ---------- 5. Environment Setup for Java ----------
echo -e "${CYAN}3. JAVA_HOME and PATH configuration...${RESET}"
sudo chown -R $(whoami):$(whoami) .
JAVA_PATH=$(readlink -f $(which java))
JAVA_HOME_AUTO="$(dirname $(dirname "$JAVA_PATH"))"
export JAVA_HOME="$JAVA_HOME_AUTO"
export PATH="$JAVA_HOME/bin:$PATH"

echo -e "${YELLOW}JAVA_HOME set to: $JAVA_HOME${RESET}"
java -version || { echo -e "${RED}java not found!${RESET}"; exit 21;}
javac -version || { echo -e "${RED}javac not found!${RESET}"; exit 22;}
javadoc -version


# --------- Download Fidranet War And Install. ----------
echo -e "${CYAN}4. Download Fidarnet War And Install...${RESET}"

# Clean up previous extracted folder if exists
if [ -d "fidarnet" ]; then
    echo -e "${YELLOW}[Info] Previous fidarnet directory found. Removing...${RESET}"
    rm -rf fidarnet
fi

echo -e "${YELLOW}[Step 1] Cloning Fidranet repository...${RESET}"
git clone "$REPO_URL_GUACAMOLE_CLIENT"
if [ $? -ne 0 ]; then
    echo -e "${RED}[Error] Failed to clone repository: $REPO_URL_GUACAMOLE_CLIENT${RESET}"
    exit 10
fi
echo -e "${GREEN}[Success] Repository cloned successfully.${RESET}\n"

cd fidarnet/

if [ ! -f "$WAR_NAME" ]; then
    echo -e "${RED}[Error] WAR file ($WAR_NAME) not found in the repository folder!${RESET}"
    cd ..
    rm -rf fidarnet
    exit 12
fi

echo -e "${YELLOW}[Step 2] Removing old WAR file from Tomcat webapps...${RESET}"
if [ -f "$WEBAPPS_DIR/$WAR_NAME" ]; then
    sudo rm -f "$WEBAPPS_DIR/$WAR_NAME"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[Success] Old WAR file removed successfully.${RESET}"
    else
        echo -e "${RED}[Error] Failed to remove old WAR file. Check permissions.${RESET}"
        cd ..
        rm -rf fidarnet
        exit 13
    fi
else
    echo -e "${YELLOW}[Warn] No old WAR file existed in $WEBAPPS_DIR.${RESET}"
fi

echo -e "${YELLOW}[Step 3] Copying new WAR file to Tomcat webapps...${RESET}"
sudo cp "$WAR_NAME" "$WEBAPPS_DIR/"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[Success] New WAR file copied to $WEBAPPS_DIR.${RESET}"
else
    echo -e "${RED}[Error] Failed to copy new WAR file!${RESET}"
    cd ..
    rm -rf fidarnet
    exit 14
fi

cd ..
rm -rf fidarnet

# # Move & cleanup WAR file and directory
# if [ -f /opt/tomcat/webapps/fidarnet.war ]; then
#     sudo mv /opt/tomcat/webapps/fidarnet.war /opt/tomcat/webapps/guacamole.war
#     echo -e "${GREEN}[Success] fidarnet.war replaced as guacamole.war.${RESET}"
# else
#     echo -e "${RED}[Error] fidarnet.war not found in webapps!${RESET}"
#     exit 15
# fi

# if [ -d /opt/tomcat/webapps/fidarnet ]; then
#     sudo rm -rf /opt/tomcat/webapps/fidarnet/
#     echo -e "${GREEN}[Success] Old fidarnet exploded directory removed.${RESET}"
# else
#     echo -e "${YELLOW}[Warn] No fidarnet exploded directory found. Skipping removal.${RESET}"
# fi

# echo -e "${GREEN}fidarnet war file setup completed successfully.${RESET}\n"



# --------- Config & initial database setup ----------
echo -e "\n${CYAN}------ Guacamole Database Setup: Force Clean Install ------${RESET}"

if ! command -v mysql >/dev/null 2>&1; then
    echo -e "${YELLOW}MySQL/MariaDB not detected. Installing...${RESET}"
    if command -v apt >/dev/null 2>&1; then
        sudo apt-get install -y mysql-server
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y mariadb-server
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y mariadb-server
    else
        echo -e "${RED}No known package manager to install MySQL!${RESET}"; exit 110
    fi
    sudo systemctl enable --now mysql || sudo systemctl enable --now mariadb
fi

mysql -uroot <<EOF
DROP DATABASE IF EXISTS \`$DB_NAME\`;
DROP USER IF EXISTS '$DB_USER'@'localhost';
CREATE DATABASE \`$DB_NAME\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[$DB_NAME] database and [$DB_USER] user (clean) created fresh!${RESET}"
else
    echo -e "${RED}[DB Error] Could not recreate [$DB_NAME] database!${RESET}"
    exit 111
fi

# --------- Config Tomcat for Guacamole. ----------
echo -e "\n${CYAN}------ Guacamole Tomcat Config ------${RESET}"

TOMCAT_USER=tomcat
TOMCAT_GROUP=tomcat

sudo mkdir -p /etc/guacamole/extensions
sudo mkdir -p /etc/guacamole/lib
sudo mkdir -p /etc/guacamole

SERVICE_FILE="/etc/systemd/system/tomcat9.service"
GUACAMOLE_ENV="Environment=GUACAMOLE_HOME=/etc/guacamole"

if [ -f "$SERVICE_FILE" ]; then
    if ! grep -q "^$GUACAMOLE_ENV" "$SERVICE_FILE"; then
        # Insert after the first [Service] section
        sudo awk -v newline="$GUACAMOLE_ENV" '
            $0 ~ /^\[Service\]/ && !x {print; x=1; getline; print; print newline; next}
            {print}
        ' "$SERVICE_FILE" > "/tmp/tomcat9.service"
        sudo mv "/tmp/tomcat9.service" "$SERVICE_FILE"
        echo "Added GUACAMOLE_HOME to systemd service file."
    else
        echo "GUACAMOLE_HOME already set in the systemd service."
    fi
else
    echo "Service file $SERVICE_FILE not found! Aborting."
    exit 1
fi

sudo systemctl daemon-reload
sudo systemctl restart tomcat9
echo "Systemd daemon reloaded and Tomcat restarted."

export GUACAMOLE_HOME=/etc/guacamole

sudo bash -c "cat > /etc/guacamole/guacamole.properties" <<EOPROPS
mysql-hostname: localhost
mysql-port: 3306
mysql-database: $DB_NAME
mysql-username: $DB_USER
mysql-password: $DB_PASS
EOPROPS

sudo mkdir -p $TOMCAT_INSTALL_DIR/.guacamole
sudo ln -sf /etc/guacamole/guacamole.properties $TOMCAT_INSTALL_DIR/.guacamole/guacamole.properties
echo -e "${GREEN}guacamole.properties updated and symlinked.${RESET}"

sudo chown $TOMCAT_USER:$TOMCAT_GROUP /etc/guacamole/guacamole.properties
sudo chmod 640 /etc/guacamole/guacamole.properties
echo "Permissions set for guacamole.properties."

# Set permissions on Guacamole directory
sudo chown -R $TOMCAT_USER:$TOMCAT_GROUP /etc/guacamole
sudo chmod -R 750 /etc/guacamole
echo "Permissions set for /etc/guacamole and subfolders."

# --------- Setup Guacamole JDBC Authentication (MySQL) And Driver ----------
echo -e "${YELLOW}Setting up Guacamole JDBC authentication (MySQL)...${RESET}"

GUAC_VERSION="1.6.0"
JDBC_VERSION="8.0.31"
JDBC_DL_URL="https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/$JDBC_VERSION/mysql-connector-j-$JDBC_VERSION.jar"
JDBC_TARGET_LIB="$TOMCAT_INSTALL_DIR/lib/mysql-connector-java-$JDBC_VERSION.jar"
JDBC_TARGET_WEBINF="$TOMCAT_INSTALL_DIR/webapps/guacamole/WEB-INF/lib/mysql-connector-java-$JDBC_VERSION.jar"
JDBC_TARGET_GUACAMOLELIB="/etc/guacamole/lib/"

if [ ! -f "$JDBC_TARGET_LIB" ]; then
    echo -e "${YELLOW}MySQL Connector/J driver not present. Downloading...${RESET}"
    sudo wget -O "$JDBC_TARGET_LIB" "$JDBC_DL_URL"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to download MySQL JDBC driver!${RESET}"; exit 111
    fi
    echo -e "${GREEN}MySQL JDBC driver downloaded to Tomcat lib.${RESET}"
else
    echo -e "${GREEN}MySQL JDBC driver already present in Tomcat lib.${RESET}"
fi

if [ -d "$TOMCAT_INSTALL_DIR/webapps/guacamole/WEB-INF/lib" ]; then
    if [ ! -f "$JDBC_TARGET_WEBINF" ]; then
        echo -e "${YELLOW}Copying JDBC to guacamole WEB-INF/lib ...${RESET}"
        echo -e "${YELLOW}Copying JDBC to guacamole etc/guacamole/lib ...${RESET}"
        sudo cp "$JDBC_TARGET_LIB" "$JDBC_TARGET_WEBINF"
        sudo cp "$JDBC_TARGET_LIB" "$JDBC_TARGET_GUACAMOLELIB"
        echo -e "${GREEN}MySQL JDBC driver copied to WEB-INF/lib and /etc/guacamole/lib.${RESET}"
    else
        echo -e "${GREEN}MySQL JDBC driver already present in WEB-INF/lib and /etc/guacamole/lib.${RESET}"
    fi
else
    echo -e "${YELLOW}WEB-INF/lib not found yet. Will copy after first Tomcat deploy if needed.${RESET}"
    echo -e "${YELLOW}/etc/guacamole/lib not found yet. Will copy after first Tomcat deploy if needed.${RESET}"
fi

# --------- JDBC EXTENSION SETUP (JAR+SCHEMA, NEW TARBALL FORMAT) ---------
GUAC_JDBC_VERSION="${GUAC_VERSION}"
JDBC_TAR_URL="https://archive.apache.org/dist/guacamole/${GUAC_JDBC_VERSION}/binary/guacamole-auth-jdbc-${GUAC_JDBC_VERSION}.tar.gz"
JDBC_TAR_TMP="/tmp/guacamole-auth-jdbc-${GUAC_JDBC_VERSION}.tar.gz"
TMP_EXTRACT="/tmp/guacamole-jdbc-extract"
EXTENSIONS_DIR="/etc/guacamole/extensions"
SCHEMA_TARGET_DIR="/tmp/guac_schema"

echo -e "${YELLOW}Cleaning previous JDBC schema & tmp dirs ...${RESET}"
sudo rm -rf "$TMP_EXTRACT" "$SCHEMA_TARGET_DIR"

echo -e "${YELLOW}Downloading JDBC extension tar.gz ...${RESET}"
wget -O "$JDBC_TAR_TMP" "$JDBC_TAR_URL"
if [ $? -ne 0 ]; then
    echo -e "${RED}[ERR] JDBC extension download failed!${RESET}"; exit 201
fi

echo -e "${YELLOW}Extracting JDBC extension tar.gz ...${RESET}"
mkdir -p "$TMP_EXTRACT"
tar -xzf "$JDBC_TAR_TMP" -C "$TMP_EXTRACT"
if [ $? -ne 0 ]; then
    echo -e "${RED}Extraction failed!${RESET}"; exit 202
fi

MYSQL_JAR="${TMP_EXTRACT}/guacamole-auth-jdbc-${GUAC_JDBC_VERSION}/mysql/guacamole-auth-jdbc-mysql-${GUAC_JDBC_VERSION}.jar"
SCHEMA_DIR="${TMP_EXTRACT}/guacamole-auth-jdbc-${GUAC_JDBC_VERSION}/mysql/schema"

# Copy extension JAR
mkdir -p "$EXTENSIONS_DIR"
if [ -f "$MYSQL_JAR" ]; then
    sudo cp "$MYSQL_JAR" "$EXTENSIONS_DIR/"
    echo -e "${GREEN}MySQL JDBC extension JAR copied to $EXTENSIONS_DIR${RESET}"
else
    echo -e "${RED}[ERR] mysql/guacamole-auth-jdbc-mysql-${GUAC_JDBC_VERSION}.jar not found!${RESET}"; exit 203
fi

# Copy schema files
mkdir -p "$SCHEMA_TARGET_DIR"
if [ -d "$SCHEMA_DIR" ]; then
    sudo cp -r "$SCHEMA_DIR/"* "$SCHEMA_TARGET_DIR/"
    echo -e "${GREEN}MySQL schema SQLs copied to $SCHEMA_TARGET_DIR${RESET}"
else
    echo -e "${RED}[ERR] mysql/schema not found in JDBC archive!${RESET}"; exit 204
fi

# --------- SCHEMA IMPORT (AUTOMATIC) ----------
for SQL in "$SCHEMA_TARGET_DIR"/[0-9]*.sql; do
    if [ -f "$SQL" ]; then
        echo -e "${CYAN}Importing: $SQL${RESET}"
        mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$SQL"
        if [ $? -ne 0 ]; then
            echo -e "${RED}[ERR] Failed importing: $SQL${RESET}"
            exit 205
        fi
    fi
done

sudo rm -rf "$TMP_EXTRACT" "$JDBC_TAR_TMP" "$SCHEMA_TARGET_DIR"

echo -e "${GREEN}JDBC extension setup and schema import finished!${RESET}"


# --------- AUTO CREATE ADMIN USER IN DATABASE ----------

# Generate salt and hash
SALT=$(openssl rand -hex 8)
HASH=$(echo -n "${ADMIN_PASS}${SALT}" | sha256sum | awk '{print $1}')

echo -e "${CYAN}Creating or updating Guacamole admin user in the database...${RESET}"

# (1) If old admin exists (e.g., guacadmin), rename to new admin username
OLD_ADMIN="guacadmin"
mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -s -e "
    UPDATE guacamole_entity 
    SET name = '$ADMIN_USER' 
    WHERE name = '$OLD_ADMIN' AND type = 'USER';
"

# (2) Get entity_id for the admin user, insert if not exists
ENTITY_ID=$(mysql -u"$DB_USER" -p"$DB_PASS" -N -s -e "
    SELECT entity_id FROM guacamole_entity WHERE name='$ADMIN_USER' AND type='USER';
" "$DB_NAME")

if [ -z "$ENTITY_ID" ]; then
    ENTITY_ID=$(mysql -u"$DB_USER" -p"$DB_PASS" -N -s -e "
        INSERT INTO guacamole_entity (name, type) VALUES ('$ADMIN_USER', 'USER');
        SELECT LAST_INSERT_ID();
    " "$DB_NAME")
    echo -e "${GREEN}Inserted into guacamole_entity, entity_id: $ENTITY_ID${RESET}"
else
    echo -e "${YELLOW}User already exists (entity_id: $ENTITY_ID), updating password...${RESET}"
fi

# (3) Always update or insert user info
mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL
INSERT INTO guacamole_user (entity_id, password_hash, password_salt, password_date, disabled, expired)
VALUES ($ENTITY_ID, UNHEX('$HASH'), UNHEX('$SALT'), NOW(), 0, 0)
ON DUPLICATE KEY UPDATE
    password_hash=UNHEX('$HASH'), password_salt=UNHEX('$SALT'), password_date=NOW(), disabled=0, expired=0;
SQL

# (4) Grant administrator permission if not already present
mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL
INSERT IGNORE INTO guacamole_system_permission (entity_id, permission)
VALUES ($ENTITY_ID, 'ADMINISTER');
SQL

echo -e "${GREEN}Guacamole admin user '$ADMIN_USER' has been created or updated with admin rights.${RESET}"
echo -e "------------------------------------"
echo -e "Username: $ADMIN_USER"
echo -e "Password: $ADMIN_PASS"
echo -e "------------------------------------"


# --------- Start Services ----------
sudo systemctl enable tomcat9
sudo systemctl enable guacd
sudo systemctl restart tomcat9
sudo systemctl start guacd
