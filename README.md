# PXE Monitor

Sistema de monitorización para entornos Proxmox con alertas a través de Telegram.

## Descripción

PXE Monitor es un conjunto de herramientas diseñado para supervisar y proteger entornos Proxmox. El sistema incluye:

- **Monitorización de backups**: Detecta problemas durante la ejecución de copias de seguridad.
- **Protección contra ataques de fuerza bruta**: Bloquea intentos de acceso no autorizado a la interfaz web de Proxmox.
- **Monitorización de VMs/CTs**: Supervisa el estado de las máquinas virtuales y contenedores, ofreciendo reactivación automática.
- **Monitorización SSH**: Detecta y alerta sobre intentos de acceso por fuerza bruta SSH.

Todas las alertas se envían a través de Telegram, permitiendo una respuesta rápida ante cualquier incidente.

## Requisitos previos

- Sistema basado en Debian/Ubuntu (Proxmox VE)
- Conexión a Internet
- Bot de Telegram configurado (token y chat_id)
- Permisos de administrador (root)

### Dependencias

- `jq`: Procesamiento de JSON
- `fail2ban`: Protección contra ataques de fuerza bruta
- `curl`: Transferencia de datos

## Instalación rápida

Para instalar PXE Monitor, ejecute el siguiente comando como administrador:

```bash
curl -sSL https://raw.githubusercontent.com/C3i-Servicios-Informaticos/pxe_monitor/main/installer.sh | bash
```

Durante la instalación, se le solicitará:
- Token del bot de Telegram
- ID del chat de Telegram

El instalador configurará automáticamente todos los componentes necesarios.

## Componentes del sistema

### 1. Monitorización de backups

Supervisa el progreso de las copias de seguridad y alerta cuando detecta problemas, como estancamiento en el tamaño del archivo de backup.

**Archivos:**
- `/etc/pxe_monitor/pxe_backup/bak_deal.sh`
- `/etc/systemd/system/backup_fail.service`

### 2. Protección contra fuerza bruta (Web Proxmox)

Configura fail2ban para detectar y bloquear intentos de acceso no autorizado a la interfaz web de Proxmox.

**Archivos:**
- `/etc/pxe_monitor/pxe_bruteforce/multi-action.sh`
- `/etc/pxe_monitor/pxe_bruteforce/jail.local`
- `/etc/pxe_monitor/pxe_bruteforce/telegram.conf`
- `/etc/fail2ban/action.d/telegram.conf`
- `/etc/fail2ban/jail.d/proxmox.conf`

### 3. Monitorización de VMs/CTs

Supervisa el estado de máquinas virtuales y contenedores mediante ping. Si una VM/CT no responde, ofrece la opción de reiniciarla a través de una notificación interactiva de Telegram.

**Archivos:**
- `/etc/pxe_monitor/pxe_vm/ping-instances.sh`
- `/etc/systemd/system/vm_fail.service`

### 4. Monitorización SSH

Detecta intentos de acceso por fuerza bruta a través de SSH y envía alertas por Telegram.

**Archivos:**
- `/etc/pxe_monitor/ssh/ssh_monitor.sh`
- Entrada en crontab (ejecutando cada 2 minutos)

## Uso y configuración

### Exclusión de VMs/CTs específicas

Para excluir VMs o contenedores de la monitorización, edite el archivo de servicio:

```bash
nano /etc/systemd/system/vm_fail.service
```

Y modifique la línea `ExecStart` para incluir los IDs que desea excluir:

```
ExecStart=/etc/pxe_monitor/ping-instances.sh 100 101 102
```

Donde 100, 101, 102 son los IDs de las VMs/CTs que desea excluir.

### Verificación de estado

Para verificar el estado de los servicios:

```bash
# Servicio de monitorización de backups
systemctl status backup_fail.service

# Servicio de monitorización de VMs
systemctl status vm_fail.service

# Estado de fail2ban
fail2ban-client status
fail2ban-client status proxmox
```

## Resolución de problemas

### Los mensajes de Telegram no llegan

1. Verifique la conexión a Internet
2. Compruebe que el token del bot es correcto
3. Asegúrese de que el bot está en el chat especificado por el chat_id
4. Verifique logs: `journalctl -u backup_fail.service` o `journalctl -u vm_fail.service`

### Fail2ban no bloquea intentos

1. Verifique que fail2ban está en ejecución: `systemctl status fail2ban`
2. Compruebe la configuración: `fail2ban-client status proxmox`
3. Revise los logs: `tail -f /var/log/fail2ban.log`

## Desinstalación

Para desinstalar PXE Monitor, ejecute:

```bash
systemctl stop backup_fail.service
systemctl stop vm_fail.service
systemctl disable backup_fail.service
systemctl disable vm_fail.service
rm -f /etc/systemd/system/backup_fail.service
rm -f /etc/systemd/system/vm_fail.service
rm -f /etc/fail2ban/action.d/telegram.conf
rm -f /etc/fail2ban/jail.d/proxmox.conf
rm -rf /etc/pxe_monitor
crontab -l | grep -v "ssh_monitor.sh" | crontab -
systemctl restart fail2ban
```

## Contribuciones

Las contribuciones son bienvenidas. Por favor, envíe sus pull requests o abra issues para discutir los cambios propuestos.

## Licencia

Este proyecto está licenciado bajo la Licencia MIT - vea el archivo LICENSE para más detalles.

## Agradecimientos

- Equipo de Proxmox por su excelente plataforma de virtualización
- Comunidad de fail2ban por sus herramientas de seguridad
- Telegram por su API de bots que hace posible las notificaciones

---

Desarrollado por [C3i Servicios Informáticos](https://github.com/C3i-Servicios-Informaticos)
