# Backup Consortium — Réseau Hyperledger Fabric v2.5

Réseau blockchain privé et permissionné composé de deux organisations partenaires (**Siege** et **Spoke**) avec un service d'ordonnancement central (**Orderer**). Le réseau utilise le consensus **etcdraft** (Raft), la gestion d'identité via **Fabric CA**, et tourne entièrement sous **Docker**.

---

## Architecture du réseau

```
┌─────────────────────────────────────────────────────────────┐
│                   Fabric CA Services                        │
│   ca-siege (:1010)   ca-spoke (:1111)   ca-orderer (:1212) │
└──────────────────────────┬──────────────────────────────────┘
                           │ enrôlement X.509
┌──────────────────────────▼──────────────────────────────────┐
│              Réseau Docker "backup"  — mychannel            │
│                                                             │
│  orderer.orderer.com:7050   (consensus Raft)                │
│       │                                                     │
│       ├──► peer0.siege.com:7051   (SiegeMSP)               │
│       └──► peer0.spoke.com:8051   (SpokeMSP)               │
│                                                             │
│  cli  (conteneur d'administration)                          │
└─────────────────────────────────────────────────────────────┘
```

| Composant | Image | Port(s) |
|-----------|-------|---------|
| orderer.orderer.com | fabric-orderer:2.5 | 7050, 7053, 17050 |
| peer0.siege.com | fabric-peer:2.5 | 7051, 17051 |
| peer0.spoke.com | fabric-peer:2.5 | 8051, 17052 |
| cli | fabric-tools:2.5 | — |
| ca-siege | fabric-ca:1.5 | 1010 |
| ca-spoke | fabric-ca:1.5 | 1111 |
| ca-orderer | fabric-ca:1.5 | 1212 |

---

## Structure du projet

```
backup_hyperledger/
├── configtx/
│   └── configtx.yaml          # Définition des orgs, politiques, profils de canal
├── consortium/
│   ├── crypto-config/         # Certificats et clés X.509 (généré par create-certificate.sh)
│   ├── channel-artifacts/     # Genesis block, channel.tx, anchor peers tx
│   └── fabric-ca/             # Configs des serveurs Fabric CA
├── docker/
│   ├── docker-compose.yaml        # Orderer + peers + CLI
│   └── docker-compose-ca.yaml     # 3 serveurs Fabric CA
├── script/
│   ├── create-certificate.sh      # Étape 1 — enrôlement des identités
│   ├── generate_genesis.sh        # Étape 2 — génération du genesis block
│   ├── start-network.sh           # Étape 3 — démarrage + initialisation du canal
│   └── fix-msp-config.sh          # Outil de correction MSP (usage ponctuel)
├── require/
│   ├── bin/                   # Binaires Fabric (peer, orderer, configtxgen, fabric-ca-client)
│   └── install-fabric.sh      # Script de téléchargement des composants Fabric
└── chaincode-asset-transfer/  # Répertoire prévu pour le chaincode (à implémenter)
```

---

## Procédure de démarrage complète

### Prérequis

- Docker et Docker Compose installés
- Binaires Fabric présents dans `require/bin/` (lancer `require/install-fabric.sh` si absent)

### Étape 0 — Télécharger les binaires Fabric (une seule fois)

```bash
cd require
./install-fabric.sh
```

Télécharge Fabric 2.5.15 et Fabric CA 1.5.17 (binaires + images Docker).

---

### Étape 1 — Démarrer les Fabric CA

```bash
docker compose -f docker/docker-compose-ca.yaml up -d
```

Lance trois serveurs CA indépendants, un par organisation :

| CA | Organisation | Port | Credentials par défaut |
|----|-------------|------|------------------------|
| ca-siege | siege.com | 1010 | admin / adminpw |
| ca-spoke | spoke.com | 1111 | admin / adminpw |
| ca-orderer | orderer.com | 1212 | admin / adminpw |

Chaque CA dispose de son propre certificat TLS auto-signé dans `consortium/fabric-ca/<org>/tls-cert.pem`. Ce certificat est utilisé par `fabric-ca-client` pour valider la connexion HTTPS au serveur CA.

---

### Étape 2 — Générer les identités (`create-certificate.sh`)

```bash
cd script
./create-certificate.sh
```

Ce script utilise `fabric-ca-client` pour créer toutes les identités cryptographiques du réseau. Il effectue, **pour chaque organisation**, les opérations suivantes :

#### 1. Enrôlement de l'admin CA
L'admin CA (bootstrappé dans `docker-compose-ca.yaml`) s'enrôle pour obtenir ses certificats locaux. Cela donne à `fabric-ca-client` les droits nécessaires pour enregistrer de nouvelles identités.

#### 2. Enregistrement (`register`) des identités
Deux identités sont déclarées dans le CA :
- **peer0** (type `peer`) — le nœud du réseau
- **Admin@org** (type `admin`) — l'administrateur humain de l'organisation

