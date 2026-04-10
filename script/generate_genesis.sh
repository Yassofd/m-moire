#!/bin/bash

set -e

# ─────────────────────────────────────────────
# Configuration du PATH Fabric
# ─────────────────────────────────────────────
FABRIC_BIN_DIR="/home/yass/backup_hyperledger/require/bin"

if [ ! -d "$FABRIC_BIN_DIR" ]; then
  echo "[ERREUR] Répertoire des binaires introuvable : $FABRIC_BIN_DIR"
  exit 1
fi

export PATH=$FABRIC_BIN_DIR:$PATH
echo "[OK] Binaires Fabric chargés depuis : $FABRIC_BIN_DIR"

which configtxgen || { echo "[ERREUR] configtxgen introuvable"; exit 1; }

BASE_DIR="/home/yass/backup_hyperledger"
CRYPTO_DIR=$BASE_DIR/consortium/crypto-config
OUTPUT_DIR=$BASE_DIR/consortium/channel-artifacts
export FABRIC_CFG_PATH=$BASE_DIR/configtx

# ═══════════════════════════════════════════════════════
#   ÉTAPE 0 — COPIE ET RENOMMAGE DES CERTIFICATS TLS
# ═══════════════════════════════════════════════════════
echo ""
echo "========================================="
echo "   0. Préparation des certificats TLS    "
echo "========================================="

# ── SIEGE TLS ──
echo ""
echo ">>> [SIEGE] Copie des certificats TLS..."
TLS_SIEGE=$CRYPTO_DIR/peerOrganizations/siege.com/peers/peer0.siege.com/tls

if [ ! -f "$TLS_SIEGE/signcerts/cert.pem" ]; then
  echo "[ERREUR] Certificats SIEGE non générés. Relancez le script register_enroll.sh"
  exit 1
fi

cp $TLS_SIEGE/signcerts/cert.pem $TLS_SIEGE/server.crt
cp $TLS_SIEGE/tlscacerts/tls-localhost-1010-ca-siege.pem $TLS_SIEGE/ca.crt

SK_SIEGE=$(find $TLS_SIEGE/keystore -name "*_sk" | head -1)
if [ -z "$SK_SIEGE" ]; then
  echo "[ERREUR] Clé privée TLS peer0.siege.com introuvable"
  exit 1
fi
cp $SK_SIEGE $TLS_SIEGE/server.key
echo "[OK] TLS peer0.siege.com : server.crt / server.key / ca.crt"

# ── SPOKE TLS ──
echo ""
echo ">>> [SPOKE] Copie des certificats TLS..."
TLS_SPOKE=$CRYPTO_DIR/peerOrganizations/spoke.com/peers/peer0.spoke.com/tls

if [ ! -f "$TLS_SPOKE/signcerts/cert.pem" ]; then
  echo "[ERREUR] Certificats SPOKE non générés. Relancez le script register_enroll.sh"
  exit 1
fi

cp $TLS_SPOKE/signcerts/cert.pem $TLS_SPOKE/server.crt
cp $TLS_SPOKE/tlscacerts/tls-localhost-1111-ca-spoke.pem $TLS_SPOKE/ca.crt

SK_SPOKE=$(find $TLS_SPOKE/keystore -name "*_sk" | head -1)
if [ -z "$SK_SPOKE" ]; then
  echo "[ERREUR] Clé privée TLS peer0.spoke.com introuvable"
  exit 1
fi
cp $SK_SPOKE $TLS_SPOKE/server.key
echo "[OK] TLS peer0.spoke.com : server.crt / server.key / ca.crt"

# ── ORDERER TLS ──
echo ""
echo ">>> [ORDERER] Copie des certificats TLS..."
TLS_ORDERER=$CRYPTO_DIR/ordererOrganizations/orderer.com/orderers/orderer.orderer.com/tls

if [ ! -f "$TLS_ORDERER/signcerts/cert.pem" ]; then
  echo "[ERREUR] Certificats ORDERER non générés. Relancez le script register_enroll.sh"
  exit 1
fi

cp $TLS_ORDERER/signcerts/cert.pem $TLS_ORDERER/server.crt
cp $TLS_ORDERER/tlscacerts/tls-localhost-1212-ca-orderer.pem $TLS_ORDERER/ca.crt

SK_ORDERER=$(find $TLS_ORDERER/keystore -name "*_sk" | head -1)
if [ -z "$SK_ORDERER" ]; then
  echo "[ERREUR] Clé privée TLS orderer introuvable"
  exit 1
fi
cp $SK_ORDERER $TLS_ORDERER/server.key
echo "[OK] TLS orderer.orderer.com : server.crt / server.key / ca.crt"

# ── TLS CA → MSP org-level tlscacerts ──
echo ""
echo ">>> Copie des TLS CA certs dans les MSP org-level (tlscacerts)..."

mkdir -p $CRYPTO_DIR/ordererOrganizations/orderer.com/msp/tlscacerts
cp $TLS_ORDERER/tlscacerts/tls-localhost-1212-ca-orderer.pem \
   $CRYPTO_DIR/ordererOrganizations/orderer.com/msp/tlscacerts/ca.crt
echo "[OK] orderer.com/msp/tlscacerts/ca.crt"

mkdir -p $CRYPTO_DIR/peerOrganizations/siege.com/msp/tlscacerts
cp $TLS_SIEGE/tlscacerts/tls-localhost-1010-ca-siege.pem \
   $CRYPTO_DIR/peerOrganizations/siege.com/msp/tlscacerts/ca.crt
echo "[OK] siege.com/msp/tlscacerts/ca.crt"

