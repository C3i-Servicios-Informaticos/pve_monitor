#!/bin/bash

# Colores para mensajes
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AMARILLO='\033[1;33m'
AZUL='\033[0;34m'
NORMAL='\033[0m'

# Función para imprimir mensajes con colores
mensaje() {
    case $1 in
        "info") echo -e "${AZUL}[INFO]${NORMAL} $2" ;;
        "ok") echo -e "${VERDE}[OK]${NORMAL} $2" ;;
        "error") echo -e "${ROJO}[ERROR]${NORMAL} $2" ;;
        "aviso") echo -e "${AMARILLO}[AVISO]${NORMAL} $2" ;;
    esac
}

# Función para verificar si un comando existe
verificar_comando() {
    if ! command -v $1 &> /dev/null; then
        mensaje "error" "El comando $1 no está instalado."
        return 1
    else
        return 0
    fi
}

# Función para verificar y mostrar el estado de instalación
verificar_instalacion() {
    if [ -d "$1" ]; then
        mensaje "ok" "$2 ya está instalado."
        return 0
    else
        return 1
    fi
}

# Función para pedir el token de Telegram
pedir_token_telegram() {
    echo -e "${AZUL}[?]${NORMAL} Por favor, introduce el token del bot de Telegram: "
    read BOT_TOKEN
    if [ -z "$BOT_TOKEN" ]; then
        mensaje "error" "El token no puede estar vacío"
        pedir_token_telegram
    else
        mensaje "ok" "Token guardado: $BOT_TOKEN"
    fi
}

# Función para pedir el ID del chat de Telegram
pedir_chat_id() {
    echo -e "${AZUL}[?]${NORMAL} Por favor, introduce el ID del chat de Telegram: "
    read CHAT_ID
    if [ -z "$CHAT_ID" ]; then
        mensaje "error" "El ID del chat no puede estar vacío"
        pedir_chat_id
    else
        mensaje "ok" "ID del chat guardado: $CHAT_ID"
    fi
}

# Función para reemplazar tokens en un archivo
reemplazar_token() {
    local archivo=$1
    
    # Asegurarse de que el archivo existe
    if [ ! -f "$archivo" ]; then
        mensaje "error" "El archivo $archivo no existe"
        return 1
    fi
    
    # Verificar el formato actual de BOT_TOKEN y CHAT_ID en el archivo
    if grep -q 'BOT_TOKEN=""' "$archivo"; then
        # Formato BOT_TOKEN=""
        sed -i "s|BOT_TOKEN=\"\"|BOT_TOKEN=\"$BOT_TOKEN\"|g" "$archivo"
    elif grep -q 'BOT_TOKEN=' "$archivo"; then
        # Formato BOT_TOKEN= (sin comillas)
        sed -i "s|BOT_TOKEN=|BOT_TOKEN=\"$BOT_TOKEN\"|g" "$archivo"
    fi
    
    if grep -q 'CHAT_ID=""' "$archivo"; then
        # Formato CHAT_ID=""
        sed -i "s|CHAT_ID=\"\"|CHAT_ID=\"$CHAT_ID\"|g" "$archivo"
    elif grep -q 'CHAT_ID=' "$archivo"; then
        # Formato CHAT_ID= (sin comillas)
        sed -i "s|CHAT_ID=|CHAT_ID=\"$CHAT_ID\"|g" "$archivo"
    fi
    
    # Para multi-action.sh, que podría usar TELEGRAM prefijo
    if grep -q 'TELEGRAM_BOT_TOKEN=""' "$archivo"; then
        sed -i "s|TELEGRAM_BOT_TOKEN=\"\"|TELEGRAM_BOT_TOKEN=\"$BOT_TOKEN\"|g" "$archivo"
    elif grep -q 'TELEGRAM_BOT_TOKEN=' "$archivo"; then
        sed -i "s|TELEGRAM_BOT_TOKEN=|TELEGRAM_BOT_TOKEN=\"$BOT_TOKEN\"|g" "$archivo"
    fi
    
    if grep -q 'TELEGRAM_CHAT_ID=""' "$archivo"; then
        sed -i "s|TELEGRAM_CHAT_ID=\"\"|TELEGRAM_CHAT_ID=\"$CHAT_ID\"|g" "$archivo"
    elif grep -q 'TELEGRAM_CHAT_ID=' "$archivo"; then
        sed -i "s|TELEGRAM_CHAT_ID=|TELEGRAM_CHAT_ID=\"$CHAT_ID\"|g" "$archivo"
    fi
    
    mensaje "ok" "Tokens reemplazados en $archivo"
}

