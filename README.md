# SubCipher (POC)

Un script bash pour gérer des conteneurs chiffrés LUKS avec support de clés publiques/privées et clé maître.

> **Note**: Ce projet est une preuve de concept (POC) et ne doit pas être utilisé en production sans audit de sécurité approprié.

## État du projet

- **Phase**: Proof of Concept (POC)
- **Objectif**: Démontrer la faisabilité d'un système de chiffrement avec support de clé maître
- **Limitations actuelles**:
  - Non audité pour la sécurité
  - Gestion basique des erreurs
  - Tests limités
  - Interface en ligne de commande basique

## Prérequis

- Linux
- cryptsetup
- OpenSSL
- sudo

## Installation

```bash
git clone <repository>
cd <repository>
chmod +x subcipher.sh
```

## Utilisation

Lancer le script :
```bash
./subcipher.sh
```

### Fonctionnalités principales

1. **Gestion des volumes**
   - Création de volumes chiffrés
   - Montage/démontage
   - Support de clés publiques/privées

2. **Gestion des clés**
   - Création de paires de clés
   - Création d'une clé maître
   - Ajout de clés aux volumes

3. **Points de montage**
   - Les volumes sont montés sous `/mnt/vault/`
   - Format : `/mnt/vault/nom_du_volume`

### Structure des clés

```
$HOME/.secrets/
├── master/
│   ├── priv/
│   │   └── cle_maitre.pem
│   └── pub/
│       └── cle_maitre_pub.pem
└── volume.vault/
    ├── priv/
    │   └── volume.vault_cle_privee.pem
    └── pub/
        └── volume.vault_cle_publique.pem
```

### Clé Maître et Conformité Légale

La clé maître est un mécanisme de sécurité qui permet :

- **Accès d'urgence** : Récupération des données en cas de perte des clés privées
- **Conformité légale** : Capacité de répondre aux demandes légales (subpoenas) sans compromettre la sécurité globale
- **Gestion centralisée** : Administration simplifiée des volumes chiffrés

#### Fonctionnement

1. **Structure à double clé**
   - Chaque volume a sa propre paire de clés
   - La clé maître est ajoutée comme clé secondaire

2. **Utilisation de la clé maître**
   ```bash
   # Ajouter la clé maître à un volume
   ./subcipher.sh
   # Choisir l'option 10: "Appliquer une nouvelle clé maître sur un conteneur"

   # Ouvrir un volume avec la clé maître
   ./subcipher.sh
   # Choisir l'option 9: "Ouvrir et monter un volume avec la clé maître"
   ```

#### Sécurité et Conservation

- La clé maître privée doit être stockée séparément des volumes
- Accès strictement contrôlé à la clé maître
- Conservation sécurisée (ex: coffre-fort, HSM)
- Documentation des accès à la clé maître

### Logs

Les logs sont stockés dans : `$HOME/log/subcipher.log`

## Sécurité

- Les clés privées sont stockées avec les permissions 600
- Les clés publiques avec les permissions 644
- Le dossier de logs avec les permissions 700
