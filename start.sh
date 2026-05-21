#!/bin/bash

set -e

APP_DIR="/home/ec2-user/hospital-backend/hospital-backend"
DOMAIN="${domain_name}"

sudo yum update -y

if ! command -v docker &> /dev/null; then
    sudo yum install -y docker
fi

# Required packages
sudo yum install -y git python3 python3-pip tar gcc make bind-utils expect cronie

sudo systemctl enable docker
sudo systemctl start docker

sudo usermod -aG docker ec2-user || true

DOCKER_COMPOSE_VERSION="v2.27.0"

if ! docker compose version &> /dev/null; then
    sudo mkdir -p /usr/local/lib/docker/cli-plugins

    sudo curl -SL \
    https://github.com/docker/compose/releases/download/$${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64 \
    -o /usr/local/lib/docker/cli-plugins/docker-compose

    sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi

if ! command -v nginx &> /dev/null; then
    sudo yum install -y nginx
fi

sudo systemctl enable crond
sudo systemctl start crond

sudo python3 -m venv /opt/certbot
sudo /opt/certbot/bin/pip install --upgrade pip
sudo /opt/certbot/bin/pip install certbot certbot-nginx
sudo ln -sf /opt/certbot/bin/certbot /usr/local/bin/certbot

sudo systemctl enable nginx
sudo systemctl start nginx

sudo mkdir -p $${APP_DIR}
sudo mkdir -p /opt/prometheus
sudo mkdir -p /etc/cron.d
sudo mkdir -p /opt/promtail
sudo mkdir -p /opt/grafana/provisioning/datasources
sudo mkdir -p /opt/grafana/provisioning/dashboards

cat > /opt/promtail/promtail.yml <<EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s

    relabel_configs:
      - source_labels: [__meta_docker_container_name]
        target_label: container
EOF

cat > $${APP_DIR}/.env <<EOF
IMAGE_TAG=latest
GRAFANA_ADMIN_PASSWORD=${grafana_password}
GRAFANA_ADMIN_USER=${grafana_user}
EOF

cat > $${APP_DIR}/docker-compose.yml <<EOF
services:
  backend:
    image: kstkaan/hospital-backend:latest
    container_name: hospital-backend
    restart: always
    ports:
      - "8080:8080"
    environment:
      ConnectionStrings__DefaultConnection: "${connection_string}"
    networks:
      - elastic

  frontend:
    image: kstkaan/hospital-frontend:latest
    container_name: hospital-frontend
    restart: always
    ports:
      - "3000:8080"
    depends_on:
      - backend
    networks:
      - elastic

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: always
    dns:
      - 127.0.0.11
    volumes:
      - /opt/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
    ports:
      - "127.0.0.1:9091:9090"
    networks:
      - elastic

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: always
    volumes:
      - grafana_data:/var/lib/grafana
      - /opt/grafana/provisioning/datasources:/etc/grafana/provisioning/datasources
      - /opt/grafana/provisioning/dashboards:/etc/grafana/provisioning/dashboards
      - /opt/grafana/dashboards:/var/lib/grafana/dashboards
    environment:
      GF_SECURITY_ADMIN_USER: "${grafana_user}"
      GF_SECURITY_ADMIN_PASSWORD: "${grafana_password}"
      GF_SERVER_DOMAIN: "$${DOMAIN}"
      GF_SERVER_ROOT_URL: "https://$${DOMAIN}/grafana/"
      GF_SERVER_SERVE_FROM_SUB_PATH: "true"
      GF_SECURITY_COOKIE_SAMESITE: "disabled"
    ports:
      - "127.0.0.1:3001:3000"
    networks:
      - elastic

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: always
    ports:
      - "127.0.0.1:8081:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    networks:
      - elastic

  loki:
    image: grafana/loki:latest
    container_name: loki
    restart: always
    ports:
      - "127.0.0.1:3100:3100"
    networks:
      - elastic

  promtail:
    image: grafana/promtail:latest
    container_name: promtail
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/log:/var/log:ro
      - /opt/promtail/promtail.yml:/etc/promtail/config.yml
    command: -config.file=/etc/promtail/config.yml
    networks:
      - elastic

  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --cleanup --interval 300
    networks:
      - elastic

volumes:
  prometheus_data:
  grafana_data:

networks:
  elastic:
    name: elastic
    driver: bridge
EOF

cat > /opt/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 1m

scrape_configs:
  - job_name: "backend"
    metrics_path: /metrics
    fallback_scrape_protocol: PrometheusText0.0.4
    static_configs:
      - targets: ["hospital-backend:8080"]

  - job_name: "cadvisor"
    static_configs:
      - targets: ["cadvisor:8080"]

  - job_name: "prometheus"
    metrics_path: /prometheus/metrics
    static_configs:
      - targets: ["prometheus:9090"]
EOF

cat > /opt/grafana/provisioning/datasources/datasources.yml <<EOF
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
EOF