# Función para crear el filtro Proxmox para fail2ban
crear_filtro_proxmox() {
    local filtro_path="/etc/fail2ban/filter.d/proxmox.conf"
    
    # Crear el archivo de filtro para Proxmox
    cat > "$filtro_path" << EOF
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
            pveproxy\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
EOF

    if [ -f "$filtro_path" ]; then
        chmod 644 "$filtro_path"
        mensaje "ok" "Filtro Proxmox para fail2ban creado correctamente"
        return 0
    else
        mensaje "error" "No se pudo crear el filtro Proxmox para fail2ban"
        return 1
    fi
}

# Verificar si se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    mensaje "error" "Este script debe ejecutarse como root"
    exit 1
fi

clear
echo "==========================================================="
echo "          INSTALADOR DE SISTEMA PXE MONITOR"
echo "==========================================================="
echo ""
mensaje "info" "Este script instalará y configurará el sistema pxe_monitor"
echo ""

# Comprobar dependencias
mensaje "info" "Comprobando dependencias..."
DEPS_MISSING=0

for dep in git jq curl grep awk sed; do
    if ! verificar_comando $dep; then
        DEPS_MISSING=1
    fi
done

# Verificar fail2ban de manera diferente ya que no es un comando binario
if ! dpkg -l | grep -q "fail2ban"; then
    DEPS_MISSING=1
    mensaje "error" "Fail2ban no está instalado."
fi

if [ $DEPS_MISSING -eq 1 ]; then
    mensaje "info" "Instalando dependencias faltantes..."
    apt update
    apt install -y git jq fail2ban curl
    
    # Verificar si se instalaron correctamente
    if ! verificar_comando git || ! verificar_comando jq || ! verificar_comando curl; then
        mensaje "error" "No se pudieron instalar algunas dependencias. Por favor, instálalas manualmente."
        exit 1
    fi
    
    # Verificar fail2ban nuevamente
    if ! dpkg -l | grep -q "fail2ban"; then
        mensaje "error" "Fail2ban no se pudo instalar. Por favor, instálalo manualmente."
        exit 1
    fi
    
    mensaje "ok" "Dependencias instaladas correctamente"
else
    mensaje "ok" "Todas las dependencias están instaladas"
fi

# Crear directorio principal si no existe
if [ ! -d "/etc/pxe_monitor" ]; then
    mkdir -p /etc/pxe_monitor
    mkdir -p /etc/pxe_monitor/pxe_backup
    mkdir -p /etc/pxe_monitor/pxe_bruteforce
    mkdir -p /etc/pxe_monitor/pxe_vm
    mkdir -p /etc/pxe_monitor/ssh
    mensaje "ok" "Directorios creados correctamente"
else
    mensaje "aviso" "El directorio /etc/pxe_monitor ya existe"
fi

# Clonar el repositorio de GitHub
mensaje "info" "Clonando repositorio desde GitHub..."
REPO_DIR="./pxe_monitor"
# Eliminar directorio si ya existe
if [ -d "$REPO_DIR" ]; then
    rm -rf "$REPO_DIR"
fi

if git clone https://github.com/C3i-Servicios-Informaticos/pxe_monitor.git "$REPO_DIR"; then
    mensaje "ok" "Repositorio clonado correctamente"
else
    mensaje "error" "No se pudo clonar el repositorio. Saliendo..."
    exit 1
fi

# Solicitar información de Telegram
echo ""
mensaje "info" "Configuración de Telegram"
BOT_TOKEN=""
CHAT_ID=""
pedir_token_telegram
pedir_chat_id
echo ""

# Verificar que los tokens se ingresaron correctamente
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    mensaje "error" "No se ingresaron correctamente los datos de Telegram. Por favor, ejecuta el script nuevamente."
    exit 1
fi

# Función para copiar y configurar un archivo
copiar_configurar_archivo() {
    local origen=$1
    local destino=$2
    local nombre_archivo=$(basename "$origen")
    
    cp "$origen" "$destino"
    
    # Si es un script, darle permisos de ejecución
    if [[ "$nombre_archivo" == *.sh ]]; then
        chmod +x "$destino/$nombre_archivo"
    fi
    
    # Reemplazar tokens en el archivo
    reemplazar_token "$destino/$nombre_archivo"
}

# Copiando los archivos desde el repositorio clonado
mensaje "info" "Copiando y configurando archivos..."

