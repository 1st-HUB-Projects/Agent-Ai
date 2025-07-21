#!/bin/bash

# Script complet d'installation N8N sur EC2 Amazon Linux
# Prépare le système ET installe N8N en une seule fois

# Verifier si info dispo
if [ -z "$1" ] |

| [ -z "$2" ] |
| [ -z "$3" ] |
| [ -z "$4" ] |
| [ -z "$5" ] |
| [ -z "$6" ] |
| [ -z "$7" ] |
| [ -z "$8" ]; then
    echo ""
    echo "    SCRIPT COMPLET D'INSTALLATION N8N SUR EC2"
    echo ""
    echo "Usage:./complete_n8n_setup.sh <domaine> <rds_host> <db_user> <db_password> <db_name> <email_ssl> <n8n_username> <n8n_password>"
    echo ""
    echo "PARAMETRES REQUIS (8 parametres):"
    echo "  1. DOMAINE        - Votre domaine (ex: n8n.mondomaine.com)"
    echo "  2. RDS_HOST       - Point de terminaison RDS (ex: mydb.cluster-abc123.eu-west-1.rds.amazonaws.com)"
    echo "  3. DB_USER        - Utilisateur de la base de donnees (ex: postgres)"
    echo "  4. DB_PASSWORD    - Mot de passe de la base de donnees"
    echo "  5. DB_NAME        - Nom de la base de donnees (ex: n8n)"
    echo "  6. EMAIL_SSL      - Email pour le certificat SSL Let's Encrypt (ex: admin@mondomaine.com)"
    echo "  7. N8N_USERNAME   - Username pour l'authentification HTTP basique (ex: admin)"
    echo "  8. N8N_PASSWORD   - Password pour l'authentification HTTP basique"
    echo ""
    echo "EXEMPLE COMPLET:"
    echo "./complete_n8n_setup.sh \\"
    echo "    n8n.croissanceconsulting.com \\"
    echo "    mydb.cluster-abc123.eu-west-1.rds.amazonaws.com \\"
    echo "    postgres \\"
    echo "    monMotDePasseDB \\"
    echo "    n8n \\"
    echo "    admin@croissanceconsulting.com \\"
    echo "    admin \\"
    echo "    MonMotDePasseSecurise123"
    echo ""
    echo "PREREQUIS:"
    echo "  - Instance EC2 Amazon Linux avec accès Internet"
    echo "  - Instance RDS PostgreSQL créée et accessible"
    echo "  - Domaine pointant vers l'IP publique de l'EC2"
    echo "  - Ports 80 et 443 ouverts dans le Security Group"
    echo ""
    echo "CE QUE FAIT CE SCRIPT:"
    echo "  ✔ Met à jour le système"
    echo "  ✔ Installe tous les outils nécessaires (Nginx, Docker, PostgreSQL client, etc.)"
    echo "  ✔ Configure les services système"
    echo "  ✔ Installe et configure N8N avec RDS"
    echo "  ✔ Configure SSL/HTTPS automatiquement"
    echo "  ✔ Configure Nginx comme reverse proxy"
    echo ""
    echo "======================================================================"
    exit 1
fi

DOMAIN_OR_IP=$1
RDS_HOST=$2
POSTGRES_USER=$3
POSTGRES_PASSWORD=$4
POSTGRES_DB=$5
SSL_EMAIL=$6
N8N_AUTH_USER=$7
N8N_AUTH_PASSWORD=$8

echo "======================================================================"
echo "                      DEMARRAGE DE L'INSTALLATION COMPLETE              "
echo "======================================================================"
echo "Configuration detectee:"
echo "  - Domaine: $DOMAIN_OR_IP"
echo "  - RDS Host: $RDS_HOST"
echo "  - DB User: $POSTGRES_USER"
echo "  - DB Name: $POSTGRES_DB"
echo "  - Email SSL: $SSL_EMAIL"
echo "  - Auth HTTP: $N8N_AUTH_USER"
echo "======================================================================"
echo ""

# Eviter Conflit
unset PGUSER
unset PGPASSWORD

# Generer cle d'encryption aleatoire
generate_encryption_key() {
    openssl rand -base64 32
}

echo "================ ETAPE 1/4: PREPARATION DU SYSTEME ================"
echo ""

# Maj systeme
echo "🔄 Mise à jour du système..."
sudo yum update -y

