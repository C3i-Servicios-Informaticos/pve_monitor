#!/bin/bash

BOT_TOKEN="8049940826:AAE5VQeKv29pmeOZDjylC-JGkCghPntGkmg"
CHAT_ID="-4716952882"
primero=$(ps -aux | grep -i vzdump | grep -v grep)
#Comprueba si se esta realizando una copia de seguridad
if [ -z "$primero" ]; then
	echo "esta vacio no hay backups ejecutandose"
else
	echo "Hay un backup en ejecucion empezando la monitorización"
	#La vmid de la máquina donde se hace la copia
	vmid=$(echo "$primero" | awk '{print $12}' | awk -F ':' '{print $7}')
	mensaje="Cuidado existe un problema con el backup en la vm $vmid"
	#cantidad de espacio que ocupa el archivo de backup
	espacio=$(ls -lh /var/lib/vz/dump/ | grep vma | awk '{print $5'})
	#convertir el formato de MB/GB a bytes para comparar
	if [ ! -z $espacio ]; then
	byte_espa_anterior=$(numfmt --from=iec $espacio)
	fi
	while [ "$primero" != "" ]; do
		echo "esto no ha finalizado"
		sleep 10 
		primero=$(ps -aux | grep -i vzdump | grep -v grep)
		echo "$primero"
		if [ -z "$primero" ]; then
			exit
		fi
		espacio=$(ls -lh /var/lib/vz/dump/ | grep vma | awk '{print $5}')
		byte_espa_actual=$(numfmt --from=iec $espacio)
		if [ ! -z "$byte_espa_anterior" ]; then
		if [ "$byte_espa_actual" -gt "$byte_espa_anterior" ]; then
				echo "El tamaño del bakup ha aumentado"
			else
				echo "El tamaño del backup no ha cambiado, es un dilema"
				
				curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d "chat_id=$CHAT_ID" -d "text=$mensaje"
			fi
			
		fi
		byte_espa_anterior=$byte_espa_actual
	done
fi
