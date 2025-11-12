#!/bin/bash

# PostgreSQL Installation and User Setup Script for Ubuntu
# WITH PUBLIC ACCESS (DEV ENVIRONMENT ONLY)
# Run with sudo: sudo bash install_postgres.sh

set -e  # Exit on error

echo "================================"
echo "PostgreSQL Installation Script"
echo "WITH PUBLIC ACCESS - DEV ONLY"
echo "================================"
echo ""
echo "⚠️  WARNING: This script will make PostgreSQL publicly accessible!"
echo "⚠️  Only use this for development/testing environments!"
echo "⚠️  NEVER use this configuration in production!"
echo ""
read -p "Do you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Installation cancelled."
    exit 0
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Update package list
echo "Updating package list..."
apt update

# Install PostgreSQL
echo "Installing PostgreSQL..."
apt install -y postgresql postgresql-contrib

# Start and enable PostgreSQL service
echo "Starting PostgreSQL service..."
systemctl start postgresql
systemctl enable postgresql

# Get PostgreSQL version
PG_VERSION=$(psql --version | awk '{print $3}' | cut -d. -f1)
echo "PostgreSQL version $PG_VERSION installed successfully"

# Configure user
echo ""
echo "================================"
echo "User Configuration"
echo "================================"

read -p "Enter database username to create: " DB_USER
read -sp "Enter password for $DB_USER: " DB_PASS
echo ""
read -p "Enter database name to create (or press Enter to skip): " DB_NAME

# Switch to postgres user and create database user
echo "Creating database user..."
sudo -u postgres psql <<EOF
-- Create user with password
CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';

-- Grant permissions (you can modify these as needed)
ALTER USER $DB_USER WITH CREATEDB;
ALTER USER $DB_USER WITH CREATEROLE;

-- If you want superuser privileges (use cautiously):
-- ALTER USER $DB_USER WITH SUPERUSER;

\du
EOF

# Create database if specified
if [ ! -z "$DB_NAME" ]; then
    echo "Creating database $DB_NAME..."
    sudo -u postgres psql <<EOF
CREATE DATABASE $DB_NAME OWNER $DB_USER;
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
\l
EOF
fi

# Configure PostgreSQL to allow password authentication from anywhere
echo "Configuring PostgreSQL for public access..."
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"

# Backup original configs
cp $PG_HBA ${PG_HBA}.backup
cp $PG_CONF ${PG_CONF}.backup

# Configure postgresql.conf to listen on all interfaces
echo "Configuring PostgreSQL to listen on all interfaces..."
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" $PG_CONF
# In case it's already uncommented
sed -i "s/listen_addresses = 'localhost'/listen_addresses = '*'/" $PG_CONF

# Configure pg_hba.conf to allow connections from any IP
echo "Configuring authentication for remote access..."
if ! grep -q "# Added by setup script for public access" $PG_HBA; then
    cat >> $PG_HBA <<EOF

# Added by setup script for public access
# WARNING: This allows connections from any IP address!
local   all             $DB_USER                                md5
host    all             $DB_USER        0.0.0.0/0               md5
host    all             $DB_USER        ::/0                    md5
EOF
fi

# Configure firewall (UFW) if it's active
echo "Checking firewall configuration..."
if command -v ufw &> /dev/null; then
    if ufw status | grep -q "Status: active"; then
        echo "Opening port 5432 in UFW firewall..."
        ufw allow 5432/tcp
        echo "✓ Port 5432 opened in UFW"
    else
        echo "UFW is installed but not active"
    fi
else
    echo "UFW not installed, skipping firewall configuration"
fi

# Restart PostgreSQL to apply changes
echo "Restarting PostgreSQL..."
systemctl restart postgresql

# Get server's public IP
echo "Detecting server IP addresses..."
PRIVATE_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s ifconfig.me || echo "Unable to detect")

# Test local connection
echo ""
echo "================================"
echo "Testing connection..."
echo "================================"

if [ ! -z "$DB_NAME" ]; then
    echo "Testing local connection to database $DB_NAME..."
    PGPASSWORD=$DB_PASS psql -U $DB_USER -d $DB_NAME -h localhost -c "SELECT version();" 2>&1 && echo "✓ Local connection successful!" || echo "✗ Local connection failed"
fi

# Display connection info
echo ""
echo "================================"
echo "Installation Complete!"
echo "================================"
echo "PostgreSQL has been installed and configured for PUBLIC ACCESS."
echo ""
echo "⚠️  SECURITY WARNING:"
echo "    Your database is now accessible from the internet!"
echo "    Make sure to use strong passwords and consider:"
echo "    - Using a firewall to restrict access to specific IPs"
echo "    - Using SSL/TLS connections"
echo "    - Regularly updating PostgreSQL"
echo ""
echo "Connection details:"
echo "  Host (local): localhost or $PRIVATE_IP"
if [ "$PUBLIC_IP" != "Unable to detect" ]; then
    echo "  Host (remote): $PUBLIC_IP"
fi
echo "  Port: 5432"
echo "  User: $DB_USER"
echo "  Password: $DB_PASS"
echo "  Database: ${DB_NAME:-postgres}"
echo ""
echo "To connect locally using psql:"
echo "  psql -U $DB_USER -d ${DB_NAME:-postgres} -h localhost"
echo ""
echo "To connect remotely using psql:"
if [ "$PUBLIC_IP" != "Unable to detect" ]; then
    echo "  psql -U $DB_USER -d ${DB_NAME:-postgres} -h $PUBLIC_IP"
fi
echo ""
echo "Connection string for applications:"
echo "  postgresql://$DB_USER:$DB_PASS@$PRIVATE_IP:5432/${DB_NAME:-postgres}"
if [ "$PUBLIC_IP" != "Unable to detect" ]; then
    echo "  postgresql://$DB_USER:$DB_PASS@$PUBLIC_IP:5432/${DB_NAME:-postgres}"
fi
echo ""
echo "Config backups:"
echo "  ${PG_HBA}.backup"
echo "  ${PG_CONF}.backup"
echo ""
echo "⚠️  Remember: This is for DEV/TEST only - never use in production!"
echo "================================"