#### 3. Enrôlement MSP du peer
Le peer s'enrôle avec ses credentials pour obtenir son certificat de signature. Cela crée le dossier `msp/` avec :
- `cacerts/` : certificat de la CA signataire
- `signcerts/` : certificat X.509 du peer
- `keystore/` : clé privée

#### 4. Enrôlement TLS du peer
Le même peer s'enrôle une seconde fois avec le profil `--enrollment.profile tls`. Cela génère un certificat **dédié aux communications TLS** (extensions différentes), stocké dans `tls/` :
- `signcerts/cert.pem` → certificat TLS du nœud
- `keystore/` → clé privée TLS
- `tlscacerts/` → **certificat de la CA TLS** (crucial pour la chaîne de confiance)

#### 5. Enrôlement MSP de l'Admin
L'administrateur humain s'enrôle pour obtenir son propre MSP, utilisé par les outils CLI pour signer les transactions d'administration.

#### 6. Copie des certificats CA dans le MSP org-level
Le certificat racine de la CA est copié dans `org/msp/cacerts/` pour que l'organisation puisse être reconnue comme membre du consortium.

#### 7. Copie du certificat TLS CA dans `msp/tlscacerts/`
**Point critique :** le certificat de la CA TLS est copié dans `org/msp/tlscacerts/`. Cette information est lue par `configtxgen` pour être embarquée dans le genesis block. Sans elle, l'orderer ne peut pas vérifier les certificats TLS des consenters Raft lors de la création du canal.

#### 8. Génération des `config.yaml` (NodeOUs)
Un fichier `config.yaml` est écrit dans chaque dossier MSP (org, peer, admin). Ce fichier active la classification des identités par **Organizational Unit (OU)** :

```yaml
NodeOUs:
  Enable: true
  PeerOUIdentifier:
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    OrganizationalUnitIdentifier: admin
  ...
```

**Pourquoi est-ce indispensable ?** Fabric 2.x utilise les NodeOUs pour savoir qui est admin, peer ou client à partir de l'OU encodé dans le certificat. Sans ce fichier, Fabric chercherait un dossier `admincerts/` explicite — qui n'existe pas dans un setup Fabric CA standard — et refuserait de démarrer avec l'erreur : `administrators must be declared when no admin ou classification is set`.

---

### Étape 3 — Générer le genesis block (`generate_genesis.sh`)

```bash
./generate_genesis.sh
```

Ce script prépare les artefacts cryptographiques et génère les fichiers de configuration du canal.

#### Préparation TLS (étape 0)
Fabric s'attend à trouver les certificats TLS sous des noms standards (`server.crt`, `server.key`, `ca.crt`). Le script normalise les noms depuis la structure générée par `fabric-ca-client` :

```
tls/signcerts/cert.pem         → tls/server.crt
tls/keystore/<hash>_sk         → tls/server.key
tls/tlscacerts/<name>.pem      → tls/ca.crt
```

Il copie également les TLS CA certs dans les MSP org-level (`msp/tlscacerts/ca.crt`) si ce n'est pas déjà fait.

#### Génération avec `configtxgen`
L'outil lit `configtx/configtx.yaml` et les dossiers MSP pour produire quatre fichiers dans `consortium/channel-artifacts/` :

| Fichier | Rôle |
|---------|------|
| `genesis.block` | Bloc de démarrage du canal système de l'orderer |
| `channel.tx` | Transaction de création du canal applicatif `mychannel` |
| `SiegeMSPanchors.tx` | Déclaration de `peer0.siege.com` comme anchor peer |
| `SpokeMSPanchors.tx` | Déclaration de `peer0.spoke.com` comme anchor peer |

Le **genesis block** est particulièrement important : il embarque la configuration complète des MSPs (cacerts, tlscacerts, config NodeOUs), les politiques d'accès, et la liste des consenters Raft. C'est le point de référence immuable à partir duquel toute l'histoire du canal est construite.

---

### Étape 4 — Démarrer le réseau (`start-network.sh`)

```bash
./start-network.sh
```

Ce script orchestre le démarrage complet du réseau en cinq phases :

#### 1. Vérification préalable
Contrôle que tous les fichiers nécessaires existent (genesis block, channel.tx, certificats TLS) avant de lancer quoi que ce soit.

#### 2. Démarrage des conteneurs
Lance `docker compose up` pour démarrer l'orderer, les deux peers et le CLI. Attend que chaque conteneur soit en état `running` (avec un maximum de 5 tentatives espacées de 3 secondes).

#### 3. Création du canal `mychannel`
Depuis le conteneur CLI, exécute `peer channel create` en tant qu'admin de Siege. Cette commande envoie le fichier `channel.tx` à l'orderer, qui crée le canal et retourne le bloc de genèse applicatif (`mychannel.block`).

#### 4. Join des peers
Chaque peer rejoint le canal via `peer channel join -b mychannel.block`. À partir de ce moment, les peers commencent à recevoir et valider les blocs du canal.

