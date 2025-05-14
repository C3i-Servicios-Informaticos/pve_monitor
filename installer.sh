#!/bin/bash

# Colores para mensajes
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AMARILLO='\033[1;33m'
AZUL='\033[0;34m'
NORMAL='\033[0m'

# Directorios principales
BASE_DIR="/etc/pve_monitor"
SYSTEMD_DIR="/etc/systemd/system"

# Función para mostrar mensajes
mensaje() {
    case $1 in
        "info") echo -e "${AZUL}[INFO]${NORMAL} $2" ;;
        "ok") echo -e "${VERDE}[OK]${NORMAL} $2" ;;
        "error") echo -e "${ROJO}[ERROR]${NORMAL} $2" ;;
        "aviso") echo -e "${AMARILLO}[AVISO]${NORMAL} $2" ;;
    esac
}

# Verificar si se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    mensaje "error" "Este script debe ejecutarse como root"
    exit 1
fi

# Función para verificar e instalar dependencias
instalar_dependencias() {
    mensaje "info" "Verificando dependencias..."
    local deps=("jq" "curl" "fail2ban" "grep" "awk" "sed")
    local missing=false
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null && ! (dpkg -l | grep -q "$dep"); then
            mensaje "aviso" "Falta dependencia: $dep"
            missing=true
        fi
    done
    
    if [ "$missing" = true ]; then
        mensaje "info" "Instalando dependencias faltantes..."
        apt update
        apt install -y jq fail2ban curl
        
        # Verificar instalación
        for dep in "${deps[@]}"; do
            if ! command -v "$dep" &> /dev/null && ! (dpkg -l | grep -q "$dep"); then
                mensaje "error" "No se pudo instalar: $dep"
                return 1
            fi
        done
    fi
    
    mensaje "ok" "Todas las dependencias están instaladas"
    return 0
}

# Crear la estructura de directorios optimizada
crear_estructura() {
    mensaje "info" "Creando estructura de directorios optimizada..."
    
    mkdir -p "$BASE_DIR"
    mkdir -p "$BASE_DIR/lib"
    mkdir -p "$BASE_DIR/modules/backup"
    mkdir -p "$BASE_DIR/modules/security"
    mkdir -p "$BASE_DIR/modules/vm"
    
    mensaje "ok" "Estructura de directorios creada"
    return 0
}

# Función para configurar Telegram
configurar_telegram() {
    mensaje "info" "Configuración de Telegram"
    
    echo -e "${AZUL}[?]${NORMAL} Introduce el token del bot de Telegram:"
    read -r BOT_TOKEN
    
    echo -e "${AZUL}[?]${NORMAL} Introduce el ID del chat de Telegram:"
    read -r CHAT_ID
    
    if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
        mensaje "error" "Token o chat ID no pueden estar vacíos"
        return 1
    fi
    
    # Crear archivo de configuración centralizado
    cat > "$BASE_DIR/config.env" << EOF
# Configuración de Telegram
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"

# Configuración de Monitoreo de Backups
BACKUP_CHECK_INTERVAL=120  # segundos
BACKUP_DIR="/var/lib/vz/dump/"

# Configuración de Monitoreo de VMs
VM_CHECK_INTERVAL=300      # segundos
VM_RESTART_DELAY=5         # segundos

# Configuración de Seguridad
BAN_TIME=600               # segundos
MAX_RETRY_PROXMOX=3
MAX_RETRY_SSH=4
SSH_FINDTIME=600           # segundos
EOF
    
    # Reemplazar tokens en configuración de fail2ban
    cp "$BASE_DIR/modules/security/telegram.conf" "$BASE_DIR/modules/security/telegram.conf.tmp"
    sed -i "s|BOT_TOKEN_PLACEHOLDER|$BOT_TOKEN|g" "$BASE_DIR/modules/security/telegram.conf.tmp" 
    sed -i "s|CHAT_ID_PLACEHOLDER|$CHAT_ID|g" "$BASE_DIR/modules/security/telegram.conf.tmp"
    mv "$BASE_DIR/modules/security/telegram.conf.tmp" "$BASE_DIR/modules/security/telegram.conf"
    
    mensaje "ok" "Configuración de Telegram completada"
    return 0
}

