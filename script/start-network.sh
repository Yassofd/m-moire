#!/bin/bash

set -e

# ─────────────────────────────────────────────
# Configuration du PATH Fabric
# ─────────────────────────────────────────────
FABRIC_BIN_DIR="/home/yass/backup_hyperledger/require/bin"
export PATH=$FABRIC_BIN_DIR:$PATH

BASE_DIR="/home/yass/backup_hyperledger"
CRYPTO_DIR=$BASE_DIR/consortium/crypto-config
ARTIFACTS_DIR=$BASE_DIR/consortium/channel-artifacts
CHANNEL_NAME="mychannel"
DELAY=3
MAX_RETRY=5

ORDERER_ADDRESS=orderer.orderer.com:7050
ORDERER_CA=/opt/crypto/ordererOrganizations/orderer.com/orderers/orderer.orderer.com/tls/ca.crt

# ─────────────────────────────────────────────
# FONCTIONS
# ─────────────────────────────────────────────
function waitForContainer() {
  local container=$1
  echo ">>> Attente du démarrage de $container..."
  local count=0
  until [ "$(docker inspect -f '{{.State.Running}}' $container 2>/dev/null)" == "true" ]; do
    sleep $DELAY
    count=$((count+1))
    if [ $count -ge $MAX_RETRY ]; then
      echo "[ERREUR] $container ne démarre pas après $((MAX_RETRY * DELAY))s"
      docker logs $container
      exit 1
    fi
    echo "  ... attente ($count/$MAX_RETRY)"
  done
  echo "[OK] $container est démarré"
}

function cli_exec() {
  docker exec cli bash -c "$1"
}

# ─────────────────────────────────────────────
# Vérifications préalables (sur la machine hôte)
# ─────────────────────────────────────────────
echo ""
echo ">>> Vérification des fichiers nécessaires..."

for f in \
  "$ARTIFACTS_DIR/genesis.block" \
  "$ARTIFACTS_DIR/channel.tx" \
  "$ARTIFACTS_DIR/SiegeMSPanchors.tx" \
  "$ARTIFACTS_DIR/SpokeMSPanchors.tx" \
  "$CRYPTO_DIR/ordererOrganizations/orderer.com/orderers/orderer.orderer.com/tls/ca.crt" \
  "$CRYPTO_DIR/ordererOrganizations/orderer.com/orderers/orderer.orderer.com/tls/server.crt" \
  "$CRYPTO_DIR/ordererOrganizations/orderer.com/orderers/orderer.orderer.com/tls/server.key" \
  "$CRYPTO_DIR/peerOrganizations/siege.com/peers/peer0.siege.com/tls/server.crt" \
  "$CRYPTO_DIR/peerOrganizations/siege.com/peers/peer0.siege.com/tls/server.key" \
  "$CRYPTO_DIR/peerOrganizations/siege.com/peers/peer0.siege.com/tls/ca.crt" \
  "$CRYPTO_DIR/peerOrganizations/siege.com/users/Admin@siege.com/msp/signcerts" \
  "$CRYPTO_DIR/peerOrganizations/spoke.com/peers/peer0.spoke.com/tls/server.crt" \
  "$CRYPTO_DIR/peerOrganizations/spoke.com/peers/peer0.spoke.com/tls/server.key" \
  "$CRYPTO_DIR/peerOrganizations/spoke.com/peers/peer0.spoke.com/tls/ca.crt" \
  "$CRYPTO_DIR/peerOrganizations/spoke.com/users/Admin@spoke.com/msp/signcerts"
do
  if [ ! -e "$f" ]; then
    echo "[ERREUR] Fichier/dossier manquant : $f"
    echo "         Relancez le script de génération des certificats"
    exit 1
  fi
done

echo "[OK] Tous les fichiers nécessaires sont présents"

# ─────────────────────────────────────────────
# 1. DÉMARRAGE DES CONTENEURS
# ─────────────────────────────────────────────
echo ""
echo "========================================="
echo "   1. Démarrage des conteneurs Docker    "
echo "========================================="

docker compose -f $BASE_DIR/docker/docker-compose.yaml down --volumes --remove-orphans 2>/dev/null || true
docker compose -f $BASE_DIR/docker/docker-compose.yaml up -d

waitForContainer orderer.orderer.com
waitForContainer peer0.siege.com
waitForContainer peer0.spoke.com
waitForContainer cli

echo ""
echo ">>> Pause de 5s pour laisser les nœuds s'initialiser..."
sleep 5

# ─────────────────────────────────────────────
# 2. CRÉATION DU CHANNEL
# ─────────────────────────────────────────────
echo ""
echo "========================================="
echo "   2. Création du channel : $CHANNEL_NAME "
echo "========================================="

cli_exec "CORE_PEER_ADDRESS=peer0.siege.com:7051 \
  CORE_PEER_LOCALMSPID=SiegeMSP \
  CORE_PEER_TLS_CERT_FILE=/opt/crypto/peerOrganizations/siege.com/peers/peer0.siege.com/tls/server.crt \
  CORE_PEER_TLS_KEY_FILE=/opt/crypto/peerOrganizations/siege.com/peers/peer0.siege.com/tls/server.key \
  CORE_PEER_TLS_ROOTCERT_FILE=/opt/crypto/peerOrganizations/siege.com/peers/peer0.siege.com/tls/ca.crt \
  CORE_PEER_MSPCONFIGPATH=/opt/crypto/peerOrganizations/siege.com/users/Admin@siege.com/msp \
  peer channel create \
  -o $ORDERER_ADDRESS \
  -c $CHANNEL_NAME \
  -f /opt/channel-artifacts/channel.tx \
  --outputBlock /opt/channel-artifacts/${CHANNEL_NAME}.block \
  --tls --cafile $ORDERER_CA"

