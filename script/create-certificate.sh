#!/bin/bash

set -e  # Arrêt en cas d'erreur

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

# Vérification finale
which fabric-ca-client || { echo "[ERREUR] fabric-ca-client introuvable dans $FABRIC_BIN_DIR"; exit 1; }

echo "========================================="
echo "   Génération des certificats Fabric CA  "
echo "========================================="

# ─────────────────────────────────────────────
# VARIABLES GLOBALES
# ─────────────────────────────────────────────
export CONSORTIUM_DIR=$PWD/../consortium
export CRYPTO_DIR=$CONSORTIUM_DIR/crypto-config

export CA_SIEGE_URL=https://admin:adminpw@localhost:1010
export CA_SPOKE_URL=https://admin:adminpw@localhost:1111
export CA_ORDERER_URL=https://admin:adminpw@localhost:1212

TLS_SIEGE=$CONSORTIUM_DIR/fabric-ca/siege/tls-cert.pem
TLS_SPOKE=$CONSORTIUM_DIR/fabric-ca/spoke/tls-cert.pem
TLS_ORDERER=$CONSORTIUM_DIR/fabric-ca/ordererOrg/tls-cert.pem

# ─────────────────────────────────────────────
# FONCTIONS UTILITAIRES
# ─────────────────────────────────────────────
function createDir() {
  mkdir -p $1
  echo "[OK] Répertoire créé : $1"
}

