#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx
systemctl enable nginx

cat > /var/www/html/index.html <<'HTML'
<!DOCTYPE html>
<html>
  <head><title>NGINX + Packer</title></head>
  <body>
    <h1>NGINX instalado con Packer</h1>
    <p>AMI importada desde una VM de VirtualBox.</p>
  </body>
</html>
HTML