echo "[OK] Channel $CHANNEL_NAME créé"

# ─────────────────────────────────────────────
# 3. PEER0.SIEGE REJOINT LE CHANNEL
# ─────────────────────────────────────────────
echo ""
echo "========================================="
echo "   3. peer0.siege.com rejoint le channel "
echo "========================================="

cli_exec "CORE_PEER_ADDRESS=peer0.siege.com:7051 \
  CORE_PEER_LOCALMSPID=SiegeMSP \
  CORE_PEER_TLS_CERT_FILE=/opt/crypto/peerOrganizations/siege.com/peers/peer0.siege.com/tls/server.crt \
  CORE_PEER_TLS_KEY_FILE=/opt/crypto/peerOrganizations/siege.com/peers/peer0.siege.com/tls/server.key \
  CORE_PEER_TLS_ROOTCERT_FILE=/opt/crypto/peerOrganizations/siege.com/peers/peer0.siege.com/tls/ca.crt \
  CORE_PEER_MSPCONFIGPATH=/opt/crypto/peerOrganizations/siege.com/users/Admin@siege.com/msp \
  peer channel join -b /opt/channel-artifacts/${CHANNEL_NAME}.block"

echo "[OK] peer0.siege.com a rejoint $CHANNEL_NAME"

# ─────────────────────────────────────────────
# 4. PEER0.SPOKE REJOINT LE CHANNEL
# ─────────────────────────────────────────────
echo ""
echo "========================================="
echo "   4. peer0.spoke.com rejoint le channel "
echo "========================================="

cli_exec "CORE_PEER_ADDRESS=peer0.spoke.com:8051 \
  CORE_PEER_LOCALMSPID=SpokeMSP \
  CORE_PEER_TLS_CERT_FILE=/opt/crypto/peerOrganizations/spoke.com/peers/peer0.spoke.com/tls/server.crt \
  CORE_PEER_TLS_KEY_FILE=/opt/crypto/peerOrganizations/spoke.com/peers/peer0.spoke.com/tls/server.key \
  CORE_PEER_TLS_ROOTCERT_FILE=/opt/crypto/peerOrganizations/spoke.com/peers/peer0.spoke.com/tls/ca.crt \
  CORE_PEER_MSPCONFIGPATH=/opt/crypto/peerOrganizations/spoke.com/users/Admin@spoke.com/msp \
  peer channel join -b /opt/channel-artifacts/${CHANNEL_NAME}.block"
echo "[OK] peer0.spoke.com a rejoint $CHANNEL_NAME"

# ─────────────────────────────────────────────
# 5. MISE À JOUR DES ANCHOR PEERS
# ─────────────────────────────────────────────
echo ""
echo "========================================="
echo "   5. Mise à jour des Anchor Peers       "
echo "========================================="

# Anchor peer Siege
cli_exec "CORE_PEER_ADDRESS=peer0.siege.com:7051 \
  CORE_PEER_LOCALMSPID=SiegeMSP \
  CORE_PEER_TLS_CERT_FILE=/opt/crypto/peerOrganizations/siege.com/peers/peer0.siege.com/tls/server.crt \
  CORE_PEER_TLS_KEY_FILE=/opt/crypto/peerOrganizations/siege.com/peers/peer0.siege.com/tls/server.key \
  CORE_PEER_TLS_ROOTCERT_FILE=/opt/crypto/peerOrganizations/siege.com/peers/peer0.siege.com/tls/ca.crt \
  CORE_PEER_MSPCONFIGPATH=/opt/crypto/peerOrganizations/siege.com/users/Admin@siege.com/msp \
  peer channel update \
  -o $ORDERER_ADDRESS \
  -c $CHANNEL_NAME \
  -f /opt/channel-artifacts/SiegeMSPanchors.tx \
  --tls --cafile $ORDERER_CA"

echo "[OK] Anchor peer Siege mis à jour"

# Anchor peer Spoke
cli_exec "CORE_PEER_ADDRESS=peer0.spoke.com:8051 \
  CORE_PEER_LOCALMSPID=SpokeMSP \
  CORE_PEER_TLS_CERT_FILE=/opt/crypto/peerOrganizations/spoke.com/peers/peer0.spoke.com/tls/server.crt \
  CORE_PEER_TLS_KEY_FILE=/opt/crypto/peerOrganizations/spoke.com/peers/peer0.spoke.com/tls/server.key \
  CORE_PEER_TLS_ROOTCERT_FILE=/opt/crypto/peerOrganizations/spoke.com/peers/peer0.spoke.com/tls/ca.crt \
  CORE_PEER_MSPCONFIGPATH=/opt/crypto/peerOrganizations/spoke.com/users/Admin@spoke.com/msp \
  peer channel update \
  -o $ORDERER_ADDRESS \
  -c $CHANNEL_NAME \
  -f /opt/channel-artifacts/SpokeMSPanchors.tx \
  --tls --cafile $ORDERER_CA"

echo "[OK] Anchor peer Spoke mis à jour"

# ─────────────────────────────────────────────
# RÉSUMÉ
# ─────────────────────────────────────────────
echo ""
echo "========================================="
echo "   Réseau opérationnel !                 "
echo "========================================="
echo ""
echo "  Channel    : $CHANNEL_NAME"
echo "  Orderer    : orderer.orderer.com:7050"
echo "  Peer Siege : peer0.siege.com:7051"
echo "  Peer Spoke : peer0.spoke.com:8051"
echo ""
echo "  Vérifier les conteneurs :"
echo "  docker ps"
echo ""
echo "Étape suivante : déployer le chaincode JS"