# Installer, Demarrer et Activer Nginx
echo "🚀 Installation et configuration de Nginx..."
sudo yum install -y nginx
sudo systemctl start nginx
sudo systemctl enable nginx

# Installer Certbot
echo "🔒 Installation de Certbot pour SSL..."
sudo yum install -y epel-release
sudo yum install -y certbot python3-certbot-nginx

# Installer Crontab
echo "🕒 Installation et configuration de Cron..."
sudo yum install -y cronie
sudo systemctl start crond
sudo systemctl enable crond

# Installer Python, Pip, Git, Docker
echo "🐍 Installation de Python, Git, Docker..."
sudo yum install -y python3 python3-pip git docker

# Demarrer et Activer Docker
echo "🐳 Configuration de Docker..."
sudo systemctl start docker
sudo systemctl enable docker

# Ajouter l'utilisateur actuel au groupe Docker
sudo usermod -aG docker $USER

# Installer Docker Compose
echo "📦 Installation de Docker Compose..."
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Installer Postgres Client
echo "🐘 Installation du client PostgreSQL..."
sudo yum install -y postgresql15

# Installer Node.js
echo "🟢 Installation de Node.js..."
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo yum install -y nodejs

# Installer PM2
echo "🚀 Installation de PM2..."
sudo npm install -g pm2

echo ""
echo "✅ PREPARATION DU SYSTEME TERMINEE"
echo ""

# Appliquer les permissions Docker pour la session actuelle
echo "🐳 Application des permissions Docker..."
newgrp docker << EOFGRP

echo "================ ETAPE 2/4: PREPARATION DES FICHIERS N8N ================"
echo ""

# Verifier Docker
docker --version
docker-compose --version

# Creer repertoire pour N8N
mkdir -p /n8n-docker
cd /n8n-docker

# Telecharger certificat RDS SSL
echo "📜 Téléchargement du certificat RDS..."
wget https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem -O rds-ca.pem

# Generer cle d'encryption N8N
N8N_ENCRYPTION_KEY=\$(generate_encryption_key)

echo "📝 Création du fichier de configuration..."
# Creer le fichier.env
cat <<EOL >.env
# AWS RDS Config
RDS_HOST=$RDS_HOST
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB

# Auth n8n (désactivée par défaut - N8N a son propre système d'auth)
N8N_BASIC_AUTH_ACTIVE=false
N8N_BASIC_AUTH_USER=$N8N_AUTH_USER
N8N_BASIC_AUTH_PASSWORD=$N8N_AUTH_PASSWORD

# Domaine & SSL Config
DOMAIN_NAME=$DOMAIN_OR_IP
N8N_PATH=/

# Redis Config
REDIS_HOST=redis

# cle d'encryption n8n
N8N_ENCRYPTION_KEY=\$N8N_ENCRYPTION_KEY

# Optimisations recommandées par N8N
# Note: N8N_RUNNERS_ENABLED=false évite les erreurs 403 temporaires au démarrage
# Les Task Runners se configurent automatiquement après le premier redémarrage
N8N_RUNNERS_ENABLED=false
OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true

# Optimisations WebSocket et performance
N8N_DISABLE_UI=false
N8N_METRICS=false
EOL

echo "🚀 Création du script d'initialisation de la base..."
# Creer init-data.sh pour l'initialisation du PostgreSQL
cat <<EOL > init-data.sh
#!/bin/bash
set -e

rds_host=\\\$1
POSTGRES_USER=\\\$2
POSTGRES_PASSWORD=\\\$3
POSTGRES_DB=\\\$4

# Mot de passe PostgreSQL
export PGPASSWORD=\\\$POSTGRES_PASSWORD

# Verifier que la BD existe
DB_EXISTS=\$(psql -v ON_ERROR_STOP=1 --host="\\\$rds_host" --username="\\\$POSTGRES_USER" --dbname="postgres" --tuples-only --command="SELECT 1 FROM pg_database WHERE datname='\\\$POSTGRES_DB'")

if; then
    echo "Database \\\$POSTGRES_DB n existe pas. Je la cree..."
    psql -v ON_ERROR_STOP=1 --host="\\\$rds_host" --username="\\\$POSTGRES_USER" --dbname="postgres" --command="CREATE DATABASE \\\$POSTGRES_DB;"
else
    echo "Database \\\$POSTGRES_DB existe."