function writeConfigYaml() {
  local MSP_DIR="$1"
  local CA_CERT
  CA_CERT=$(ls "$MSP_DIR/cacerts"/*.pem 2>/dev/null | head -1 | xargs -I{} basename {})
  if [ -z "$CA_CERT" ]; then
    echo "[WARN] Pas de cert CA trouvé dans $MSP_DIR/cacerts, config.yaml ignoré"
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
  echo "[OK] config.yaml (NodeOUs) : $MSP_DIR"
}

# ─────────────────────────────────────────────
# CRÉATION DE LA STRUCTURE DES RÉPERTOIRES
# ─────────────────────────────────────────────
echo ""
echo ">>> Création de la structure des répertoires..."

# Siege
createDir $CRYPTO_DIR/peerOrganizations/siege.com/ca
createDir $CRYPTO_DIR/peerOrganizations/siege.com/msp
createDir $CRYPTO_DIR/peerOrganizations/siege.com/msp/cacerts
createDir $CRYPTO_DIR/peerOrganizations/siege.com/tlsca
createDir $CRYPTO_DIR/peerOrganizations/siege.com/peers/peer0.siege.com
createDir $CRYPTO_DIR/peerOrganizations/siege.com/users/admin
createDir $CRYPTO_DIR/peerOrganizations/siege.com/users/Admin@siege.com

# Spoke
createDir $CRYPTO_DIR/peerOrganizations/spoke.com/ca
createDir $CRYPTO_DIR/peerOrganizations/spoke.com/msp
createDir $CRYPTO_DIR/peerOrganizations/spoke.com/msp/cacerts
createDir $CRYPTO_DIR/peerOrganizations/spoke.com/tlsca
createDir $CRYPTO_DIR/peerOrganizations/spoke.com/peers/peer0.spoke.com
createDir $CRYPTO_DIR/peerOrganizations/spoke.com/users/admin
createDir $CRYPTO_DIR/peerOrganizations/spoke.com/users/Admin@spoke.com

# Orderer
createDir $CRYPTO_DIR/ordererOrganizations/orderer.com/ca
createDir $CRYPTO_DIR/ordererOrganizations/orderer.com/msp
createDir $CRYPTO_DIR/ordererOrganizations/orderer.com/msp/cacerts
createDir $CRYPTO_DIR/ordererOrganizations/orderer.com/tlsca
createDir $CRYPTO_DIR/ordererOrganizations/orderer.com/orderers/orderer.orderer.com
createDir $CRYPTO_DIR/ordererOrganizations/orderer.com/users/admin
createDir $CRYPTO_DIR/ordererOrganizations/orderer.com/users/Admin@orderer.com


# ═══════════════════════════════════════════════════════
#                     ORGANISATION SIEGE
# ═══════════════════════════════════════════════════════
echo ""
echo "========================================="
echo "   ORGANISATION : SIEGE                  "
echo "========================================="

SIEGE_ORG_DIR=$CRYPTO_DIR/peerOrganizations/siege.com
export FABRIC_CA_CLIENT_HOME=$SIEGE_ORG_DIR/users/admin

# ── 1. Enrôlement de l'Admin CA ──
echo ""
echo ">>> [SIEGE] Enrôlement de l'admin CA..."
fabric-ca-client enroll \
  -u $CA_SIEGE_URL \
  --caname ca-siege \
  --tls.certfiles $TLS_SIEGE

# ── 2. Enregistrement des identités ──
echo ""
echo ">>> [SIEGE] Enregistrement des identités..."

# Peer0
fabric-ca-client register \
  --caname ca-siege \
  --id.name peer0.siege.com \
  --id.secret peer0pw \
  --id.type peer \
  --tls.certfiles $TLS_SIEGE

# Admin
fabric-ca-client register \
  --caname ca-siege \
  --id.name Admin@siege.com \
  --id.secret adminpw \
  --id.type admin \
  --tls.certfiles $TLS_SIEGE

# ── 3. Enrôlement du Peer0 (MSP) ──
echo ""
echo ">>> [SIEGE] Enrôlement du peer0 (MSP)..."
export FABRIC_CA_CLIENT_HOME=$SIEGE_ORG_DIR/peers/peer0.siege.com

fabric-ca-client enroll \
  -u https://peer0.siege.com:peer0pw@localhost:1010 \
  --caname ca-siege \
  --csr.names C=FR,ST=Paris,L=Paris,O=siege.com \
  -M $SIEGE_ORG_DIR/peers/peer0.siege.com/msp \
  --tls.certfiles $TLS_SIEGE

# ── 4. Enrôlement du Peer0 (TLS) ──
echo ""
echo ">>> [SIEGE] Enrôlement du peer0 (TLS)..."
fabric-ca-client enroll \
  -u https://peer0.siege.com:peer0pw@localhost:1010 \
  --caname ca-siege \
  --enrollment.profile tls \
  --csr.names C=FR,ST=Paris,L=Paris,O=siege.com \
  --csr.hosts peer0.siege.com \
  -M $SIEGE_ORG_DIR/peers/peer0.siege.com/tls \
  --tls.certfiles $TLS_SIEGE

# ── 5. Enrôlement de l'Admin (MSP) ──
echo ""
echo ">>> [SIEGE] Enrôlement de l'Admin..."
export FABRIC_CA_CLIENT_HOME=$SIEGE_ORG_DIR/users/Admin@siege.com

fabric-ca-client enroll \
  -u https://Admin@siege.com:adminpw@localhost:1010 \
  --caname ca-siege \
  --csr.names C=FR,ST=Paris,L=Paris,O=siege.com \
  -M $SIEGE_ORG_DIR/users/Admin@siege.com/msp \
  --tls.certfiles $TLS_SIEGE

# ── 6. Copie du certificat CA ──
echo ""
echo ">>> [SIEGE] Copie des certificats CA..."
cp $SIEGE_ORG_DIR/users/admin/msp/cacerts/*.pem $SIEGE_ORG_DIR/ca/ca.siege.com-cert.pem
cp $SIEGE_ORG_DIR/users/admin/msp/cacerts/*.pem $SIEGE_ORG_DIR/msp/cacerts/

# ── 7. Copie TLS CA vers MSP org-level (tlscacerts) ──
echo ""
echo ">>> [SIEGE] Copie TLS CA vers org MSP..."
mkdir -p $SIEGE_ORG_DIR/msp/tlscacerts
cp $SIEGE_ORG_DIR/peers/peer0.siege.com/tls/tlscacerts/tls-localhost-1010-ca-siege.pem \
   $SIEGE_ORG_DIR/msp/tlscacerts/ca.crt

# ── 8. Génération des config.yaml (NodeOUs) ──
echo ""
echo ">>> [SIEGE] Génération des config.yaml..."
writeConfigYaml $SIEGE_ORG_DIR/msp
writeConfigYaml $SIEGE_ORG_DIR/peers/peer0.siege.com/msp
writeConfigYaml $SIEGE_ORG_DIR/users/Admin@siege.com/msp


# ═══════════════════════════════════════════════════════
#                     ORGANISATION SPOKE
# ═══════════════════════════════════════════════════════
echo ""
echo "========================================="
echo "   ORGANISATION : SPOKE                  "
echo "========================================="

SPOKE_ORG_DIR=$CRYPTO_DIR/peerOrganizations/spoke.com
export FABRIC_CA_CLIENT_HOME=$SPOKE_ORG_DIR/users/admin

# ── 1. Enrôlement de l'Admin CA ──
echo ""
echo ">>> [SPOKE] Enrôlement de l'admin CA..."
fabric-ca-client enroll \
  -u $CA_SPOKE_URL \
  --caname ca-spoke \
  --tls.certfiles $TLS_SPOKE

# ── 2. Enregistrement des identités ──
echo ""
echo ">>> [SPOKE] Enregistrement des identités..."

# Peer0
fabric-ca-client register \
  --caname ca-spoke \
  --id.name peer0.spoke.com \
  --id.secret peer0pw \
  --id.type peer \
  --tls.certfiles $TLS_SPOKE

# Admin
fabric-ca-client register \
  --caname ca-spoke \
  --id.name Admin@spoke.com \
  --id.secret adminpw \
  --id.type admin \
  --tls.certfiles $TLS_SPOKE

# ── 3. Enrôlement du Peer0 (MSP) ──
echo ""
echo ">>> [SPOKE] Enrôlement du peer0 (MSP)..."
export FABRIC_CA_CLIENT_HOME=$SPOKE_ORG_DIR/peers/peer0.spoke.com

fabric-ca-client enroll \
  -u https://peer0.spoke.com:peer0pw@localhost:1111 \
  --caname ca-spoke \
  --csr.names C=FR,ST=Paris,L=Paris,O=spoke.com \
  -M $SPOKE_ORG_DIR/peers/peer0.spoke.com/msp \
  --tls.certfiles $TLS_SPOKE

# ── 4. Enrôlement du Peer0 (TLS) ──
echo ""
echo ">>> [SPOKE] Enrôlement du peer0 (TLS)..."
fabric-ca-client enroll \
  -u https://peer0.spoke.com:peer0pw@localhost:1111 \
  --caname ca-spoke \
  --enrollment.profile tls \
  --csr.names C=FR,ST=Paris,L=Paris,O=spoke.com \
  --csr.hosts peer0.spoke.com \
  -M $SPOKE_ORG_DIR/peers/peer0.spoke.com/tls \
  --tls.certfiles $TLS_SPOKE

# ── 5. Enrôlement de l'Admin ──
echo ""
echo ">>> [SPOKE] Enrôlement de l'Admin..."
export FABRIC_CA_CLIENT_HOME=$SPOKE_ORG_DIR/users/Admin@spoke.com

fabric-ca-client enroll \
  -u https://Admin@spoke.com:adminpw@localhost:1111 \
  --caname ca-spoke \
  --csr.names C=FR,ST=Paris,L=Paris,O=spoke.com \
  -M $SPOKE_ORG_DIR/users/Admin@spoke.com/msp \
  --tls.certfiles $TLS_SPOKE

# ── 6. Copie du certificat CA ──
echo ""
echo ">>> [SPOKE] Copie des certificats CA..."
cp $SPOKE_ORG_DIR/users/admin/msp/cacerts/*.pem $SPOKE_ORG_DIR/ca/ca.spoke.com-cert.pem
cp $SPOKE_ORG_DIR/users/admin/msp/cacerts/*.pem $SPOKE_ORG_DIR/msp/cacerts/

# ── 7. Copie TLS CA vers MSP org-level (tlscacerts) ──
echo ""
echo ">>> [SPOKE] Copie TLS CA vers org MSP..."
mkdir -p $SPOKE_ORG_DIR/msp/tlscacerts
cp $SPOKE_ORG_DIR/peers/peer0.spoke.com/tls/tlscacerts/tls-localhost-1111-ca-spoke.pem \
   $SPOKE_ORG_DIR/msp/tlscacerts/ca.crt

# ── 8. Génération des config.yaml (NodeOUs) ──
echo ""
echo ">>> [SPOKE] Génération des config.yaml..."
writeConfigYaml $SPOKE_ORG_DIR/msp
writeConfigYaml $SPOKE_ORG_DIR/peers/peer0.spoke.com/msp
writeConfigYaml $SPOKE_ORG_DIR/users/Admin@spoke.com/msp


# ═══════════════════════════════════════════════════════
#                   ORGANISATION ORDERER
# ═══════════════════════════════════════════════════════
echo ""
echo "========================================="
echo "   ORGANISATION : ORDERER                "
echo "========================================="

ORDERER_ORG_DIR=$CRYPTO_DIR/ordererOrganizations/orderer.com
export FABRIC_CA_CLIENT_HOME=$ORDERER_ORG_DIR/users/admin

# ── 1. Enrôlement de l'Admin CA ──
echo ""
echo ">>> [ORDERER] Enrôlement de l'admin CA..."
fabric-ca-client enroll \
  -u $CA_ORDERER_URL \
  --caname ca-orderer \
  --tls.certfiles $TLS_ORDERER

# ── 2. Enregistrement des identités ──
echo ""
echo ">>> [ORDERER] Enregistrement des identités..."

# Orderer node
fabric-ca-client register \
  --caname ca-orderer \
  --id.name orderer.orderer.com \
  --id.secret ordererpw \
  --id.type orderer \
  --tls.certfiles $TLS_ORDERER

# Admin Orderer
fabric-ca-client register \
  --caname ca-orderer \
  --id.name Admin@orderer.com \
  --id.secret adminpw \
  --id.type admin \
  --tls.certfiles $TLS_ORDERER

# ── 3. Enrôlement de l'Orderer (MSP) ──
echo ""
echo ">>> [ORDERER] Enrôlement de l'orderer (MSP)..."
export FABRIC_CA_CLIENT_HOME=$ORDERER_ORG_DIR/orderers/orderer.orderer.com

fabric-ca-client enroll \
  -u https://orderer.orderer.com:ordererpw@localhost:1212 \
  --caname ca-orderer \
  --csr.names C=FR,ST=Paris,L=Paris,O=orderer.com \
  -M $ORDERER_ORG_DIR/orderers/orderer.orderer.com/msp \
  --tls.certfiles $TLS_ORDERER

# ── 4. Enrôlement de l'Orderer (TLS) ──
echo ""
echo ">>> [ORDERER] Enrôlement de l'orderer (TLS)..."
fabric-ca-client enroll \
  -u https://orderer.orderer.com:ordererpw@localhost:1212 \
  --caname ca-orderer \
  --enrollment.profile tls \
  --csr.names C=FR,ST=Paris,L=Paris,O=orderer.com \
  --csr.hosts orderer.orderer.com \
  -M $ORDERER_ORG_DIR/orderers/orderer.orderer.com/tls \
  --tls.certfiles $TLS_ORDERER

# ── 5. Enrôlement de l'Admin ──
echo ""
echo ">>> [ORDERER] Enrôlement de l'Admin..."
export FABRIC_CA_CLIENT_HOME=$ORDERER_ORG_DIR/users/Admin@orderer.com

fabric-ca-client enroll \
  -u https://Admin@orderer.com:adminpw@localhost:1212 \
  --caname ca-orderer \
  --csr.names C=FR,ST=Paris,L=Paris,O=orderer.com \
  -M $ORDERER_ORG_DIR/users/Admin@orderer.com/msp \
  --tls.certfiles $TLS_ORDERER

# ── 6. Copie du certificat CA ──
echo ""
echo ">>> [ORDERER] Copie des certificats CA..."
cp $ORDERER_ORG_DIR/users/admin/msp/cacerts/*.pem $ORDERER_ORG_DIR/ca/ca.orderer.com-cert.pem
cp $ORDERER_ORG_DIR/users/admin/msp/cacerts/*.pem $ORDERER_ORG_DIR/msp/cacerts/

# ── 7. Copie TLS CA vers MSP org-level (tlscacerts) ──
echo ""
echo ">>> [ORDERER] Copie TLS CA vers org MSP..."
mkdir -p $ORDERER_ORG_DIR/msp/tlscacerts
cp $ORDERER_ORG_DIR/orderers/orderer.orderer.com/tls/tlscacerts/tls-localhost-1212-ca-orderer.pem \
   $ORDERER_ORG_DIR/msp/tlscacerts/ca.crt

# ── 8. Génération des config.yaml (NodeOUs) ──
echo ""
echo ">>> [ORDERER] Génération des config.yaml..."
writeConfigYaml $ORDERER_ORG_DIR/msp
writeConfigYaml $ORDERER_ORG_DIR/orderers/orderer.orderer.com/msp
writeConfigYaml $ORDERER_ORG_DIR/users/Admin@orderer.com/msp


echo ""
echo "========================================="
echo " Tous les certificats ont été générés !  "
echo "========================================="