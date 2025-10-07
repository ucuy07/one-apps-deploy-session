#!/bin/bash

# Interactive Deployment Script with Health Check
set -e

echo "=================================="
echo "    DevOps Deployment Assistant   "
echo "=================================="

# Function to get user input
get_input() {
    read -p "$1: " input
    echo $input
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Skrip ini harus dijalankan dengan sudo/root"
        exit 1
    fi
}

# Function to create custom docker-compose
create_custom_docker_compose() {
    echo "=== Custom Docker Compose Creator ==="
    echo "Pilih metode pembuatan docker-compose.yml:"
    echo "1. Template dasar"
    echo "2. Template Node.js"
    echo "3. Template Python Flask"
    echo "4. Template React/Static"
    echo "5. Template database (PostgreSQL)"
    echo "6. Input manual (full custom)"
    echo ""
    read -p "Pilih template [1-6]: " template_choice

    case $template_choice in
        1)
            # Basic template
            cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  web:
    image: nginx:latest
    ports:
      - "80:80"
    volumes:
      - .:/usr/share/nginx/html
    restart: unless-stopped
EOF
            ;;
        2)
            # Node.js template
            cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
    volumes:
      - .:/app
      - /app/node_modules
    restart: unless-stopped
    depends_on:
      - db

  db:
    image: postgres:13
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password
    volumes:
      - postgres_/var/lib/postgresql/data
    restart: unless-stopped

volumes:
  postgres_
EOF
            ;;
        3)
            # Python Flask template
            cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  web:
    build: .
    ports:
      - "5000:5000"
    environment:
      - FLASK_ENV=production
    volumes:
      - .:/app
    restart: unless-stopped
    depends_on:
      - redis

  redis:
    image: redis:alpine
    restart: unless-stopped

volumes:
  static_volume:
EOF
            ;;
        4)
            # React/Static template
            cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  web:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - .:/usr/share/nginx/html:ro
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    restart: unless-stopped
EOF
            ;;
        5)
            # PostgreSQL template
            cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  db:
    image: postgres:13
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password
    ports:
      - "5432:5432"
    volumes:
      - postgres_/var/lib/postgresql/data
    restart: unless-stopped

  adminer:
    image: adminer
    ports:
      - "8080:8080"
    restart: unless-stopped

volumes:
  postgres_
EOF
            ;;
        6)
            # Manual input
            echo "=== Manual Docker Compose Input ==="
            echo "Silakan masukkan konten docker-compose.yml (akhiri dengan baris kosong):"
            echo "(Ketik 'END' di baris terakhir untuk selesai)"
            
            > docker-compose.yml  # Create empty file
            while IFS= read -r line; do
                if [[ "$line" == "END" ]]; then
                    break
                fi
                echo "$line" >> docker-compose.yml
            done
            ;;
        *)
            echo "Pilihan tidak valid!"
            return 1
            ;;
    esac

    echo "docker-compose.yml telah dibuat:"
    echo "----------------------------------------"
    cat docker-compose.yml
    echo "----------------------------------------"
    
    # Ask if user wants to edit
    read -p "Apakah kamu ingin mengedit file? (y/n): " edit_choice
    if [[ $edit_choice == "y" || $edit_choice == "Y" ]]; then
        if command -v nano &> /dev/null; then
            nano docker-compose.yml
        elif command -v vim &> /dev/null; then
            vim docker-compose.yml
        else
            echo "Editor tidak ditemukan, kamu bisa edit manual nanti"
        fi
    fi
}

# Function to create app directory
create_app_directory() {
    echo "=== App Directory Setup ==="
    APP_NAME=$(get_input "Nama aplikasi (akan menjadi nama direktori)")
    
    # Create app directory if it doesn't exist
    if [ ! -d "$APP_NAME" ]; then
        mkdir -p "$APP_NAME"
        echo "Direktori aplikasi '$APP_NAME' dibuat"
    else
        echo "Direktori '$APP_NAME' sudah ada"
    fi
    
    # Change to app directory
    cd "$APP_NAME"
    echo "Berada di direktori: $(pwd)"
    
    return 0
}

