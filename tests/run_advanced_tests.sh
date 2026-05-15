#!/bin/bash
# Script d'exécution des tests avancés
# Usage: ./run_advanced_tests.sh [--usb-device=/dev/sdb] [--dangerous]

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Tests Avancés LFS Builder"
echo "=========================================="

# Parse arguments
USB_DEVICE=""
DANGEROUS=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --usb-device=*)
            USB_DEVICE="${1#*=}"
            shift
            ;;
        --dangerous)
            DANGEROUS="--dangerous"
            shift
            ;;
        *)
            echo "Option inconnue: $1"
            echo "Usage: $0 [--usb-device=/dev/sdb] [--dangerous]"
            exit 1
            ;;
    esac
done

# 1. Tests unitaires (toujours)
echo ""
echo "📦 1. Tests unitaires..."
python -m pytest tests/ -m "not (network or usb or acceptance)" -v

# 2. Tests réseau (si Internet disponible)
echo ""
echo "🌐 2. Tests réseau..."
if ping -c 1 8.8.8.8 &>/dev/null; then
    python -m pytest tests/test_integration_network.py -v -m network
else
    echo "⚠️ Pas de connexion Internet - tests réseau ignorés"
fi

# 3. Tests d'acceptance (scripts shell)
echo ""
echo "🐚 3. Tests d'acceptance..."
python -m pytest tests/test_acceptance_shell.py -v -m acceptance

# 4. Tests USB (uniquement si périphérique spécifié)
if [ -n "$USB_DEVICE" ] && [ -n "$DANGEROUS" ]; then
    echo ""
    echo "⚠️⚠️⚠️ TESTS USB DESTRUCTIFS ⚠️⚠️⚠️"
    echo "Périphérique: $USB_DEVICE"
    echo "Ces tests vont EFFACER les données sur ce périphérique!"
    read -p "Continuer? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        python -m pytest tests/test_integration_usb.py -v -m usb --usb-device="$USB_DEVICE" --dangerous
    else
        echo "Tests USB ignorés"
    fi
else
    echo "💾 4. Tests USB ignorés (spécifiez --usb-device et --dangerous)"
fi

echo ""
echo "=========================================="
echo "✅ Tous les tests terminés"
echo "=========================================="