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

# Función para pedir y validar el token de Telegram
pedir_token_telegram() {
    while true; do
        read -p "Por favor, introduce el token del bot de Telegram: " BOT_TOKEN
        if [[ $BOT_TOKEN =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
            mensaje "ok" "Token válido"
            break
        else
            mensaje "error" "El formato del token no es válido. Debe ser similar a '123456789:ABC-DEF1234ghIkl-zyx57W2v1u123ew11'"
        fi
    done
}

# Función para pedir y validar el ID del chat de Telegram
pedir_chat_id() {
    while true; do
        read -p "Por favor, introduce el ID del chat de Telegram: " CHAT_ID
        if [[ $CHAT_ID =~ ^-?[0-9]+$ ]]; then
            mensaje "ok" "ID de chat válido"
            break
        else
            mensaje "error" "El ID del chat debe ser un número (puede incluir un signo negativo al principio)"
        fi
    done
}

# Función para reemplazar tokens en un archivo
reemplazar_token() {
    sed -i "s|BOT_TOKEN=\"\"|BOT_TOKEN=\"$BOT_TOKEN\"|g" $1
    sed -i "s|CHAT_ID=\"\"|CHAT_ID=\"$CHAT_ID\"|g" $1
    # Para multi-action.sh, que usa TELEGRAM prefijo
    sed -i "s|TELEGRAM_BOT_TOKEN|BOT_TOKEN|g" $1
    sed -i "s|TELEGRAM_CHAT_ID|CHAT_ID|g" $1
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

for dep in jq fail2ban curl grep awk sed; do
    if ! verificar_comando $dep; then
        DEPS_MISSING=1
    fi
done

if [ $DEPS_MISSING -eq 1 ]; then
    mensaje "info" "Instalando dependencias faltantes..."
    apt update
    apt install -y jq fail2ban curl
    
    # Verificar si se instalaron correctamente
    if ! verificar_comando jq || ! verificar_comando fail2ban || ! verificar_comando curl; then
        mensaje "error" "No se pudieron instalar todas las dependencias. Por favor, instálalas manualmente."
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

# Solicitar información de Telegram
echo ""
mensaje "info" "Configuración de Telegram"
pedir_token_telegram
pedir_chat_id
echo ""

# Descargar archivos
mensaje "info" "Descargando archivos del repositorio..."

# URLs base para los archivos
REPO_URL="https://raw.githubusercontent.com/C3i-Servicios-Informaticos/pxe_monitor/main"

# Función para descargar un archivo
descargar_archivo() {
    local ruta_destino=$1
    local nombre_archivo=$2
    local url_completa="${REPO_URL}/${ruta_destino}/${nombre_archivo}"
    
    if curl -s --head "$url_completa" | head -n 1 | grep "200" > /dev/null; then
        curl -s "$url_completa" -o "/etc/pxe_monitor/${ruta_destino}/${nombre_archivo}"
        mensaje "ok" "Archivo ${nombre_archivo} descargado correctamente"
        
        # Aplicar permisos si es un script
        if [[ "$nombre_archivo" == *.sh ]]; then
            chmod +x "/etc/pxe_monitor/${ruta_destino}/${nombre_archivo}"
        fi
        
        # Reemplazar tokens
        reemplazar_token "/etc/pxe_monitor/${ruta_destino}/${nombre_archivo}"
        
        return 0
    else
        mensaje "error" "No se pudo acceder a ${url_completa}"
        return 1
    fi
}

# Descargar los archivos por categoría
# pxe_backup
descargar_archivo "pxe_backup" "backup_fail.service"
descargar_archivo "pxe_backup" "bak_deal.sh"

# pxe_bruteforce
descargar_archivo "pxe_bruteforce" "jail.local"
descargar_archivo "pxe_bruteforce" "multi-action.sh"
descargar_archivo "pxe_bruteforce" "telegram.conf"

# pxe_vm
descargar_archivo "pxe_vm" "ping-instances.sh"
descargar_archivo "pxe_vm" "vm_fail.service"

# ssh
descargar_archivo "ssh" "ssh_monitor.sh"

# README.md (en el directorio raíz)
curl -s "${REPO_URL}/README.md" -o "/etc/pxe_monitor/README.md"

# Configurar fail2ban
mensaje "info" "Configurando fail2ban..."

# Crear acción personalizada para fail2ban
if [ -f "/etc/pxe_monitor/pxe_bruteforce/telegram.conf" ]; then
    cp /etc/pxe_monitor/pxe_bruteforce/telegram.conf /etc/fail2ban/action.d/telegram.conf
    mensaje "ok" "Acción de Telegram configurada para fail2ban"
fi

# Configurar jail local
if [ -f "/etc/pxe_monitor/pxe_bruteforce/jail.local" ]; then
    cp /etc/pxe_monitor/pxe_bruteforce/jail.local /etc/fail2ban/jail.d/proxmox.conf
    mensaje "ok" "Configuración de jail para Proxmox añadida"
fi

# Reiniciar fail2ban
systemctl restart fail2ban
if [ $? -eq 0 ]; then
    mensaje "ok" "Servicio fail2ban reiniciado correctamente"
else
    mensaje "error" "No se pudo reiniciar el servicio fail2ban"
fi

# Configurar servicios systemd
mensaje "info" "Configurando servicios..."

# Servicio de backup
if [ -f "/etc/pxe_monitor/pxe_backup/backup_fail.service" ]; then
    cp /etc/pxe_monitor/pxe_backup/backup_fail.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable backup_fail.service
    systemctl start backup_fail.service
    mensaje "ok" "Servicio de backup configurado y activado"
fi

# Servicio de monitoreo de VMs
if [ -f "/etc/pxe_monitor/pxe_vm/vm_fail.service" ]; then
    cp /etc/pxe_monitor/pxe_vm/vm_fail.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable vm_fail.service
    systemctl start vm_fail.service
    mensaje "ok" "Servicio de monitoreo de VMs configurado y activado"
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
fi

if systemctl is-active --quiet vm_fail.service; then
    mensaje "ok" "Servicio vm_fail está activo"
else
    mensaje "error" "Servicio vm_fail no está activo"
fi

# Verificar fail2ban
if fail2ban-client status | grep -q "Number of jail:"; then
    mensaje "ok" "Fail2ban está funcionando correctamente"
    if fail2ban-client status | grep -q "proxmox"; then
        mensaje "ok" "Jail de Proxmox configurado correctamente"
    else
        mensaje "aviso" "Jail de Proxmox no encontrado en fail2ban"
    fi
else
    mensaje "error" "Fail2ban no está funcionando correctamente"
fi

# Verificar crontab
if crontab -l | grep -q "/etc/pxe_monitor/ssh/ssh_monitor.sh"; then
    mensaje "ok" "Tarea cron para monitoreo SSH configurada correctamente"
else
    mensaje "error" "Tarea cron para monitoreo SSH no configurada"
fi

echo ""
mensaje "info" "Resumen de la instalación:"
echo "- Directorio principal: /etc/pxe_monitor"
echo "- Monitoreo de backups: Activo (servicio systemd)"
echo "- Monitoreo de VMs: Activo (servicio systemd)"
echo "- Protección contra fuerza bruta: Configurada (fail2ban)"
echo "- Monitoreo SSH: Activo (crontab cada 2 minutos)"
echo ""
mensaje "ok" "¡Instalación completada con éxito!"
echo "Puedes modificar los scripts en /etc/pxe_monitor si necesitas personalizar la configuración."