# Function to check application health
check_health() {
    echo "=== Health Check ==="
    
    if [ ! -f "docker-compose.yml" ]; then
        echo "docker-compose.yml tidak ditemukan di direktori saat ini!"
        return 1
    fi
    
    echo "Mengecek status docker-compose..."
    docker-compose ps
    
    echo ""
    echo "Mengecek status container..."
    docker-compose ps --format "table {{.Name}}\t{{.State}}\t{{.Status}}"
    
    # Get container names and check if they're running
    CONTAINERS=$(docker-compose ps --format "{{.Name}}")
    if [ -n "$CONTAINERS" ]; then
        echo ""
        echo "Detail status container:"
        for container in $CONTAINERS; do
            echo "Container: $container"
            docker inspect --format='{{.State.Status}}' $container 2>/dev/null || echo "Tidak ditemukan"
            echo ""
        done
    fi
    
    # Check if any ports are exposed and accessible
    echo "Mengecek port yang terbuka..."
    if command -v netstat &> /dev/null; then
        netstat -tuln | grep -E ':(80|443|3000|5000|8080)'
    elif command -v ss &> /dev/null; then
        ss -tuln | grep -E ':(80|443|3000|5000|8080)'
    fi
    
    # Check nginx status if configuration exists
    echo ""
    echo "Mengecek status nginx..."
    if systemctl is-active --quiet nginx; then
        echo "✓ Nginx: Running"
    else
        echo "✗ Nginx: Not Running"
    fi
    
    # Test web accessibility if nginx config exists
    NGINX_CONF="/etc/nginx/conf.d/$(basename $(pwd)).conf"
    if [ -f "$NGINX_CONF" ]; then
        echo ""
        echo "Mengecek konfigurasi nginx..."
        nginx -t 2>/dev/null && echo "✓ Konfigurasi nginx: OK" || echo "✗ Konfigurasi nginx: Error"
    fi
    
    # Check SSL certificates if they exist
    DOMAINS=$(grep -oP 'server_name \K[^;]*' /etc/nginx/conf.d/$(basename $(pwd)).conf 2>/dev/null || true)
    if [ -n "$DOMAINS" ]; then
        for domain in $DOMAINS; do
            if [ "$domain" != "www.$(basename $(pwd))" ] && [ "$domain" != "$(basename $(pwd))" ]; then
                continue
            fi
            CERT_PATH="/etc/letsencrypt/live/$domain/fullchain.pem"
            if [ -f "$CERT_PATH" ]; then
                echo "✓ SSL Certificate for $domain: OK"
                # Show certificate expiration
                EXPIRY=$(openssl x509 -in $CERT_PATH -noout -enddate | cut -d= -f2)
                echo "  Certificate expires: $EXPIRY"
            else
                echo "✗ SSL Certificate for $domain: Not found"
            fi
        done
    fi
}

# Function to check specific port
check_port_health() {
    read -p "Port yang ingin dicek (contoh: 3000): " PORT
    echo "Mengecek port $PORT..."
    
    if netstat -tuln | grep -q ":$PORT "; then
        echo "✓ Port $PORT: Open"
        # Try to curl the port if it's a web service
        if curl -s -f -m 5 http://localhost:$PORT > /dev/null 2>&1; then
            echo "✓ Service on port $PORT: Responding"
        else
            echo "✗ Service on port $PORT: Not responding"
        fi
    else
        echo "✗ Port $PORT: Closed"
    fi
}

# Main menu
show_menu() {
    echo ""
    echo "Pilih tindakan yang ingin dilakukan:"
    echo "1. Deploy aplikasi baru (dengan direktori)"
    echo "2. Deploy aplikasi di direktori yang ada"
    echo "3. Setup Nginx web server (conf.d)"
    echo "4. Generate SSL certificate (Let's Encrypt)"
    echo "5. Setup auto renewal SSL certificate"
    echo "6. Full deployment (semua di atas)"
    echo "7. Health check aplikasi"
    echo "8. Health check port spesifik"
    echo "9. Cek status nginx"
    echo "10. Restart nginx"
    echo "11. Lihat docker-compose.yml saat ini"
    echo "12. Edit docker-compose.yml"
    echo "13. Lihat daftar aplikasi yang ada"
    echo "14. Pindah ke direktori aplikasi"
    echo "15. Keluar"
    echo ""
    read -p "Masukkan pilihan [1-15]: " choice
}

