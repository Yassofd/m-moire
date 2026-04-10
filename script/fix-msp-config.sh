#!/bin/bash

# ─────────────────────────────────────────────────────────────────────────────
# fix-msp-config.sh
# Ajoute les fichiers config.yaml (NodeOUs) manquants dans tous les dossiers MSP.
# À exécuter une fois si create-certificate.sh a déjà été lancé sans config.yaml.
# ─────────────────────────────────────────────────────────────────────────────

set -e

CRYPTO_DIR="/home/yass/backup_hyperledger/consortium/crypto-config"

# ─────────────────────────────────────────────
# Fonction : génère config.yaml dans un dossier MSP
# $1 = chemin du dossier MSP
# ─────────────────────────────────────────────
write_config_yaml() {
  local MSP_DIR="$1"
  local CACERTS_DIR="$MSP_DIR/cacerts"

  if [ ! -d "$CACERTS_DIR" ]; then
    echo "[SKIP] Pas de cacerts dans : $MSP_DIR"
    return
  fi

  local CA_CERT
  CA_CERT=$(ls "$CACERTS_DIR"/*.pem 2>/dev/null | head -1 | xargs -I{} basename {})

  if [ -z "$CA_CERT" ]; then
    echo "[SKIP] Aucun .pem dans $CACERTS_DIR"
    return
  fi

  cat > "$MSP_DIR/config.yaml" <<EOF
NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/${CA_CERT}
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/${CA_CERT}
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/${CA_CERT}
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/${CA_CERT}
    OrganizationalUnitIdentifier: orderer
EOF
  echo "[OK] config.yaml créé : $MSP_DIR  (cert: $CA_CERT)"
}

echo ""
echo "========================================="
echo "   Correction des config.yaml MSP        "
echo "========================================="

# ── SIEGE ──
echo ""
echo ">>> [SIEGE]"
write_config_yaml "$CRYPTO_DIR/peerOrganizations/siege.com/msp"
write_config_yaml "$CRYPTO_DIR/peerOrganizations/siege.com/peers/peer0.siege.com/msp"
write_config_yaml "$CRYPTO_DIR/peerOrganizations/siege.com/users/Admin@siege.com/msp"

# ── SPOKE ──
echo ""
echo ">>> [SPOKE]"
write_config_yaml "$CRYPTO_DIR/peerOrganizations/spoke.com/msp"
write_config_yaml "$CRYPTO_DIR/peerOrganizations/spoke.com/peers/peer0.spoke.com/msp"
write_config_yaml "$CRYPTO_DIR/peerOrganizations/spoke.com/users/Admin@spoke.com/msp"

# ── ORDERER ──
echo ""
echo ">>> [ORDERER]"
write_config_yaml "$CRYPTO_DIR/ordererOrganizations/orderer.com/msp"
write_config_yaml "$CRYPTO_DIR/ordererOrganizations/orderer.com/orderers/orderer.orderer.com/msp"
write_config_yaml "$CRYPTO_DIR/ordererOrganizations/orderer.com/users/Admin@orderer.com/msp"

echo ""
echo "========================================="
echo "  [SUCCÈS] config.yaml ajoutés partout   "
echo "========================================="
echo ""
echo "Relance maintenant : ./start-network.sh"