fi

# Privileges pour POSTGRES_USER
psql -v ON_ERROR_STOP=1 --host="\\\$rds_host" --username="\\\$POSTGRES_USER" --dbname="\\\$POSTGRES_DB" <<EOSQL
GRANT ALL PRIVILEGES ON DATABASE \\\$POSTGRES_DB TO \\\$POSTGRES_USER;
GRANT CREATE ON SCHEMA public TO \\\$POSTGRES_USER;
EOSQL

# Unset la variable mot de passe
unset PGPASSWORD
EOL
chmod +x init-data.sh

echo ""
echo "================ ETAPE 3/4: CONFIGURATION DE LA BASE DE DONNEES ================"
echo "==============================================================================="

# Verifier que PostgreSQL est accessible & lancer script d'initialisation
echo "🔎 Vérification de la connectivité PostgreSQL..."
until PGPASSWORD=$POSTGRES_PASSWORD psql --host="$RDS_HOST" --username="$POSTGRES_USER" --dbname="postgres" -c '\q'; do
    echo "En attente de PostgreSQL..."
    sleep 5
done

echo "🐘 PostgreSQL accessible. Initialisation de la base..."
./init-data.sh "$RDS_HOST" "$POSTGRES_USER" "$POSTGRES_PASSWORD" "$POSTGRES_DB"

echo "🐳 Création du fichier Docker Compose..."
# Creer le Docker Compose file pour n8n
cat <<EOL > docker-compose.yml
version: '3.8'

volumes:
  n8n_storage:
  redis_storage:

services:
  redis:
    image: redis:6-alpine
    restart: always
    volumes:
      - redis_storage:/data
    healthcheck:
      test:
      interval: 5s
      timeout: 5s
      retries: 10

  n8n:
    image: docker.n8n.io/n8nio/n8n
    restart: always
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=$RDS_HOST
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=$POSTGRES_DB
      - DB_POSTGRESDB_USER=$POSTGRES_USER
      - DB_POSTGRESDB_PASSWORD=$POSTGRES_PASSWORD
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_HEALTH_CHECK_ACTIVE=true
      - N8N_BASIC_AUTH_ACTIVE=\${N8N_BASIC_AUTH_ACTIVE}
      - N8N_BASIC_AUTH_USER=\${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=\${N8N_BASIC_AUTH_PASSWORD}
      - DB_POSTGRESDB_SSL_CA=/rds-ca.pem
      - DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false
      - N8N_HOST=$DOMAIN_OR_IP
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://\$DOMAIN_OR_IP\${N8N_PATH}
      - N8N_ENCRYPTION_KEY=\$N8N_ENCRYPTION_KEY
      - N8N_RUNNERS_ENABLED=false
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
    ports:
      - 5678:5678
    volumes:
      - n8n_storage:/home/node/.n8n
      -./rds-ca.pem:/rds-ca.pem
    depends_on:
      - redis

  n8n-worker:
    image: docker.n8n.io/n8nio/n8n
    restart: always
    command: worker
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=$RDS_HOST
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=$POSTGRES_DB
      - DB_POSTGRESDB_USER=$POSTGRES_USER
      - DB_POSTGRESDB_PASSWORD=$POSTGRES_PASSWORD
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_HEALTH_CHECK_ACTIVE=true
      - N8N_ENCRYPTION_KEY=\$N8N_ENCRYPTION_KEY
      - N8N_RUNNERS_ENABLED=false
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
    volumes:
      - n8n_storage:/home/node/.n8n
      -./rds-ca.pem:/rds-ca.pem
    depends_on:
      - redis
      - n8n
EOL

echo ""
echo "================ ETAPE 4/4: DEMARRAGE ET CONFIGURATION WEB ================"
echo "=========================================================================="

# Demarrer n8n
echo "🚀 Démarrage de N8N..."
docker-compose up -d

# Attendre que n8n soit pret
echo "⏳ Attente du démarrage de N8N..."
sleep 30

# Verifier que n8n fonctionne
if curl -f http://localhost:5678 > /dev/null 2>&1; then
    echo "✅ N8N est accessible localement"
else
    echo "❌ Problème: N8N n'est pas accessible localement"
    docker-compose logs n8n
    exit 1
fi

# Corriger l'avertissement Redis (optionnel mais recommandé)
echo "⚙️ Optimisation système Redis..."
sudo sysctl vm.overcommit_memory=1
echo 'vm.overcommit_memory = 1' | sudo tee -a /etc/sysctl.conf

# Quitter le sous-shell newgrp
EOFGRP

echo "🌐 Configuration de Nginx (HTTP temporaire)..."
# Creer config Nginx TEMPORAIRE (sans SSL)
FINAL_NGINX_CONF="/etc/nginx/conf.d/n8n.conf"
sudo tee $FINAL_NGINX_CONF > /dev/null <<EOL
server {
    listen 80;
    server_name $DOMAIN_OR_IP;

    # Configuration optimisée même en HTTP temporaire
    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Support WebSocket
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # Timeouts
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;

        # Buffer settings
        proxy_buffering off;
        proxy_request_buffering off;
    }
}
EOL