# Deploy Docker Compose
deploy_docker() {
    echo "=== Docker Compose Deployment ==="
    
    # Ask if user wants to create new directory or use existing
    echo "Pilih direktori aplikasi:"
    echo "1. Buat direktori baru"
    echo "2. Gunakan direktori yang sudah ada"
    read -p "Pilih [1-2]: " dir_choice
    
    if [[ $dir_choice == "1" ]]; then
        create_app_directory
    else
        # List existing directories
        echo "Daftar direktori aplikasi yang tersedia:"
        ls -d */ 2>/dev/null || echo "Tidak ada direktori aplikasi"
        
        APP_NAME=$(get_input "Masukkan nama direktori aplikasi")
        if [ -d "$APP_NAME" ]; then
            cd "$APP_NAME"
            echo "Berada di direktori: $(pwd)"
        else
            echo "Direktori tidak ditemukan, membuat direktori baru..."
            create_app_directory
        fi
    fi
    
    # Check if docker-compose.yml exists in current directory
    if [ -f "docker-compose.yml" ]; then
        echo "File docker-compose.yml ditemukan:"
        echo "----------------------------------------"
        head -20 docker-compose.yml  # Show first 20 lines
        if [ $(wc -l < docker-compose.yml) -gt 20 ]; then
            echo "... (dan $(($(wc -l < docker-compose.yml) - 20)) baris lainnya)"
        fi
        echo "----------------------------------------"
        
        read -p "Gunakan file ini? (y/n): " use_existing
        if [[ $use_existing != "y" && $use_existing != "Y" ]]; then
            create_custom_docker_compose
        fi
    else
        create_custom_docker_compose
    fi
    
    echo "Menjalankan docker-compose up..."
    docker-compose up -d
    
    if [ $? -eq 0 ]; then
        echo "Deployment Docker selesai!"
        echo "Aplikasi berjalan di direktori: $(pwd)"
        echo ""
        echo "Melakukan health check setelah deployment..."
        sleep 3  # Wait a bit for services to start
        check_health
    else
        echo "Deployment gagal, cek konfigurasi docker-compose.yml"
        cd ..  # Go back to parent directory
        return 1
    fi
}

# Setup Nginx in conf.d
setup_nginx() {
    echo "=== Setting up Nginx (conf.d) ==="
    check_root
    
    # Get current directory name as default app name
    CURRENT_DIR=$(basename $(pwd))
    read -p "Domain name (default: $CURRENT_DIR): " DOMAIN
    if [ -z "$DOMAIN" ]; then
        DOMAIN=$CURRENT_DIR
    fi
    
    BACKEND_PORT=$(get_input "Backend port (contoh: 3000)")
    
    # Create Nginx config in conf.d
    NGINX_CONF="/etc/nginx/conf.d/$DOMAIN.conf"
    cat > $NGINX_CONF << EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    
    location / {
        proxy_pass http://localhost:$BACKEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
    
    # Logging
    access_log /var/log/nginx/$DOMAIN.access.log;
    error_log /var/log/nginx/$DOMAIN.error.log;
}
EOF
    
    echo "Testing konfigurasi nginx..."
    nginx -t
    
    if [ $? -eq 0 ]; then
        echo "Konfigurasi OK, mereload nginx..."
        systemctl reload nginx
        echo "Nginx setup selesai di: $NGINX_CONF"
    else
        echo "Error dalam konfigurasi nginx, membatalkan..."
        rm $NGINX_CONF
        return 1
    fi
}