# Función para crear los archivos del sistema optimizado
crear_archivos_optimizados() {
    mensaje "info" "Creando archivos optimizados..."
    
    # Biblioteca de funciones comunes
    cat > "$BASE_DIR/lib/common.sh" << 'EOF'
#!/bin/bash
# Cargar configuración
source /etc/pve_monitor/config.env

# Función para enviar mensajes a Telegram
send_telegram_message() {
    local message="$1"
    local keyboard="$2"
    
    if [ -n "$keyboard" ]; then
        curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
             -d "chat_id=$CHAT_ID" \
             -d "text=$message" \
             -d "reply_markup=$keyboard"
    else
        curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
             -d "chat_id=$CHAT_ID" \
             -d "text=$message"
    fi
}

# Función para crear teclados inline para Telegram
create_inline_keyboard() {
    local options=("$@")
    local keyboard='{"inline_keyboard":['
    
    # Crear botones con pares de [texto, callback_data]
    local buttons=""
    for ((i=0; i<${#options[@]}; i+=2)); do
        if [ "$i" -gt 0 ]; then
            buttons+=","
        fi
        buttons+="{\"text\":\"${options[i]}\",\"callback_data\":\"${options[i+1]}\"}"
    done
    
    keyboard+="[$buttons]]}"
    echo "$keyboard"
}

# Función para esperar respuesta de botón en Telegram
wait_telegram_callback() {
    local message_id="$1"
    local timeout="${2:-60}"  # Timeout por defecto 60 segundos
    local offset=0
    local start_time=$(date +%s)
    
    while true; do
        # Verificar si se ha excedido el timeout
        local current_time=$(date +%s)
        if [ $((current_time - start_time)) -gt "$timeout" ]; then
            echo "timeout"
            return 1
        fi
        
        # Obtener actualizaciones
        local updates=$(curl -s "https://api.telegram.org/bot$BOT_TOKEN/getUpdates?offset=$offset&timeout=1")
        
        # Procesar actualizaciones
        if [ -n "$(echo $updates | jq '.result')" ] && [ "$(echo $updates | jq '.result | length')" -gt 0 ]; then
            for i in $(seq 0 $(echo $updates | jq '.result | length - 1')); do
                local update_id=$(echo $updates | jq -r ".result[$i].update_id")
                offset=$((update_id + 1))
                
                # Verificar si es una callback para nuestro mensaje
                if echo $updates | jq -r ".result[$i].callback_query" | grep -q "$message_id"; then
                    local callback_id=$(echo $updates | jq -r ".result[$i].callback_query.id")
                    local data=$(echo $updates | jq -r ".result[$i].callback_query.data")
                    
                    # Confirmar recepción de callback
                    curl -s "https://api.telegram.org/bot$BOT_TOKEN/answerCallbackQuery?callback_query_id=$callback_id" > /dev/null
                    
                    echo "$data"
                    return 0
                fi
            done
        fi
        
        sleep 1
    done
}

# Función para log
log_message() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

# Verificar si un proceso está en ejecución
is_process_running() {
    local process_name="$1"
    pgrep -f "$process_name" > /dev/null
    return $?
}
EOF

    # Módulo de monitoreo de backups
    cat > "$BASE_DIR/modules/backup/monitor.sh" << 'EOF'
#!/bin/bash
# Cargar funciones comunes
source /etc/pve_monitor/lib/common.sh

log_message "INFO" "Iniciando monitoreo de backups"

# Verificar si hay backups en ejecución
backup_process=$(ps -aux | grep -i vzdump | grep -v grep)

if [ -z "$backup_process" ]; then
    log_message "INFO" "No hay backups en ejecución"
    exit 0
fi

log_message "INFO" "Backup en ejecución, iniciando monitorización"

# Obtener VMID del backup
vmid=$(echo "$backup_process" | awk '{print $12}' | awk -F ':' '{print $7}')
alerta_enviada=false
mensaje="⚠️ Posible problema con el backup en la VM $vmid - El tamaño no está aumentando"

# Monitorizar el progreso del backup
espacio=$(ls -lh "$BACKUP_DIR" | grep vma | awk '{print $5}')
[ -n "$espacio" ] && byte_espacio_anterior=$(numfmt --from=iec "$espacio")

while [ -n "$(ps -aux | grep -i vzdump | grep -v grep)" ]; do
    log_message "INFO" "Backup en progreso..."
    
    # Obtener el tamaño actual del archivo de backup
    espacio=$(ls -lh "$BACKUP_DIR" | grep vma | awk '{print $5}')
    [ -z "$espacio" ] && continue
    
    byte_espacio_actual=$(numfmt --from=iec "$espacio")
    
    # Verificar si el tamaño ha aumentado
    if [ -n "$byte_espacio_anterior" ] && [ "$byte_espacio_actual" -le "$byte_espacio_anterior" ] && [ "$alerta_enviada" = false ]; then
        log_message "WARNING" "El tamaño del backup no ha cambiado"
        send_telegram_message "$mensaje"
        alerta_enviada=true
    fi
    
    byte_espacio_anterior="$byte_espacio_actual"
    sleep 10
done

log_message "INFO" "Backup finalizado"
exit 0
EOF

    # Módulo de monitoreo de VMs/CTs
    cat > "$BASE_DIR/modules/vm/monitor.sh" << 'EOF'
#!/bin/bash
# Cargar funciones comunes
source /etc/pve_monitor/lib/common.sh

# Leer instancias excluidas de los argumentos
excluded_instances=("$@")
log_message "INFO" "Instancias excluidas: ${excluded_instances[*]}"

# Teclado inline para preguntar si reiniciar VM
vm_keyboard=$(create_inline_keyboard "Si" "restart_yes" "No" "restart_no")

# Función para verificar si una instancia está excluida
is_excluded() {
    local instance="$1"
    for excluded in "${excluded_instances[@]}"; do
        if [ "$instance" = "$excluded" ]; then
            return 0  # True, está excluida
        fi
    done
    return 1  # False, no está excluida
}

# Función para obtener IP de una instancia
get_instance_ip() {
    local instance="$1"
    local type="$2"
    
    if [ "$type" = "container" ]; then
        pct exec "$instance" ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1
    else  # VM
        qm guest cmd "$instance" network-get-interfaces 2>/dev/null | grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -E "192\.|10\.|172\." | head -n 1
    fi
}

# Función para verificar si una instancia debe ser monitoreada
should_monitor_instance() {
    local instance="$1"
    local config_cmd="$2"
    
    # Verificar si es template o no está configurada para arrancar
    local onboot=$($config_cmd "$instance" | grep -q "onboot: 0" || ( ! $config_cmd "$instance" | grep -q "onboot" ) && echo "true" || echo "false")
    local template=$($config_cmd "$instance" | grep -q "template:" && echo "true" || echo "false")
    
    if [ "$onboot" = "true" ] || [ "$template" = "true" ]; then
        return 1  # No monitorear
    fi
    
    return 0  # Monitorear
}

# Función principal de monitoreo
monitor_instances() {
    log_message "INFO" "Iniciando ciclo de monitoreo"
    
    # Obtener lista de contenedores
    local containers=$(pct list | awk 'NR>1 {print $1}')
    
    # Obtener lista de VMs
    local vms=$(qm list | awk 'NR>1 {print $1}')
    
    # Monitorear todas las instancias
    for instance in $containers $vms; do
        # Saltar instancias excluidas
        if is_excluded "$instance"; then
            log_message "INFO" "Saltando instancia $instance (excluida)"
            continue
        fi
        
        # Determinar tipo y comando de configuración
        local instance_type=""
        local config_cmd=""
        
        if pct status "$instance" >/dev/null 2>&1; then
            instance_type="container"
            config_cmd="pct config"
        else
            instance_type="vm"
            config_cmd="qm config"
        fi
        
        # Verificar si la instancia debe ser monitoreada
        if ! should_monitor_instance "$instance" "$config_cmd"; then
            log_message "INFO" "Saltando instancia $instance (no configurada para monitoreo)"
            continue
        fi
        
        # Obtener IP de la instancia
        local ip=$(get_instance_ip "$instance" "$instance_type")
        
        if [ -z "$ip" ]; then
            log_message "WARNING" "No se pudo obtener IP para $instance_type $instance"
            continue
        fi
        
        # Verificar si la instancia responde
        if ! ping -c 3 "$ip" >/dev/null 2>&1; then
            log_message "WARNING" "$instance_type $instance ($ip) no responde"
            
            if [ "$instance_type" = "container" ]; then
                # Reiniciar contenedor automáticamente
                log_message "INFO" "Reiniciando contenedor $instance"
                pct stop "$instance" >/dev/null 2>&1
                sleep "$VM_RESTART_DELAY"
                pct start "$instance" >/dev/null 2>&1
                send_telegram_message "🔄 Contenedor $instance reiniciado automáticamente"
            else
                # Verificar estado de la VM
                if qm status "$instance" | grep -q "status: running"; then
                    log_message "WARNING" "VM $instance está en ejecución pero no responde"
                    mensaje="⚠️ VM $instance no responde. ¿Desea reiniciarla?"
                else
                    log_message "WARNING" "VM $instance no está en ejecución"
                    mensaje="ℹ️ VM $instance no está encendida. ¿Desea encenderla?"
                fi
                
                # Enviar mensaje con botones y esperar respuesta
                response=$(send_telegram_message "$mensaje" "$vm_keyboard")
                message_id=$(echo "$response" | jq -r '.result.message_id')
                
                # Esperar respuesta (timeout 60 segundos)
                choice=$(wait_telegram_callback "$message_id" 60)
                
                if [ "$choice" = "restart_yes" ]; then
                    log_message "INFO" "Reiniciando VM $instance"
                    if qm status "$instance" | grep -q "status: running"; then
                        qm stop "$instance" >/dev/null 2>&1
                        sleep "$VM_RESTART_DELAY"
                    fi
                    qm start "$instance" >/dev/null 2>&1
                    send_telegram_message "🔄 VM $instance reiniciada/encendida"
                else
                    log_message "INFO" "Usuario decidió no reiniciar VM $instance"
                    send_telegram_message "⏹️ No se reiniciará la VM $instance"
                fi
            fi
        else
            log_message "INFO" "$instance_type $instance ($ip) responde correctamente"
        fi
    done
    
    log_message "INFO" "Ciclo de monitoreo completado"
}

# Bucle principal
while true; do
    monitor_instances
    log_message "INFO" "Esperando $VM_CHECK_INTERVAL segundos para el próximo ciclo"
    sleep "$VM_CHECK_INTERVAL"
done
EOF

    # Configuración de Fail2Ban para Proxmox
    cat > "$BASE_DIR/modules/security/proxmox.conf" << 'EOF'
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
            pveproxy\[.*authentication failure; rhost=<HOST> user=.* msg=.*
            pveproxy\[.*Failed to authenticate user .* \(<HOST>\): invalid credentials

ignoreregex =
EOF

    # Configuración de Acción Telegram para Fail2Ban
    cat > "$BASE_DIR/modules/security/telegram.conf" << 'EOF'
[Definition]
actionstart =
actionstop =
actionban = curl -s -X POST "https://api.telegram.org/bot<bot_token>/sendMessage" -d "chat_id=<chat_id>" -d "text=🛑 Fail2Ban: Bloqueo IP <ip> (servicio: <name>)"
actionunban =

[Init]
bot_token = BOT_TOKEN_PLACEHOLDER
chat_id = CHAT_ID_PLACEHOLDER
EOF

    # Dar permisos de ejecución a los scripts
    chmod +x "$BASE_DIR/lib/common.sh"
    chmod +x "$BASE_DIR/modules/backup/monitor.sh"
    chmod +x "$BASE_DIR/modules/vm/monitor.sh"
    
    mensaje "ok" "Archivos optimizados creados correctamente"
    return 0
}

# Configurar servicios systemd
configurar_servicios() {
    mensaje "info" "Configurando servicios systemd..."
    
    # Servicio de monitoreo de backups
    cat > "$SYSTEMD_DIR/backup-monitor.service" << EOF
[Unit]
Description=Servicio de monitoreo de backups
After=network.target

[Service]
Type=oneshot
ExecStart=$BASE_DIR/modules/backup/monitor.sh
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF

    # Timer de monitoreo de backups
    cat > "$SYSTEMD_DIR/backup-monitor.timer" << EOF
[Unit]
Description=Ejecuta el monitoreo de backups cada 2 minutos

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
Unit=backup-monitor.service

[Install]
WantedBy=timers.target
EOF

    # Servicio de monitoreo de VMs/CTs
    cat > "$SYSTEMD_DIR/vm-monitor.service" << EOF
[Unit]
Description=Servicio de monitoreo de VMs y contenedores
After=network.target

[Service]
Type=simple
ExecStart=$BASE_DIR/modules/vm/monitor.sh
Restart=on-failure
RestartSec=30
User=root

[Install]
WantedBy=multi-user.target
EOF

    # Habilitar y arrancar servicios
    systemctl daemon-reload
    
    mensaje "info" "Habilitando servicios..."
    systemctl enable backup-monitor.timer
    systemctl start backup-monitor.timer
    systemctl enable vm-monitor.service
    systemctl start vm-monitor.service
    
    mensaje "ok" "Servicios configurados y activados"
    return 0
}

# Configurar fail2ban
configurar_fail2ban() {
    mensaje "info" "Configurando fail2ban..."
    
    # Crear filtro de Proxmox
    cp "$BASE_DIR/modules/security/proxmox.conf" /etc/fail2ban/filter.d/proxmox.conf
    
    # Crear acción de Telegram
    cp "$BASE_DIR/modules/security/telegram.conf" /etc/fail2ban/action.d/telegram.conf
    
    # Configurar jail.local
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
ignoreip = 127.0.0.1/8
bantime = 600
maxretry = 3
backend = systemd

[proxmox]
enabled = true
port = https,http,8006
filter = proxmox
backend = systemd
maxretry = 3
bantime = 100
action = telegram

[sshd]
enabled = true
filter = sshd
port = ssh
backend = systemd
maxretry = 4
findtime = 600
bantime = 600
action = iptables-multiport[name=SSH, port=ssh, protocol=tcp]
        telegram
EOF

    # Eliminar configuración por defecto que podría interferir
    [ -f "/etc/fail2ban/jail.d/defaults-debian.conf" ] && rm -f /etc/fail2ban/jail.d/defaults-debian.conf
    
    # Reiniciar fail2ban
    systemctl restart fail2ban
    
    mensaje "ok" "Fail2ban configurado correctamente"
    return 0
}

# Verificar la instalación
verificar_instalacion() {
    mensaje "info" "Verificando instalación..."
    local errores=0
    
    # Verificar servicios
    if ! systemctl is-active --quiet backup-monitor.timer; then
        mensaje "error" "El temporizador backup-monitor.timer no está activo"
        errores=$((errores + 1))
    fi
    
    if ! systemctl is-active --quiet vm-monitor.service; then
        mensaje "error" "El servicio vm-monitor.service no está activo"
        errores=$((errores + 1))
    fi
    
    # Verificar fail2ban
    if ! systemctl is-active --quiet fail2ban; then
        mensaje "error" "El servicio fail2ban no está activo"
        errores=$((errores + 1))
    else
        # Dar tiempo a que fail2ban se inicialice completamente
        sleep 2
        
        # Verificar configuración de fail2ban con mejor manejo de errores
        JAIL_CHECK=$(fail2ban-client status 2>/dev/null || echo "ERROR")
        if echo "$JAIL_CHECK" | grep -q "ERROR"; then
            mensaje "aviso" "No se pudo verificar la configuración de fail2ban, pero el servicio está activo"
        elif ! echo "$JAIL_CHECK" | grep -q "proxmox"; then
            mensaje "error" "Jail de Proxmox no configurado en fail2ban"
            errores=$((errores + 1))
        else
            mensaje "ok" "Fail2ban configurado correctamente con jail de Proxmox"
        fi
    fi
    
    # Enviar mensaje de prueba a Telegram
    source "$BASE_DIR/config.env"
    local mensaje_prueba="✅ Sistema PVE Monitor instalado correctamente en $(hostname)"
    
    if ! curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d "chat_id=$CHAT_ID" -d "text=$mensaje_prueba" > /dev/null; then
        mensaje "error" "No se pudo enviar mensaje de prueba a Telegram"
        errores=$((errores + 1))
    fi
    
    if [ "$errores" -eq 0 ]; then
        mensaje "ok" "Instalación verificada correctamente"
        return 0
    else
        mensaje "error" "Se encontraron $errores errores durante la verificación"
        return 1
    fi
}

# Función principal de instalación
main() {
    clear
    echo "==========================================================="
    echo "          INSTALADOR DE SISTEMA PVE MONITOR"
    echo "==========================================================="
    echo ""
    mensaje "info" "Este script instalará y configurará el sistema PVE Monitor optimizado"
    echo ""
    
    # Instalar dependencias
    if ! instalar_dependencias; then
        mensaje "error" "Error al instalar dependencias. Abortando..."
        exit 1
    fi
    
    # Crear estructura de directorios optimizada
    crear_estructura
    
    # Crear archivos del sistema optimizado
    crear_archivos_optimizados
    
    # Configurar Telegram
    if ! configurar_telegram; then
        mensaje "error" "Error al configurar Telegram. Abortando..."
        exit 1
    fi
    
    # Configurar servicios
    configurar_servicios
    
    # Configurar fail2ban
    configurar_fail2ban
    
    # Verificar instalación
    if verificar_instalacion; then
        mensaje "ok" "¡Instalación completada con éxito!"
        echo ""
        echo "Resumen de la instalación:"
        echo "- Monitoreo de backups: Activo (temporizador systemd cada 2 minutos)"
        echo "- Monitoreo de VMs: Activo (servicio systemd)"
        echo "- Protección contra fuerza bruta: Configurada (fail2ban)"
        echo "- Notificaciones: Configuradas (Telegram)"
        echo ""
        mensaje "info" "Puede modificar la configuración en $BASE_DIR/config.env"
    else
        mensaje "aviso" "La instalación se completó con advertencias. Revise los mensajes anteriores."
    fi
}

# Ejecutar instalación
main