# Backup
copiar_configurar_archivo "$REPO_DIR/pxe_backup/bak_deal.sh" "/etc/pxe_monitor/pxe_backup"
cp "$REPO_DIR/pxe_backup/backup_fail.service" "/etc/pxe_monitor/pxe_backup/"

# Bruteforce
copiar_configurar_archivo "$REPO_DIR/pxe_bruteforce/multi-action.sh" "/etc/pxe_monitor/pxe_bruteforce"
cp "$REPO_DIR/pxe_bruteforce/jail.local" "/etc/pxe_monitor/pxe_bruteforce/"
cp "$REPO_DIR/pxe_bruteforce/telegram.conf" "/etc/pxe_monitor/pxe_bruteforce/"

# VM Monitoring
copiar_configurar_archivo "$REPO_DIR/pxe_vm/ping-instances.sh" "/etc/pxe_monitor/pxe_vm"
cp "$REPO_DIR/pxe_vm/vm_fail.service" "/etc/pxe_monitor/pxe_vm/"

# SSH Monitoring
copiar_configurar_archivo "$REPO_DIR/ssh/ssh_monitor.sh" "/etc/pxe_monitor/ssh"

# Limpiar directorio del repositorio
rm -rf "$REPO_DIR"
mensaje "ok" "Archivos copiados y directorio del repositorio eliminado"

# Configurar fail2ban
mensaje "info" "Configurando fail2ban..."

# Crear filtro Proxmox para fail2ban (NUEVO)
crear_filtro_proxmox

# Crear acción personalizada para fail2ban
if [ -f "/etc/pxe_monitor/pxe_bruteforce/telegram.conf" ]; then
    cp /etc/pxe_monitor/pxe_bruteforce/telegram.conf /etc/fail2ban/action.d/telegram.conf
    # Actualizar la ruta del script multi-action.sh en la configuración
    sed -i "s|/root/multi-action.sh|/etc/pxe_monitor/pxe_bruteforce/multi-action.sh|g" /etc/fail2ban/action.d/telegram.conf
    mensaje "ok" "Acción de Telegram configurada para fail2ban"
fi

# Configurar jail local
if [ -f "/etc/pxe_monitor/pxe_bruteforce/jail.local" ]; then
    cp /etc/pxe_monitor/pxe_bruteforce/jail.local /etc/fail2ban/jail.d/proxmox.conf
    mensaje "ok" "Configuración de jail para Proxmox añadida"
fi

# Asegurar que los permisos de los archivos de configuración son correctos
chmod 644 /etc/fail2ban/jail.d/proxmox.conf
chmod 644 /etc/fail2ban/action.d/telegram.conf

# Verificar y corregir permisos de los scripts
chmod +x /etc/pxe_monitor/pxe_backup/bak_deal.sh
chmod +x /etc/pxe_monitor/pxe_bruteforce/multi-action.sh
chmod +x /etc/pxe_monitor/pxe_vm/ping-instances.sh
chmod +x /etc/pxe_monitor/ssh/ssh_monitor.sh

# Reiniciar fail2ban
systemctl restart fail2ban
# Esperamos un momento para que fail2ban se inicie correctamente
sleep 3
if systemctl is-active --quiet fail2ban; then
    mensaje "ok" "Servicio fail2ban reiniciado correctamente"
else
    mensaje "error" "No se pudo reiniciar el servicio fail2ban"
    # Mostrar log de error
    echo "Mostrando los logs de fail2ban:"
    journalctl -u fail2ban -n 10
fi

# Configurar servicios systemd
mensaje "info" "Configurando servicios..."

# Servicio de backup
if [ -f "/etc/pxe_monitor/pxe_backup/backup_fail.service" ]; then
    # Actualizar la ruta en el archivo de servicio
    sed -i "s|ExecStart=.*|ExecStart=/etc/pxe_monitor/pxe_backup/bak_deal.sh|g" /etc/pxe_monitor/pxe_backup/backup_fail.service
    cp /etc/pxe_monitor/pxe_backup/backup_fail.service /etc/systemd/system/
    chmod 644 /etc/systemd/system/backup_fail.service
    systemctl daemon-reload
    systemctl enable backup_fail.service
    systemctl start backup_fail.service
    # Esperamos un momento para que el servicio se inicie correctamente
    sleep 2
    if systemctl is-active --quiet backup_fail.service; then
        mensaje "ok" "Servicio de backup configurado y activado"
    else
        mensaje "error" "No se pudo iniciar el servicio de backup"
        # Mostrar log de error
        echo "Mostrando los logs del servicio backup_fail:"
        journalctl -u backup_fail.service -n 10
    fi