# Test & Reload Nginx
sudo nginx -t && sudo systemctl reload nginx

echo "🔒 Installation du certificat SSL..."
# Installer Certbot and obtain SSL certificate
sudo certbot certonly --nginx -d $DOMAIN_OR_IP --non-interactive --agree-tos --email $SSL_EMAIL

# Verifier si le certificat existe (nouveau ou existant)
if; then
    echo "✅ Certificat SSL disponible. Configuration HTTPS..."

    # Activer SSL dans la config Nginx
    sudo tee $FINAL_NGINX_CONF > /dev/null <<EOL
server {
    listen 443 ssl;
    server_name $DOMAIN_OR_IP;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN_OR_IP/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_OR_IP/privkey.pem;

    # Configuration optimisée pour N8N et WebSockets
    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Support WebSocket pour N8N
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # Timeouts optimisés pour éviter les déconnexions
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;

        # Buffer settings pour temps réel
        proxy_buffering off;
        proxy_request_buffering off;
    }
}

server {
    listen 80;
    server_name $DOMAIN_OR_IP;
    return 301 https://\$host\$request_uri;
}
EOL

    # Test & reload Nginx
    sudo nginx -t && sudo systemctl reload nginx
    echo "✅ Configuration HTTPS terminée."
else
    echo "⚠️ Avertissement: Le certificat SSL n'a pas pu être obtenu. N8N reste accessible en HTTP."
fi

echo ""
echo "======================================================================"
echo "================== INSTALLATION COMPLETE TERMINEE =================="
echo "======================================================================"
echo ""
echo "🎉 N8N est maintenant installé et accessible!"
echo ""
echo "✅ N8N accessible à:"
if; then
    echo "  🔒 HTTPS: https://$DOMAIN_OR_IP"
else
    echo "   unsecured HTTP: http://$DOMAIN_OR_IP"
fi
echo ""
echo "📋 CONFIGURATION:"
echo "  - Domaine: $DOMAIN_OR_IP"
echo "  - Email SSL: $SSL_EMAIL"
echo "  - Auth HTTP Basique: $N8N_AUTH_USER / $N8N_AUTH_PASSWORD"
echo ""
echo "🚀 PREMIERE CONNEXION:"
echo "  1. Allez sur https://$DOMAIN_OR_IP"
echo "  2. N8N vous demandera de créer le compte administrateur principal"
echo "  3. Remplissez vos informations (email, nom, prénom, mot de passe)"
echo "  4. Commencez à créer vos workflows!"
echo ""
echo "💡 NOTES:"
echo "  - L'authentification HTTP basique est désactivée par défaut"
echo "  - N8N utilise son propre système d'authentification intégré"
echo "  - Pour activer l'auth HTTP basique: modifiez N8N_BASIC_AUTH_ACTIVE=true dans.env"
echo ""
echo "🛠️ COMMANDES UTILES:"
echo "  - Voir les logs: cd ~/n8n-docker && docker-compose logs n8n"
echo "  - Redémarrer: cd ~/n8n-docker && docker-compose restart"
echo "  - Arrêter: cd ~/n8n-docker && docker-compose down"
echo "  - Démarrer: cd ~/n8n-docker && docker-compose up -d"
echo ""
echo "🗂️ FICHIERS IMPORTANTS:"
echo "  - Configuration: ~/n8n-docker/.env"
echo "  - Docker Compose: ~/n8n-docker/docker-compose.yml"
echo "  - Nginx: /etc/nginx/conf.d/n8n.conf"
echo ""
echo "======================================================================"
echo "Installation terminée!"