# Generate SSL
generate_ssl() {
    echo "=== Generating SSL Certificate ==="
    check_root
    
    # Get current directory name as default domain
    CURRENT_DIR=$(basename $(pwd))
    read -p "Domain name (default: $CURRENT_DIR): " DOMAIN
    if [ -z "$DOMAIN" ]; then
        DOMAIN=$CURRENT_DIR
    fi
    
    if ! command -v certbot &> /dev/null; then
        echo "Menginstall certbot..."
        apt-get update && apt-get install -y certbot python3-certbot-nginx
    fi
    
    # Backup existing config first
    NGINX_CONF="/etc/nginx/conf.d/$DOMAIN.conf"
    if [ -f "$NGINX_CONF" ]; then
        cp $NGINX_CONF $NGINX_CONF.backup.$(date +%Y%m%d)
    fi
    
    # Run certbot
    certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email your-email@example.com
    
    if [ $? -eq 0 ]; then
        echo "SSL certificate generated successfully!"
    else
        echo "SSL generation failed!"
        # Restore backup if failed
        if [ -f "$NGINX_CONF.backup.$(date +%Y%m%d)" ]; then
            mv $NGINX_CONF.backup.$(date +%Y%m%d) $NGINX_CONF
        fi
        return 1
    fi
}

# Setup auto renewal
setup_auto_renewal() {
    echo "=== Setting up Auto Renewal ==="
    check_root
    
    # Add cron job for auto renewal
    (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -
    
    echo "Auto renewal setup selesai!"
    echo "Cron job ditambahkan untuk menjalankan setiap hari jam 12 siang"
}

# Check nginx status
check_nginx_status() {
    echo "=== Nginx Status ==="
    systemctl status nginx --no-pager
}

# Restart nginx
restart_nginx() {
    echo "=== Restarting Nginx ==="
    check_root
    systemctl reload nginx
    echo "Nginx direload!"
}

# View docker-compose.yml
view_docker_compose() {
    if [ -f "docker-compose.yml" ]; then
        echo "=== Current docker-compose.yml ==="
        echo "----------------------------------------"
        cat docker-compose.yml
        echo "----------------------------------------"
    else
        echo "docker-compose.yml tidak ditemukan di direktori saat ini!"
    fi
}

# Edit docker-compose.yml
edit_docker_compose() {
    if [ -f "docker-compose.yml" ]; then
        if command -v nano &> /dev/null; then
            nano docker-compose.yml
        elif command -v vim &> /dev/null; then
            vim docker-compose.yml
        else
            echo "Editor tidak ditemukan"
        fi
    else
        echo "docker-compose.yml tidak ditemukan di direktori saat ini!"
    fi
}

# List applications
list_applications() {
    echo "=== Daftar Aplikasi ==="
    echo "Direktori saat ini: $(pwd)"
    echo "Aplikasi yang ditemukan:"
    for dir in */; do
        if [ -f "$dir/docker-compose.yml" ]; then
            echo "  - ${dir%/} (ada docker-compose.yml)"
        else
            echo "  - ${dir%/}"
        fi
    done
}

# Change to application directory
change_app_directory() {
    echo "=== Pindah ke Direktori Aplikasi ==="
    list_applications
    
    APP_NAME=$(get_input "Masukkan nama direktori aplikasi")
    if [ -d "$APP_NAME" ]; then
        cd "$APP_NAME"
        echo "Berhasil pindah ke direktori: $(pwd)"
    else
        echo "Direktori tidak ditemukan!"
    fi
}

# Main loop
while true; do
    show_menu
    case $choice in
        1) deploy_docker ;;
        2) 
            # Use existing directory without creating new one
            change_app_directory
            # Now deploy in the selected directory
            if [ -f "docker-compose.yml" ]; then
                echo "Menjalankan docker-compose up..."
                docker-compose up -d
                echo "Deployment selesai!"
            else
                echo "docker-compose.yml tidak ditemukan, membuat template baru..."
                create_custom_docker_compose
                echo "Menjalankan docker-compose up..."
                docker-compose up -d
                echo "Deployment selesai!"
            fi
            ;;
        3) setup_nginx ;;
        4) generate_ssl ;;
        5) setup_auto_renewal ;;
        6) 
            deploy_docker
            setup_nginx
            generate_ssl
            setup_auto_renewal
            echo "Full deployment selesai!"
            ;;
        7) check_health ;;
        8) check_port_health ;;
        9) check_nginx_status ;;
        10) restart_nginx ;;
        11) view_docker_compose ;;
        12) edit_docker_compose ;;
        13) list_applications ;;
        14) change_app_directory ;;
        15) 
            echo "Terima kasih!"
            exit 0
            ;;
        *) 
            echo "Pilihan tidak valid!"
            ;;
    esac
done