#!/bin/bash
# Variables al principio
IP=$1
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
PORT=8006

#BLOQUEA LA IP AL PUERTO 8006
iptables -A INPUT -s $IP -p tcp --dport $PORT -j DROP

#ENVIA EL MENSAJE POR TELEGRAM
curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" -d "chat_id=$TELEGRAM_CHAT_ID" -d "text=Fail2 Alert: Intento por fuerza bruta por web desde $IP"