# Grafana dashboards
sudo rm -rf /opt/grafana/dashboards
sudo git clone https://github.com/KaanMyumyun/grafanadashboards.git /opt/grafana/dashboards

# Remove old exported folder UID fields from dashboard JSON files
sudo sed -i '/"folderUid":/d; /"folderUID":/d' /opt/grafana/dashboards/*.json

cat > /opt/grafana/provisioning/dashboards/dashboards.yml <<EOF
apiVersion: 1

providers:
  - name: default
    orgId: 1
    folder: Hospital System
    folderUid: afmm2euro67lsf
    type: file
    disableDeletion: false
    editable: true
    allowUiUpdates: true
    updateIntervalSeconds: 10
    options:
      path: /var/lib/grafana/dashboards
EOF

sudo tee /etc/nginx/conf.d/hospital.conf > /dev/null <<EOF
server {
    server_name $${DOMAIN};

    location /api/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location = /grafana {
        return 301 /grafana/;
    }

    location /grafana/ {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Server \$host;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location = /prometheus {
        return 301 /prometheus/;
    }

    location /prometheus/ {
        proxy_pass http://127.0.0.1:9091/prometheus/;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    listen 80;
}
EOF

sudo nginx -t
sudo systemctl restart nginx

if ! command -v noip2 &> /dev/null; then
    cd /tmp
    curl -LO https://www.noip.com/client/linux/noip-duc-linux.tar.gz
    tar xf noip-duc-linux.tar.gz
    cd noip-2.*
    make
    sudo cp noip2 /usr/local/bin/noip2
    sudo mkdir -p /usr/local/etc
fi

sudo /usr/local/bin/noip2 -K -c /usr/local/etc/no-ip2.conf 2>/dev/null || true
sudo rm -f /usr/local/etc/no-ip2.conf

cat > /tmp/noip2_config.exp <<'EOF'
#!/usr/bin/expect -f

set timeout 120

set email [lindex $argv 0]
set password [lindex $argv 1]

spawn /usr/local/bin/noip2 -C -c /usr/local/etc/no-ip2.conf

expect {
    -re "Please select.*" {
        send "0\r"
        exp_continue
    }

    -re "Please enter the login/email.*" {
        send "$email\r"
        exp_continue
    }

    -re "Please enter the password.*" {
        send "$password\r"
        exp_continue
    }

    -re "Please enter an update interval.*" {
        send "30\r"
        exp_continue
    }

    -re "Do you wish to run something at successful update.*" {
        send "n\r"
        exp_continue
    }

    -re "Only one host.*registered.*" {
        exp_continue
    }

    -re "Please select the host.*" {
        send "1\r"
        exp_continue
    }

    -re "Please enter the number.*" {
        send "1\r"
        exp_continue
    }

    eof
}
EOF

chmod +x /tmp/noip2_config.exp

sudo /tmp/noip2_config.exp "${noip_email}" "${noip_password}" || true

if ! sudo test -f /usr/local/etc/no-ip2.conf; then
    echo "WARNING: no-ip2.conf not created, skipping noip2 setup"
else
    sudo chmod 600 /usr/local/etc/no-ip2.conf
    sudo /usr/local/bin/noip2 -c /usr/local/etc/no-ip2.conf || true
fi

CURRENT_IP=$(curl -s http://checkip.amazonaws.com | tr -d '\n')

echo "Instance IP: $${CURRENT_IP} — waiting for $${DOMAIN} to resolve to it..."

for i in $(seq 1 60); do
    RESOLVED=$(dig +short "$${DOMAIN}" @8.8.8.8 \
        | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print; exit }' || true)

    echo "[$${i}/60] $${DOMAIN} -> $${RESOLVED:-<pending>}"

    if [ "$${RESOLVED}" = "$${CURRENT_IP}" ]; then
        echo "DNS propagated."
        break
    fi

    sleep 10
done

sudo certbot --nginx \
    -d $${DOMAIN} \
    --non-interactive \
    --agree-tos \
    -m ${certbot_email} \
    --redirect || true

echo "0 0,12 * * * root /opt/certbot/bin/certbot renew --quiet" \
    | sudo tee /etc/cron.d/certbot-renew > /dev/null

sudo systemctl enable crond
sudo systemctl restart crond

sudo tee /etc/systemd/system/noip2.service > /dev/null <<'EOF'
[Unit]
Description=No-IP Dynamic DNS Update Client
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=/usr/local/bin/noip2 -c /usr/local/etc/no-ip2.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/hospital-stack.service > /dev/null <<EOF
[Unit]
Description=Hospital Docker Stack
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$${APP_DIR}

ExecStart=/usr/bin/docker compose pull
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down

TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

sudo systemctl enable noip2
sudo systemctl start noip2 || true

sudo systemctl enable hospital-stack

cd $${APP_DIR}

sudo docker compose down -v || true
sudo docker compose pull
sudo docker compose up -d

sudo systemctl enable docker
sudo systemctl enable nginx
sudo systemctl enable hospital-stack

sudo docker ps