fi

# Servicio de monitoreo de VMs
if [ -f "/etc/pxe_monitor/pxe_vm/vm_fail.service" ]; then
    # Actualizar la ruta en el archivo de servicio
    sed -i "s|ExecStart=.*|ExecStart=/etc/pxe_monitor/pxe_vm/ping-instances.sh|g" /etc/pxe_monitor/pxe_vm/vm_fail.service
    cp /etc/pxe_monitor/pxe_vm/vm_fail.service /etc/systemd/system/
    chmod 644 /etc/systemd/system/vm_fail.service
    systemctl daemon-reload
    systemctl enable vm_fail.service
    systemctl start vm_fail.service
    # Esperamos un momento para que el servicio se inicie correctamente
    sleep 2
    if systemctl is-active --quiet vm_fail.service; then
        mensaje "ok" "Servicio de monitoreo de VMs configurado y activado"
    else
        mensaje "error" "No se pudo iniciar el servicio de monitoreo de VMs"
        # Mostrar log de error
        echo "Mostrando los logs del servicio vm_fail:"
        journalctl -u vm_fail.service -n 10
    fi
fi

# Configurar crontab para ssh_monitor
mensaje "info" "Configurando cron para monitoreo SSH..."
(crontab -l 2>/dev/null || echo "") | grep -v "/etc/pxe_monitor/ssh/ssh_monitor.sh" | { cat; echo "*/2 * * * * /etc/pxe_monitor/ssh/ssh_monitor.sh"; } | crontab -
mensaje "ok" "Tarea cron para monitoreo SSH configurada"

# Verificar instalación
echo ""
mensaje "info" "Verificando la instalación..."

# Verificar servicios
if systemctl is-active --quiet backup_fail.service; then
    mensaje "ok" "Servicio backup_fail está activo"
else
    mensaje "error" "Servicio backup_fail no está activo"
    mensaje "aviso" "Comprobando los logs del servicio backup_fail:"
    journalctl -u backup_fail.service -n 5
fi

if systemctl is-active --quiet vm_fail.service; then
    mensaje "ok" "Servicio vm_fail está activo"
else
    mensaje "error" "Servicio vm_fail no está activo"
    mensaje "aviso" "Comprobando los logs del servicio vm_fail:"
    journalctl -u vm_fail.service -n 5
fi

# Verificar fail2ban
if systemctl is-active --quiet fail2ban; then
    mensaje "ok" "Fail2ban está funcionando correctamente"
    if fail2ban-client status | grep -q "proxmox"; then
        mensaje "ok" "Jail de Proxmox configurado correctamente"
    else
        mensaje "aviso" "Jail de Proxmox no encontrado en fail2ban, intentando mostrar estado:"
        fail2ban-client status
    fi
else
    mensaje "error" "Fail2ban no está funcionando correctamente"
    mensaje "aviso" "Comprobando los logs de fail2ban:"
    journalctl -u fail2ban -n 5
fi

# Verificar crontab
if crontab -l | grep -q "/etc/pxe_monitor/ssh/ssh_monitor.sh"; then
    mensaje "ok" "Tarea cron para monitoreo SSH configurada correctamente"
else
    mensaje "error" "Tarea cron para monitoreo SSH no configurada"
fi

# Enviar mensaje de prueba a Telegram
mensaje "info" "Enviando mensaje de prueba a Telegram..."
MENSAJE_PRUEBA="✅ Sistema PXE Monitor instalado correctamente en $(hostname)"
curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d "chat_id=$CHAT_ID" -d "text=$MENSAJE_PRUEBA" > /dev/null
if [ $? -eq 0 ]; then
    mensaje "ok" "Mensaje de prueba enviado correctamente"
else
    mensaje "error" "No se pudo enviar el mensaje de prueba. Verifica los datos del bot y el chat ID"
fi

echo ""
mensaje "info" "Resumen de la instalación:"
echo "- Directorio principal: /etc/pxe_monitor"
echo "- Monitoreo de backups: Activo (servicio systemd)"
echo "- Monitoreo de VMs: Activo (servicio systemd)"
echo "- Protección contra fuerza bruta: Configurada (fail2ban)"
echo "- Monitoreo SSH: Activo (crontab cada 2 minutos)"
echo "- Bot de Telegram: Configurado"
echo ""
mensaje "ok" "¡Instalación completada con éxito!"
echo "Puedes modificar los scripts en /etc/pxe_monitor si necesitas personalizar la configuración."
