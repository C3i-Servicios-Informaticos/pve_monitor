# PVE Monitor

Sistema de monitorización y gestión para Proxmox Virtual Environment (PVE) con notificaciones a través de Telegram.

![Proxmox](https://img.shields.io/badge/Proxmox-E57000?style=for-the-badge&logo=proxmox&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)
![Telegram](https://img.shields.io/badge/Telegram-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white)

## 📋 Características

- **Monitoreo de backups**: Detecta problemas durante la creación de copias de seguridad.
- **Monitoreo de VMs/Contenedores**: Verifica el estado de las máquinas virtuales y contenedores, permitiendo reiniciar automáticamente los que no responden.
- **Protección contra fuerza bruta**: Integración con Fail2ban para proteger SSH y la interfaz web de Proxmox.
- **Notificaciones por Telegram**: Recibe alertas y toma acciones directamente desde tu dispositivo móvil.

## 🔧 Requisitos

- Proxmox Virtual Environment (PVE)
- Acceso root al servidor
- Bot de Telegram (token y chat ID)
- Conexión a Internet

## 🚀 Instalación

1. Descarga el script de instalación:

```bash
wget https://raw.githubusercontent.com/C3i-Servicios-Informaticos/pxe_monitor/refs/heads/main/installer.sh
```

2. Dale permisos de ejecución:

```bash
chmod +x installer.sh
```

3. Ejecuta el script como usuario root:

```bash
sudo ./installer.sh
```

4. Sigue las instrucciones en pantalla para configurar el bot de Telegram.

## ⚙️ Configuración

Después de la instalación, puedes modificar la configuración en el archivo:

```
/etc/pve_monitor/config.env
```

### Parámetros configurables:

| Parámetro | Descripción | Valor por defecto |
|-----------|-------------|-------------------|
| BOT_TOKEN | Token del bot de Telegram | Configurado durante instalación |
| CHAT_ID | ID del chat de Telegram | Configurado durante instalación |
| BACKUP_CHECK_INTERVAL | Intervalo de verificación de backups (segundos) | 120 |
| BACKUP_DIR | Directorio de backups | /var/lib/vz/dump/ |
| VM_CHECK_INTERVAL | Intervalo de verificación de VMs (segundos) | 300 |
| VM_RESTART_DELAY | Tiempo de espera entre apagar y encender una VM (segundos) | 5 |
| BAN_TIME | Tiempo de baneo para intentos fallidos (segundos) | 600 |
| MAX_RETRY_PROXMOX | Intentos fallidos permitidos para Proxmox | 3 |
| MAX_RETRY_SSH | Intentos fallidos permitidos para SSH | 4 |
| SSH_FINDTIME | Periodo de tiempo para contar intentos SSH (segundos) | 600 |

## 📦 Estructura del sistema

```
/etc/pve_monitor/
├── config.env                   # Configuración principal
├── lib/
│   └── common.sh               # Funciones comunes
└── modules/
    ├── backup/
    │   └── monitor.sh          # Monitor de backups
    ├── security/
    │   ├── proxmox.conf        # Configuración Fail2ban para Proxmox
    │   └── telegram.conf       # Configuración de notificaciones Telegram
    └── vm/
        └── monitor.sh          # Monitor de VMs y contenedores
```

## 🔄 Servicios

El sistema instala y configura los siguientes servicios:

1. **backup-monitor.timer**: Ejecuta el monitoreo de backups cada 2 minutos.
2. **vm-monitor.service**: Servicio que monitorea constantemente las VMs y contenedores.
3. **fail2ban**: Configurado con reglas específicas para proteger Proxmox y SSH.

### Gestión de servicios

Para verificar el estado de los servicios:

```bash
# Monitor de backups
systemctl status backup-monitor.timer

# Monitor de VMs
systemctl status vm-monitor.service

# Fail2ban
systemctl status fail2ban

fail2ban-client status
```

## 🛡️ Seguridad

El sistema configura Fail2ban con dos reglas principales:

1. **proxmox**: Protege la interfaz web de Proxmox bloqueando intentos de inicio de sesión fallidos.
2. **sshd**: Protege el acceso SSH al servidor.

En ambos casos, se enviarán notificaciones a Telegram cuando se bloquee una IP.
