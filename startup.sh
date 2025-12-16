#!/bin/bash

echo "[startup] Starte cron..."
cron

echo "[startup] Starte apcupsd..."
apcupsd
sleep 2

echo "[startup] Prüfe apcupsd Verbindung..."
if apcaccess status >/dev/null 2>&1; then
  echo "[startup] apcupsd läuft – MQTT-Skript starten..."
  /usr/local/bin/apc.sh status &
else
  echo "[startup] Fehler: apcupsd nicht erreichbar – MQTT-Skript wird nicht gestar>
fi

echo "[startup] Starte Apache im Vordergrund..."
exec apache2ctl -D FOREGROUND

