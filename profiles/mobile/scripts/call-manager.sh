#!/bin/bash
# Script de gestion des appels pour PinePhone / Librem 5
# Compatible ModemManager

MM_BUS="org.freedesktop.ModemManager1"
MM_OBJECT="/org/freedesktop/ModemManager1/Modem/0"

# Détection automatique du modem
detect_modem() {
    mmcli -L 2>/dev/null | grep -oE '/org/freedesktop/ModemManager1/Modem/[0-9]+' | head -1
}

MODEM_PATH=$(detect_modem)

if [ -z "$MODEM_PATH" ]; then
    echo "❌ Aucun modem trouvé"
    exit 1
fi

echo "✅ Modem trouvé: $MODEM_PATH"

# Fonctions principales
make_call() {
    local number="$1"
    echo "📞 Appel vers $number..."
    mmcli -m 0 --call-create "tel:$number"
}

answer_call() {
    local call_id="$1"
    echo "✅ Réponse à l'appel $call_id"
    mmcli -c "$call_id" --accept
}

hangup_call() {
    local call_id="$1"
    echo "📴 Raccrocher $call_id"
    mmcli -c "$call_id" --hangup
}

list_calls() {
    mmcli -L
}

send_sms() {
    local number="$1"
    local message="$2"
    echo "✉️ Envoi SMS à $number..."
    mmcli -m 0 --messaging-create-sms="text='$message',number='$number'"
    # Le SMS envoyé reçoit un ID, puis il faut le lancer
}

# Écoute des événements (incoming calls)
listen_events() {
    echo "📡 Surveillance des appels entrants..."
    dbus-monitor --system "interface='org.freedesktop.ModemManager1.Modem.Voice'"
}

# Menu principal
case "$1" in
    call)      make_call "$2" ;;
    answer)    answer_call "$2" ;;
    hangup)    hangup_call "$2" ;;
    list)      list_calls ;;
    sms)       send_sms "$2" "$3" ;;
    listen)    listen_events ;;
    status)    mmcli -m 0 ;;
    *)
        echo "Usage: $0 {call|answer|hangup|list|sms|listen|status} [arguments]"
        echo ""
        echo "Examples:"
        echo "  $0 call +33123456789"
        echo "  $0 answer /org/freedesktop/ModemManager1/Call/0"
        echo "  $0 sms +33123456789 'Hello from LFS'"
        echo "  $0 status"
        ;;
esac