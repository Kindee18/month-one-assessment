#!/bin/bash

# Update system
yum update -y

# Install PostgreSQL
amazon-linux-extras install postgresql13 -y
yum install -y postgresql-server postgresql-contrib

# Initialize PostgreSQL database
postgresql-setup initdb

# Start and enable PostgreSQL
systemctl start postgresql
systemctl enable postgresql

# Configure PostgreSQL
sudo -u postgres psql << EOF
CREATE USER techcorp WITH PASSWORD '${server_password}';
CREATE DATABASE techcorp_db OWNER techcorp;
GRANT ALL PRIVILEGES ON DATABASE techcorp_db TO techcorp;
\q
EOF

# Configure PostgreSQL to accept connections
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /var/lib/pgsql/data/postgresql.conf

# Configure pg_hba.conf for authentication
echo "host    all             all             10.0.0.0/16            md5" >> /var/lib/pgsql/data/pg_hba.conf

# Restart PostgreSQL to apply changes
systemctl restart postgresql

# Create user with password for SSH access
useradd -m techcorp
# Password will be injected via Terraform `templatefile()` as ${server_password}
echo "techcorp:${server_password}" | chpasswd
usermod -aG wheel techcorp

# Install public key for techcorp (injected via Terraform as ${public_key})
mkdir -p /home/techcorp/.ssh
echo '${public_key}' >> /home/techcorp/.ssh/authorized_keys
chown -R techcorp:techcorp /home/techcorp/.ssh
chmod 700 /home/techcorp/.ssh
chmod 600 /home/techcorp/.ssh/authorized_keys

# Enable password authentication (optional; having the key allows key-based SSH)
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd

# Configure firewall
systemctl start firewalld
systemctl enable firewalld
firewall-cmd --permanent --add-port=5432/tcp
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload

# Create a simple test table
sudo -u postgres psql -d techcorp_db << EOF
CREATE TABLE test_table (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO test_table (name) VALUES ('TechCorp Test Data');
\q
EOF