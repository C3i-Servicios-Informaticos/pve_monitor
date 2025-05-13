#!/usr/bin/env bash
# Read excluded instances from command line arguments
excluded_instances=("$@")
echo "Excluded instances: ${excluded_instances[@]}"

BOT_TOKEN=""
CHAT_ID=""
msg1="🔄 Se procede a levantar la máquina"
msg2="No se levantará, para no repetir el mensaje, por favor modificar opciones de la vm"
# Aviso por máquina apagada: mensaje
# Crear los botones en formato JSON (estructura de teclado en línea)
TECLADO=$(cat <<-EOF
{
	"inline_keyboard": [
	[
	  	{
			"text": "Si",
			"callback_data": "op1"
		},
		{
			"text": "No",
			"callback_data": "op2"
		}
	]
	]
}
EOF
)
#Loop principal
while true; do

  for instance in $(pct list | awk '{if(NR>1) print $1}'; qm list | awk '{if(NR>1) print $1}'); do
    # Skip excluded instances
    if [[ " ${excluded_instances[@]} " =~ " ${instance} " ]]; then
      echo "Skipping $instance because it is excluded"
      continue
    fi

    # Determine the type of the instance (container or virtual machine)
    if pct status $instance >/dev/null 2>&1; then
      # It is a container
      config_cmd="pct config"
      IP=$(pct exec $instance ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
    else
      # It is a virtual machine
      config_cmd="qm config"
      IP=$(qm guest cmd $instance network-get-interfaces | egrep -o "([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -E "192\.|10\.|172\." | head -n 1)
    fi

    # Skip instances based on onboot and templates
    onboot=$($config_cmd $instance | grep -q "onboot: 0" || ( ! $config_cmd $instance | grep -q "onboot" ) && echo "true" || echo "false")
    template=$($config_cmd $instance | grep template | grep -q "template:" && echo "true" || echo "false")

    if [ "$onboot" == "true" ]; then
      echo "Skipping $instance because it is set not to boot"
      continue
    elif [ "$template" == "true" ]; then
      echo "Skipping $instance because it is a template"
      continue
    fi

    # Ping the instance
    if ! ping -c 3 $IP >/dev/null 2>&1; then
      # If the instance can not be pinged, stop and start it
      if pct status $instance >/dev/null 2>&1; then
        # It is a container
        echo "$(date): CT $instance is not responding, restarting..."
        pct stop $instance >/dev/null 2>&1
        sleep 5
        pct start $instance >/dev/null 2>&1
      else
        # It is a virtual machine
        if qm status $instance | grep -q "status: running"; then
          echo "$(date): VM $instance is not responding, restarting..."
          qm stop $instance >/dev/null 2>&1
          sleep 5
        else
  echo "$(date): VM $instance is not running, starting..."
      fi
	
	MENSAJE="ℹ️ La VM $instance no está encendida, desea encenderla"
	# Enviar el mensaje con los botones
	RESPUESTA=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d "chat_id=$CHAT_ID" -d "text=$MENSAJE" -d "reply_markup=$TECLADO")
	# Extraer el ID del mensaje enviado (necesario para identificar las respuestas)
	# Requiere jq instalado
	MESSAGE_ID=$(echo $RESPUESTA | jq -r '.result.message_id')
	echo "Mensaje enviado con ID: $MESSAGE_ID"
	echo "Esperando respuesta..."
	# Función para obtener actualizaciones y buscar la respuesta
obtener_respuesta() {
local OFFSET=0
local RESPUESTA_USUARIO=""
# Bucle para verificar actualizaciones hasta que se reciba una respuesta
while [ -z "$RESPUESTA_USUARIO" ]; do
# Obtener actualizaciones
UPDATES=$(curl -s "https://api.telegram.org/bot$BOT_TOKEN/getUpdates?offset=$OFFSET&timeout=60")
# Procesar actualizaciones para encontrar respuestas al mensaje
if [ -n "$(echo $UPDATES | jq '.result')" ] && [ "$(echo $UPDATES | jq '.result | length')" -gt 0 ]; then
# Recorrer cada actualización
for i in $(seq 0 $(echo $UPDATES | jq '.result | length - 1')); do
	UPDATE_ID=$(echo $UPDATES | jq -r ".result[$i].update_id")
	# Actualizar OFFSET para la próxima consulta
		OFFSET=$((UPDATE_ID + 1))
		# Verificar si es una callback_query de nuestro mensaje
		if echo $UPDATES | jq -r ".result[$i].callback_query" | grep -q "$MESSAGE_ID"; then
			RESPUESTA_USUARIO=$(echo $UPDATES | jq -r ".result[$i].callback_query.data")
			# Confirmar la callback para que el botón deje de mostrar el indicador de carga
			CALLBACK_ID=$(echo $UPDATES | jq -r ".result[$i].callback_query.id")
			curl -s "https://api.telegram.org/bot$BOT_TOKEN/answerCallbackQuery?callback_query_id=$CALLBACK_ID" > /dev/null
			echo "$RESPUESTA_USUARIO"
			break 2
		fi
	done
fi
        # Pequeña pausa para no saturar la API
        sleep 1
    done
}
 
	# Obtener la respuesta y guardarla en una variable
	ELECCION=$(obtener_respuesta)
	echo "$ELECCION"
	if [[ "$ELECCION" == "op1" ]]; then
		echo "yes sir"
        	qm start $instance >/dev/null 2>&1	
		curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d "chat_id=$CHAT_ID" -d "text=$msg1"

	elif [[ "$ELECCION" == "op2" ]]; then
		echo "no sir"
		curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d "chat_id=$CHAT_ID" -d "text=$msg2"
	else
		echo "well what"
	fi
	
        #qm start $instance >/dev/null 2>&1

      fi
    fi
  done

  # Wait for 5 minutes. (Edit to your needs)
  echo "$(date): Pausing for 5 minutes..."
  sleep 300
done #>/var/log/ping-instances.log 2>&1
