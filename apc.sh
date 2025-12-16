#!/bin/bash

# Verzeichnis des Skripts ermitteln
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/apc.conf"

# Config laden
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  echo "Config-Datei $CONFIG_FILE nicht gefunden!"
  exit 1
fi


PIDFILE="/var/run/apc2mqtt_loop.pid"


# Gemeinsamer Device-Block
DEVICE_INFO='"device": {
  "identifiers": ["apc_usv_01"],
  "name": "USV",
  "manufacturer": "APC",
  "model": "Smart-UPS"
}'

shutdown_proxmox() {

    echo "Fahre gesamten Proxmox Host herunter..."
    response=$(curl -k -s -o /tmp/pve_response.json -w "%{http_code}" \
      -X POST \
      -H "Authorization: PVEAPIToken=$PVE_API_TOKEN" \
      "https://${PVE_HOST}:${PVE_PORT}/api2/json/nodes/${PVE_NODE}/status" \
      -d "command=shutdown")
}


check_timeleft_loop() {
  while true; do
    TIMELEFT=$(apcaccess status | awk '/TIMELEFT/ {printf "%.0f", $3}')
    STATUS=$(apcaccess status | awk '/STATUS/ {print $3}')

    echo "[$(date)] Status=$STATUS, Restlaufzeit=$TIMELEFT min"

    if [ "$STATUS" == "ONBATT" ] && [ "$TIMELEFT" -le 15 ]; then
      echo "Restlaufzeit <= 15 Minuten → Shutdown einleiten"
      shutdown_proxmox
      exit 0
    fi

    sleep 60
  done
}


# Hilfsfunktion für Discovery
publish_discovery() {
  local uniq_id=$1
  local name=$2
  local topic=$3
  local unit=$4
  local dev_class=$5

  local payload="{\"name\": \"$name\", \"uniq_id\": \"$uniq_id\", \"stat_t\": \"$M>
  [ -n "$unit" ] && payload+=", \"unit_of_meas\": \"$unit\""
  [ -n "$dev_class" ] && payload+=", \"dev_cla\": \"$dev_class\""
  payload+=", $DEVICE_INFO }"

  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" -r>
    -t "homeassistant/sensor/${uniq_id}/config" \
    -m "$payload"
}
publish_data() {
   publish_all_discovery

   # Werte aus apcaccess holen
   STATUS=$(apcaccess status | awk '/STATUS/ {print $3}')
   LOADPCT=$(apcaccess status | awk '/LOADPCT/ {printf "%.1f", $3}')
   TIMELEFT=$(apcaccess status | awk '/TIMELEFT/ {printf "%.1f", $3}')
   BCHARGE=$(apcaccess status | awk '/BCHARGE/ {printf "%.0f", $3}')
   SELFTEST=$(apcaccess status | awk '/SELFTEST/ {print $3}')
   FIRMWARE=$(apcaccess status | awk '/FIRMWARE/ {print $3 " " $4 " " $5 " "  $6}')
   VERSION=$(apcaccess status | awk '/VERSION/ {print $3}')
   MODEL=$(apcaccess status | awk '/MODEL/ {print $3 " " $4 " " $5 " " $6}')

   # Werte publizieren
   mosquitto_pub -h $MQTT_HOST -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PASS -t "$MQTT>
   mosquitto_pub -h $MQTT_HOST -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PASS -t "$MQTT>
   mosquitto_pub -h $MQTT_HOST -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PASS -t "$MQTT>
   mosquitto_pub -h $MQTT_HOST -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PASS -t "$MQTT>
   mosquitto_pub -h $MQTT_HOST -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PASS -t "$MQTT>
   mosquitto_pub -h $MQTT_HOST -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PASS -t "$MQTT>
   mosquitto_pub -h $MQTT_HOST -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PASS -t "$MQTT>

}
handle_event() {
  local event=$1

  case "$event" in
    powerout|onbattery)
      echo "USV läuft auf Batterie"
      publish_data

      # Loop im Hintergrund starten und PID merken
      if [ ! -f "$PIDFILE" ]; then
        check_timeleft_loop &
        echo $! > "$PIDFILE"
        echo "Loop gestartet mit PID $(cat $PIDFILE)"
      fi
      ;;
    offbattery)
      echo "USV wieder am Netz"
      publish_data

      if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        kill "$PID" 2>/dev/null
        rm -f "$PIDFILE"
        echo "Loop mit PID $PID beendet"
      fi
      ;;
    runlimit)
      echo "Unter 5 Min "
      shutdown_proxmox
      touch /home/akuerschner/runlimit.txt
      ;;
    lowbattery)
      echo "USV Batterie schwach – System fährt herunter"
      touch /home/akuerschner/lowbat.txt
      ;;

    shutdown)
      echo "USV sendet Shutdown-Signal"
      touch /home/akuerschner/shutdown.txt
      ;;

    status)
      echo "Status abfragen"
      publish_data
      ;;
    *)
      echo "Unbekanntes Event: $event"
      publish_data
      ;;
  esac
}

# Hauptlogik
if [ -n "$1" ]; then
  handle_event "$1"
else
  publish_all_discovery
  publish_data
fi



