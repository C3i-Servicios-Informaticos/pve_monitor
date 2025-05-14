#!/bin/bash

BOT_TOKEN=""
CHAT_ID=""

# Buscar intentos de fuerza bruta en journalctl
detect=$(journalctl -u ssh.service --since "5 minutes ago" | grep "error: maximum authentication attempts exceeded")

if [ -z "$detect" ]; then
    echo "Todo bien jeje que felicidad"
else
    # Extraer IP del atacante de los logs
    IP=$(journalctl -u ssh.service --since "5 minutes ago" | grep "error: maximum authentication attempts exceeded" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print $i}' | head -1)
    
    msg="Intento de fuerza bruta por ssh bloqueado, ip bloqueada: $IP"
    echo "ataqueeeee help meeee(manda algo por telegram)"
    
    # Enviar notificación por Telegram
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d "chat_id=$CHAT_ID" -d "text=$msg"
fi
