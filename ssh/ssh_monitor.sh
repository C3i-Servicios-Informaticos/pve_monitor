#!/bin/bash

logf="/var/log/auth.log"
BOT_TOKEN="8049940826:AAE5VQeKv29pmeOZDjylC-JGkCghPntGkmg"
CHAT_ID="-4716952882"
IP=$(grep "error: maximum" $logf | awk '{print $12}' | head -1)
msg="Intento de fuerza bruta por ssh bloqueado, ip bloqueada: $IP"
# Extract failed login attempts and count occurrences per IP
detect=$(grep "error: maximum" $logf)
if [ -z "$detect" ]; then
	echo "Todo bien jeje que felicidad"
else
	echo "ataqueeeee help meeee(manda algo por telegram)"
	curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d "chat_id=$CHAT_ID" -d "text=$msg"
	sed -i '/error: maximum/d' $logf
fi