mkdir -p $CRYPTO_DIR/peerOrganizations/spoke.com/msp/tlscacerts
cp $TLS_SPOKE/tlscacerts/tls-localhost-1111-ca-spoke.pem \
   $CRYPTO_DIR/peerOrganizations/spoke.com/msp/tlscacerts/ca.crt
echo "[OK] spoke.com/msp/tlscacerts/ca.crt"

# ── MSP — clés privées ──
echo ""
echo ">>> Copie des clés privées MSP..."

SK=$(find $CRYPTO_DIR/peerOrganizations/siege.com/peers/peer0.siege.com/msp/keystore -name "*_sk" -not -name "priv_sk" | head -1)
[ -n "$SK" ] && cp $SK $CRYPTO_DIR/peerOrganizations/siege.com/peers/peer0.siege.com/msp/keystore/priv_sk

SK=$(find $CRYPTO_DIR/peerOrganizations/spoke.com/peers/peer0.spoke.com/msp/keystore -name "*_sk" -not -name "priv_sk" | head -1)
[ -n "$SK" ] && cp $SK $CRYPTO_DIR/peerOrganizations/spoke.com/peers/peer0.spoke.com/msp/keystore/priv_sk

SK=$(find $CRYPTO_DIR/ordererOrganizations/orderer.com/orderers/orderer.orderer.com/msp/keystore -name "*_sk" -not -name "priv_sk" | head -1)
[ -n "$SK" ] && cp $SK $CRYPTO_DIR/ordererOrganizations/orderer.com/orderers/orderer.orderer.com/msp/keystore/priv_sk

echo "[OK] Clés privées MSP copiées"

# ── Vérification finale TLS ──
echo ""
echo ">>> Vérification des fichiers TLS..."
for f in \
  "$TLS_SIEGE/server.crt"   "$TLS_SIEGE/server.key"   "$TLS_SIEGE/ca.crt" \
  "$TLS_SPOKE/server.crt"   "$TLS_SPOKE/server.key"   "$TLS_SPOKE/ca.crt" \
  "$TLS_ORDERER/server.crt" "$TLS_ORDERER/server.key" "$TLS_ORDERER/ca.crt"
do
  if [ ! -f "$f" ]; then
    echo "[ERREUR] Fichier manquant : $f"
    exit 1
  fi
done
echo "[OK] Tous les fichiers TLS sont en place"

# ═══════════════════════════════════════════════════════
#   ÉTAPE 1 — VÉRIFICATIONS CONFIGTX
# ═══════════════════════════════════════════════════════
echo ""
echo "========================================="
echo "   1. Vérification de la configuration   "
echo "========================================="

if [ ! -f "$FABRIC_CFG_PATH/configtx.yaml" ]; then
  echo "[ERREUR] configtx.yaml introuvable dans : $FABRIC_CFG_PATH"
  exit 1
fi
echo "[OK] configtx.yaml trouvé"

if [ ! -d "$CRYPTO_DIR" ]; then
  echo "[ERREUR] crypto-config introuvable"
  exit 1
fi
echo "[OK] crypto-config trouvé"

# ─────────────────────────────────────────────
# Création du dossier de sortie
# ─────────────────────────────────────────────
mkdir -p $OUTPUT_DIR
echo "[OK] Dossier channel-artifacts : $OUTPUT_DIR"

# ═══════════════════════════════════════════════════════
#   ÉTAPE 2 — GENESIS BLOCK
# ═══════════════════════════════════════════════════════
echo ""
echo "========================================="
echo "   2. Génération du Genesis Block        "
echo "========================================="

configtxgen \
  -profile TwoOrgsOrdererGenesis \
  -channelID system-channel \
  -outputBlock $OUTPUT_DIR/genesis.block

echo "[OK] Genesis block : $OUTPUT_DIR/genesis.block"

# ═══════════════════════════════════════════════════════
#   ÉTAPE 3 — CHANNEL TRANSACTION
# ═══════════════════════════════════════════════════════
echo ""
echo "========================================="
echo "   3. Génération de la Channel TX        "
echo "========================================="

configtxgen \
  -profile TwoOrgsChannel \
  -outputCreateChannelTx $OUTPUT_DIR/channel.tx \
  -channelID mychannel

echo "[OK] Channel TX : $OUTPUT_DIR/channel.tx"

# ═══════════════════════════════════════════════════════
#   ÉTAPE 4 — ANCHOR PEERS
# ═══════════════════════════════════════════════════════
echo ""
echo "========================================="
echo "   4. Génération des Anchor Peers TX     "
echo "========================================="

configtxgen \
  -profile TwoOrgsChannel \
  -outputAnchorPeersUpdate $OUTPUT_DIR/SiegeMSPanchors.tx \
  -channelID mychannel \
  -asOrg SiegeMSP

echo "[OK] Anchor Siege : $OUTPUT_DIR/SiegeMSPanchors.tx"

configtxgen \
  -profile TwoOrgsChannel \
  -outputAnchorPeersUpdate $OUTPUT_DIR/SpokeMSPanchors.tx \
  -channelID mychannel \
  -asOrg SpokeMSP

echo "[OK] Anchor Spoke : $OUTPUT_DIR/SpokeMSPanchors.tx"

# ═══════════════════════════════════════════════════════
#   RÉSUMÉ
# ═══════════════════════════════════════════════════════
echo ""
echo "========================================="
echo "   Fichiers générés dans channel-artifacts"
echo "========================================="
ls -lh $OUTPUT_DIR

echo ""
echo "[SUCCÈS] Tout est prêt !"
echo ""
echo "Étape suivante : lancer start_network.sh"