#### 5. Mise à jour des anchor peers
Envoie les transactions `SiegeMSPanchors.tx` et `SpokeMSPanchors.tx` à l'orderer pour déclarer les anchor peers de chaque organisation. Les anchor peers sont utilisés par le protocole **Gossip** pour la découverte des peers entre organisations.

---

## Comprendre les MSP (Membership Service Provider)

Le MSP est le mécanisme par lequel Fabric identifie et authentifie les participants. Chaque organisation a deux types de MSP :

### MSP local (sur le nœud)
Contenu dans le dossier `msp/` du peer ou de l'orderer. Contient la clé privée et le certificat de signature du nœud. Le nœud l'utilise pour signer ses messages.

### MSP de canal (dans le genesis block)
Contenu dans la configuration du canal (genesis block). Contient uniquement les certificats publics (CA certs, TLS CA certs, config NodeOUs). Les autres participants l'utilisent pour **vérifier** les messages signés par ce nœud.

### Structure d'un dossier MSP complet

```
msp/
├── cacerts/          # Certificat racine de la CA signataire
├── tlscacerts/       # Certificat racine de la CA TLS
├── signcerts/        # Certificat X.509 du nœud
├── keystore/         # Clé privée (local uniquement)
└── config.yaml       # Activation des NodeOUs
```

---

## Explication du `configtx.yaml`

Fichier central qui définit le réseau pour `configtxgen`. Il contient :

- **Organizations** : les trois organisations avec leurs MSPDir, leurs politiques d'accès (Readers/Writers/Admins) et leurs anchor peers
- **Capabilities** : versions des fonctionnalités activées (Application V2_5, Orderer V2_0, Channel V2_0)
- **Orderer** : type de consensus (etcdraft), liste des consenters avec leurs certificats TLS, paramètres de batch
- **Profiles** : combinaisons prédéfinies utilisées par `configtxgen`
  - `TwoOrgsOrdererGenesis` : pour le genesis block du canal système
  - `TwoOrgsChannel` : pour le canal applicatif `mychannel`

---

## Bugs corrigés et explications

### Bug 1 — `cp: fichier identique` dans `generate_genesis.sh`
**Symptôme :** erreur lors d'un second lancement du script.  
**Cause :** `find *_sk` retournait `priv_sk` (déjà créé lors du premier lancement), et `cp` refusait de copier un fichier sur lui-même.  
**Correction :** ajout de `-not -name "priv_sk"` dans la commande `find`.

### Bug 2 — `sleep: missing operand` dans `start-network.sh`
**Symptôme :** le script s'arrêtait après le démarrage des conteneurs.  
**Cause :** `sleep` appelé sans argument (`sleep ` au lieu de `sleep 5`).  
**Correction :** remplacement par `sleep 5`.

### Bug 3 — `administrators must be declared when no admin ou classification is set`
**Symptôme :** les peers et l'orderer refusaient de démarrer.  
**Cause :** `create-certificate.sh` n'écrivait pas de `config.yaml` dans les dossiers MSP. Sans NodeOUs activés, Fabric cherche un dossier `admincerts/` — absent dans un setup Fabric CA.  
**Correction :** ajout de la fonction `writeConfigYaml()` qui génère le `config.yaml` avec NodeOUs activés dans chaque dossier MSP (org, peer, admin).

### Bug 4 — `x509: certificate signed by unknown authority` à la création du canal
**Symptôme :** `peer channel create` échouait avec une erreur de certificat TLS non reconnu.  
**Cause :** les dossiers `msp/tlscacerts/` des organisations étaient vides. `configtxgen` n'embarquait donc pas les TLS CA certs dans le genesis block. L'orderer ne pouvait pas vérifier les certificats TLS des consenters Raft déclarés dans la config du canal.  
**Correction :** ajout d'une étape dans `create-certificate.sh` et `generate_genesis.sh` pour copier les TLS CA certs dans `org/msp/tlscacerts/ca.crt` avant la génération du genesis block.

---

## Procédure de reset complet

Si tu veux repartir de zéro (re-générer tous les certificats) :

```bash
# 1. Arrêter tous les conteneurs
docker compose -f docker/docker-compose.yaml down -v
docker compose -f docker/docker-compose-ca.yaml down -v

# 2. Supprimer le crypto-config et les artifacts
rm -rf consortium/crypto-config consortium/channel-artifacts

# 3. Redémarrer les CAs
docker compose -f docker/docker-compose-ca.yaml up -d

# 4. Regénérer les identités
cd script && ./create-certificate.sh

# 5. Générer le genesis block
./generate_genesis.sh

# 6. Démarrer le réseau
./start-network.sh
```

---

## Prochaine étape — Déployer le chaincode

Le répertoire `chaincode-asset-transfer/` est prévu pour accueillir le chaincode (contrat intelligent). Le déploiement suivra le cycle de vie Fabric 2.x :

```bash
# Dans le conteneur CLI :
peer lifecycle chaincode package
peer lifecycle chaincode install
peer lifecycle chaincode approveformyorg
peer lifecycle chaincode commit
```
