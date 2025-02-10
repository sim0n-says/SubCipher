#!/bin/bash

# Nom du script: SubCipher
# Auteur: Simon Bédard
# Date: 2025-02-09
# Description: Script pour gérer des conteneurs/volumes chiffrés avec LUKS en utilisant des clés publiques/privées et une clé Maître.

# Configuration des options Bash
set -e  # Arrêt en cas d'erreur
set -u  # Erreur sur variable non définie
set -o pipefail  # Erreur dans les pipelines

# Variables globales
readonly SECRETS_DIR="$HOME/.secrets"      # Dossier contenant les clés de chiffrement
readonly LOG_FILE="$HOME/log/subcipher.log"  # Fichier de journalisation
readonly CONTAINER_EXT=".vault"            # Extension des fichiers conteneurs
readonly MOUNT_ROOT="/mnt/vault"           # Point de montage racine des conteneurs
readonly KEYS_DIR="$HOME/.secrets/keys"            # Dossier contenant les clés

# Variables modifiables
mapper_name=""      # Nom du périphérique mapper
# Fonction pour journaliser les messages
log_message() {
    local message="$1"
    local log_dir=$(dirname "$LOG_FILE")
    
    # Créer le répertoire de logs si nécessaire
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir"
        chmod 700 "$log_dir"  # Permissions restrictives pour la sécurité
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') : $message" | tee -a "$LOG_FILE"
}

# Fonction pour vérifier l'espace disponible
# @param $1 Chemin du répertoire à vérifier
# @param $2 Taille requise en Mo
# @return 0 si suffisant, 1 sinon
check_available_space() {
    local path="$1"
    local required_size="$2"
    local available_space
    
    available_space="$(df --output=avail "$path" | tail -n 1)"
    if (( available_space < required_size )); then
        log_message "Error: Insufficient space available at $path (Required: ${required_size}MB, Available: ${available_space}MB)"
        return 1
    fi
    
    log_message "Sufficient space available at $path (Required: ${required_size}MB, Available: ${available_space}MB)"
    return 0
}

# Format LUKS volume
# @param $1 Volume path
# @param $2 Volume name
# @param $3 Key path
# @return void
format_luks_volume() {
    local path=$1
    local name=$2
    local key=$3

    if [ ! -f "$key" ]; then
        log_message "Error: Key file not found at $key"
        return 1
    fi

    if ! sudo cryptsetup --batch-mode luksFormat "$path/$name" --key-file "$key"; then
        log_message "Error: Failed to format LUKS volume at $path/$name"
        return 1
    fi

    log_message "LUKS volume formatted at $path/$name"
}

# Format volume as ext4
# @param $1 Mapper name
# @return void
format_ext4_volume() {
    local mapper_name=$1
    sudo mkfs.ext4 "/dev/mapper/$mapper_name"
    log_message "Volume formatted as ext4: $mapper_name"
}

# Add a LUKS key to volume
# @param $1 Volume path
# @param $2 Volume name
# @param $3 Existing key file
# @param $4 New key file to add
# @return 0 on success, 1 on failure
add_luks_key() {
    local path=$1
    local name=$2
    local key=$3
    local new_key_file=$4

    # Vérification des fichiers de clés
    if [ ! -f "$key" ]; then
        log_message "Error: Key file not found at $key"
        return 1
    fi

    if [ ! -f "$new_key_file" ]; then
        log_message "Error: New key file not found at $new_key_file"
        return 1
    fi

    # Ajout de la nouvelle clé
    if ! sudo cryptsetup luksAddKey --key-file="$key" "$path/$name" "$new_key_file"; then
        log_message "Error: Failed to add key to LUKS volume at $path/$name"
        return 1
    fi

    log_message "Key successfully added to LUKS volume at $path/$name"
    return 0
}


# Fonction pour créer le fichier conteneur chiffré
create_container() {
    local path="$1"
    local name="$2"
    local size="$3"  # Size in MB

    # Vérifie si l'espace est disponible
    if ! check_available_space "$path" "$size"; then
        log_message "Error: Insufficient space for container"
        return 1
    fi

    # Vérifie si les arguments sont présents
    if [ -z "$path" ] || [ -z "$name" ] || [ -z "$size" ]; then
        log_message "Error: Missing parameters for create_container (path: $path, name: $name, size: $size)"
        return 1
    fi

    # Crée le conteneur avec fallocate
    if ! fallocate -l "${size}M" "$path/$name"; then
        log_message "Error: Failed to create container at $path/$name"
        return 1
    fi

    log_message "Container file created at $path/$name with size ${size}MB"
    return 0
}

# Fonction pour formater le volume LUKS
format_luks() {
    local path=$1
    local name=$2
    local key=$3

    if [ ! -f "$key" ]; then
        log_message "Erreur : Le fichier de clé $key n'existe pas."
        exit 1
    fi

    sudo cryptsetup --batch-mode luksFormat "$path/$name" --key-file "$key"
    log_message "Volume LUKS formaté à $path/$name avec la clé $key."
}

# Fonction pour formater le volume en ext4
format_ext4() {
    local mapper_name=$1
    sudo mkfs.ext4 "/dev/mapper/$mapper_name"
    log_message "Volume $mapper_name formaté en ext4."
}

# Fonction pour ajouter une clé au volume LUKS
add_luks_key() {
    local path=$1
    local name=$2
    local key=$3
    local new_key_file=$4

    if [ ! -f "$key" ];then
        log_message "Erreur : Le fichier de clé $key n'existe pas."
        exit 1
    fi

    if [ ! -f "$new_key_file" ]; then
        log_message "Erreur : Le fichier de nouvelle clé $new_key_file n'existe pas."
        exit 1
    fi

    sudo cryptsetup luksAddKey --key-file="$key" "$path/$name" "$new_key_file"
    if [ $? -ne 0 ]; then
        log_message "Erreur : Impossible d'ajouter la clé au volume LUKS à $path/$name."
        exit 1
    fi
    log_message "Clé ajoutée au volume LUKS à $path/$name."
}

# Fonction pour supprimer une clé du volume LUKS
remove_luks_key() {
    local path=$1
    local name=$2
    local key=$3

    if [ ! -f "$key" ];then
        log_message "Erreur : Le fichier de clé $key n'existe pas."
        exit 1
    fi

    sudo cryptsetup luksRemoveKey "$path/$name" --key-file "$key"
    log_message "Clé supprimée du volume LUKS à $path/$name."
}

# Fonction pour ouvrir le volume LUKS
open_luks() {
    local path=$1
    local name=$2
    local key="${3:-$HOME/.secrets/$name/priv/${name}_private_key.pem}"
    
    # Check if the container exists first
    if [ ! -f "$path/$name" ]; then
        log_message "Erreur : Le conteneur $path/$name n'existe pas."
        exit 1
    fi

    # Verify the key file exists
    if [ ! -f "$key" ]; then
        log_message "Erreur : Le fichier de clé $key n'existe pas."
        read -p "Le fichier de clé par défaut n'a pas été trouvé. Veuillez fournir le chemin complet du fichier de clé : " key
        if [ ! -f "$key" ]; then
            log_message "Erreur : Le fichier de clé fourni n'existe pas."
            exit 1
        fi
    fi

    # Set mapper name if not already set
    if [ -z "${MAPPER_NAME:-}" ]; then
        MAPPER_NAME="${name}_mapper"
    fi

    # Check if mapper exists and try to close it
    if sudo cryptsetup status "$MAPPER_NAME" &>/dev/null; then
        # Check if it's mounted first
        if mount | grep -q "/dev/mapper/$MAPPER_NAME"; then
            log_message "Le volume est monté. Démontage en cours..."
            sudo umount "/dev/mapper/$MAPPER_NAME" || {
                log_message "Erreur : Impossible de démonter le volume."
                exit 1
            }
        fi
        log_message "Le périphérique $MAPPER_NAME existe déjà. Fermeture du périphérique."
        sudo cryptsetup luksClose "$MAPPER_NAME" || {
            log_message "Erreur : Impossible de fermer le mapper."
            exit 1
        }
    fi

    # Try to open the LUKS volume
    if ! sudo cryptsetup luksOpen "$path/$name" "$MAPPER_NAME" --key-file "$key"; then
        log_message "Erreur : Impossible d'ouvrir le volume LUKS à $path/$name avec la clé $key."
        exit 1
    fi
    
    log_message "Volume LUKS ouvert à $path/$name avec la clé $key."
}

# Fonction pour monter le volume LUKS
mount_luks() {
    local mapper_name=$1
    local container_name=$(basename "$mapper_name" _mapper)
    
    # Strip .vault extension properly before creating mount point
    local base_name="${container_name%$CONTAINER_EXT}"
    local mount_point="$MOUNT_ROOT/$base_name"
    
    # Créer le répertoire racine s'il n'existe pas
    if [ ! -d "$MOUNT_ROOT" ]; then
        if sudo mkdir -p "$MOUNT_ROOT"; then
            sudo chown $(whoami):$(whoami) "$MOUNT_ROOT"
            log_message "Répertoire racine $MOUNT_ROOT créé."
        else
            log_message "Erreur : Impossible de créer le répertoire racine $MOUNT_ROOT."
            exit 1
        fi
    fi

    # Créer le point de montage sans l'extension .vault
    if [ ! -d "$mount_point" ]; then
        if sudo mkdir -p "$mount_point"; then
            log_message "Répertoire de montage $mount_point créé."
        else
            log_message "Erreur : Impossible de créer le répertoire de montage $mount_point."
            exit 1
        fi
    fi

    if ! sudo mount "/dev/mapper/$mapper_name" "$mount_point"; then
        log_message "Erreur : Impossible de monter le volume $mapper_name à $mount_point."
        exit 1
    fi
    sudo chown -R $(whoami):$(whoami) "$mount_point"
    log_message "Volume $mapper_name monté à $mount_point."
}

# Fonction pour démonter le volume LUKS
unmount_luks() {
    local mount_point=$1
    sudo umount "$mount_point"
    log_message "Volume démonté de $mount_point."
}

# Fonction pour fermer le volume LUKS
close_luks() {
    local mapper_name=$1
    sudo cryptsetup luksClose "$mapper_name"
    log_message "Volume $mapper_name fermé."
}


# Fonction pour démonter tous les volumes .vault montés
unmount_all_volumes() {
    echo "Démontage de tous les volumes montés sous $MOUNT_ROOT..."
    echo "------------------------------------------------"
    
    for mount in $(mount | grep "$MOUNT_ROOT" | awk '{print $3}'); do
        if sudo umount "$mount"; then
            log_message "Volume démonté avec succès: $mount"
        else
            log_message "Erreur lors du démontage de $mount"
        fi
    done
    
    echo "------------------------------------------------"
}

# Fonction pour fermer tous les mappers des volumes .vault
close_all_mappers() {
    echo "Fermeture de tous les mappers .vault..."
    echo "------------------------------------------------"
    
    # Démonter d'abord tous les volumes
    unmount_all_volumes
    
    # Liste tous les conteneurs .vault existants
    find "$HOME" -name "*${CONTAINER_EXT}" | while read vault_file; do
        vault_name=$(basename "$vault_file")
        mapper_name="${vault_name}_mapper"  # Inclut .vault dans le nom du mapper
        
        # Vérifie si le mapper existe
        if sudo cryptsetup status "$mapper_name" &>/dev/null; then
            log_message "Fermeture du mapper: $mapper_name"
            close_luks "$mapper_name"
        fi
    done
    echo "------------------------------------------------"
}
# Fonction pour créer une paire de clés publique/privée
create_key_pair() {
    local name=$1
    local container_keys_dir="$KEYS_DIR/$name"

    mkdir -p "$container_keys_dir/priv" "$container_keys_dir/pub"

    openssl genpkey -algorithm RSA -out "$container_keys_dir/priv/${name}_private_key.pem" -pkeyopt rsa_keygen_bits:2048
    openssl rsa -pubout -in "$container_keys_dir/priv/${name}_private_key.pem" -out "$container_keys_dir/pub/${name}_cle_publique.pem"
    log_message "Paire de clés publique/privée créée à $container_keys_dir avec le nom $name."
}

# Fonction pour créer une clé maître
create_master_key() {
    local master_keys_dir="$KEYS_DIR/master"
    mkdir -p "$master_keys_dir/priv" "$master_keys_dir/pub"

    if [ -f "$master_keys_dir/priv/master_key.pem" ]; then
        read -p "La clé maître existe déjà. Voulez-vous la remplacer ? (yes/no) : " RESPONSE
        while [[ -z "$RESPONSE" || ( "$RESPONSE" != "yes" && "$RESPONSE" != "no" ) ]]; do
            read -p "La clé maître existe déjà. Voulez-vous la remplacer ? (yes/no) : " RESPONSE
        done
        if [[ "$RESPONSE" == "no" ]]; then
            log_message "Clé maître existante conservée."
            return
        fi
    fi
    
    # Créer la paire de clés maître sans passphrase
    openssl genpkey -algorithm RSA -out "$master_keys_dir/priv/master_key.pem" -pkeyopt rsa_keygen_bits:4096
    openssl rsa -pubout -in "$master_keys_dir/priv/master_key.pem" -out "$master_keys_dir/pub/master_key_pub.pem"
    
    chmod 600 "$master_keys_dir/priv/master_key.pem"
    chmod 644 "$master_keys_dir/pub/master_key_pub.pem"
    
    log_message "Paire de clés maître créée in $master_keys_dir"
}

# Fonction pour chiffrer un volume avec la clé publique
encrypt_volume() {
    local path=$1
    local name=$2
    local container_keys_dir="$KEYS_DIR/$name"

    openssl rsautl -encrypt -inkey "$container_keys_dir/pub/${name}_cle_publique.pem" -pubin -in "$path/$name" -out "$path/$name.enc"
    log_message "Volume chiffré avec la clé publique $container_keys_dir/pub/${name}_cle_publique.pem."
}

# Fonction pour déchiffrer un volume avec la clé privée
decrypt_volume() {
    local path=$1
    local encrypted_name=$2
    local container_keys_dir="$KEYS_DIR/${encrypted_name%.enc}"

    openssl rsautl -decrypt -inkey "$container_keys_dir/priv/${encrypted_name%.enc}_private_key.pem" -in "$path/$encrypted_name" -out "$path/${encrypted_name%.enc}"
    log_message "Volume déchiffré avec la clé privée $container_keys_dir/priv/${encrypted_name%.enc}_private_key.pem."
}

# Fonction pour déchiffrer un volume avec la clé maître
decrypt_master() {
    local path=$1
    local encrypted_name=$2
    local master_key="$KEYS_DIR/master/master_key.pem"

    if [ ! -f "$master_key" ]; then
        log_message "Erreur : Le fichier de clé maître $master_key n'existe pas."
        exit 1
    fi

    openssl rsautl -decrypt -inkey "$master_key" -in "$path/$encrypted_name" -out "$path/${encrypted_name%.enc}"
    log_message "Volume déchiffré avec la clé maître $master_key."
}

# Fonction pour appliquer une nouvelle clé maître sur un conteneur
apply_new_master() {
    read -p "Nom du fichier conteneur (sans extension) : " CONTAINER_NAME
    CONTAINER_NAME="${CONTAINER_NAME}${CONTAINER_EXT}"
    CONTAINER_PATH="$HOME/$CONTAINER_NAME"
    local master_keys_dir="$KEYS_DIR/master"
    local private_key="$KEYS_DIR/$CONTAINER_NAME/priv/${CONTAINER_NAME}_private_key.pem"
    local master_key="$master_keys_dir/priv/master_key.pem"

    # Vérifier l'existence des fichiers nécessaires
    if [ ! -f "$master_key" ]; then
        log_message "Erreur : La clé maître n'existe pas à $master_key"
        exit 1
    fi

    if [ ! -f "$private_key" ]; then
        log_message "Erreur : La clé privée n'existe pas à $private_key"
        exit 1
    fi

    # Ouvrir le volume avec la clé privée du conteneur
    log_message "Ouverture du volume avec la clé privée"
    open_luks "$HOME" "$CONTAINER_NAME" "$private_key"

    # Ajouter la clé maître
    log_message "Ajout de la clé maître"
    add_luks_key "$HOME" "$CONTAINER_NAME" "$master_key" "$private_key"

    close_luks "$MAPPER_NAME"
    log_message "Application de la clé maître terminée"
}

# Fonction pour créer le volume
create_volume() {
    local container_name=""
    local container_size=1024  # Default 1GB in MB
    
    read -p "Nom du fichier conteneur (sans extension) : " container_name
    if [ -z "$container_name" ]; then
        log_message "Erreur : Nom de conteneur requis"
        return 1
    fi
    container_name="${container_name}${CONTAINER_EXT}"
    
    read -p "Taille du fichier conteneur en Go [1]: " size_input
    if [ -n "$size_input" ]; then
        container_size=$((size_input * 1024))
    fi

    # Create container
    if ! create_container "$HOME" "$container_name" "$container_size"; then
        return 1
    fi
    log_message "Fichier conteneur créé."

    # Create keys
    create_key_pair "$container_name"
    log_message "Paire de clés créée."

    # Format LUKS volume
    format_luks "$HOME" "$container_name" "$KEYS_DIR/$container_name/priv/${container_name}_private_key.pem"
    log_message "Volume LUKS formaté."

    MAPPER_NAME="${container_name}_mapper"
    
    if ! open_luks "$HOME" "$container_name" "$KEYS_DIR/$container_name/priv/${container_name}_private_key.pem"; then
        return 1
    fi
    
    # Format ext4
    format_ext4 "$MAPPER_NAME"
    log_message "Volume formaté en ext4."
    
    # Mount volume
    if ! mount_luks "$MAPPER_NAME" "$MOUNT_ROOT/${container_name%$CONTAINER_EXT}"; then
        close_luks "$MAPPER_NAME"
        return 1
    fi
    log_message "Volume monté avec succès."
}
# Open and mount LUKS volume with private key
# @param void
# @return 0 on success, 1 on failure
open_volume() {
    local container_name=""
    local container_path=""
    local key_path=""
    
    read -p "Nom du fichier conteneur (sans extension) : " container_name
    
    # Validate input
    if [ -z "$container_name" ]; then
        log_message "Error: No container name provided"
        return 1
    fi
    
    # Set paths
    container_name="${container_name}${CONTAINER_EXT}"
    container_path="$HOME/$container_name"
    key_path="$KEYS_DIR/$container_name/priv/${container_name}_private_key.pem"
    
    # Check if container exists
    if [ ! -f "$container_path" ]; then
        log_message "Error: Container not found at $container_path"
        return 1
    fi
    
    # Open LUKS container
    if ! open_luks "$HOME" "$container_name" "$key_path"; then
        return 1
    fi
    
    # Mount volume
    if ! mount_luks "$MAPPER_NAME" "$MOUNT_ROOT/${container_name%$CONTAINER_EXT}"; then
        log_message "Error: Failed to mount volume"
        sudo cryptsetup luksClose "$MAPPER_NAME" 2>/dev/null
        return 1
    fi
    
    log_message "Volume successfully opened and mounted"
    return 0
}

# Fonction pour démonter et fermer le volume
# Fonction pour démonter et fermer le volume
unmount_volume() {
    echo "Volumes .vault montés :"
    echo "------------------------------------------------"
    echo "INDEX | MAPPER | POINT DE MONTAGE"
    echo "------------------------------------------------"
    
    local index=1
    local mounted_volumes=()
    
    while read -r mapper rest; do
        if [[ "$mapper" == *".vault_mapper" ]]; then
            local mount_point=$(grep "/dev/mapper/$mapper" /proc/mounts | awk '{print $2}')
            if [ -n "$mount_point" ]; then
                echo "$index) $mapper | $mount_point"
                mounted_volumes+=("$index:$mapper:$mount_point")
                ((index++))
            fi
        fi
    done <<< "$(sudo dmsetup ls --target crypt)"
    
    if [ ${#mounted_volumes[@]} -eq 0 ]; then
        echo "Aucun volume monté trouvé."
        return 1
    fi
    
    echo "------------------------------------------------"
    read -p "Entrez l'INDEX du volume à démonter : " volume_index
    
    local selected_entry=""
    for entry in "${mounted_volumes[@]}"; do
        if [[ "$entry" == "$volume_index:"* ]]; then
            selected_entry="$entry"
            break
        fi
    done
    
    if [ -z "$selected_entry" ]; then
        log_message "Erreur : INDEX invalide."
        return 1
    fi
    
    local selected_mapper=$(echo "$selected_entry" | cut -d: -f2)
    local selected_mount_point=$(echo "$selected_entry" | cut -d: -f3)
    
    if ! sudo umount "$selected_mount_point"; then
        log_message "Erreur lors du démontage de $selected_mount_point"
        return 1
    else
        log_message "Volume démonté avec succès: $selected_mount_point"
        sudo rmdir "$selected_mount_point" 2>/dev/null
    fi

    if ! sudo cryptsetup luksClose "$selected_mapper"; then
        log_message "Erreur lors de la fermeture du mapper: $selected_mapper"
        return 1
    else
        log_message "Mapper fermé avec succès: $selected_mapper"
    fi
}
# Fonction pour lister les volumes .vault montés
# @return void
# Fonction pour lister les volumes .vault montés
# @return void
# Fonction pour lister les volumes .vault montés
# @return void
list_mounted_vaults() {
    echo "Volumes .vault montés :"
    echo "------------------------------------------------"
    echo "FICHIER VAULT | MAPPER | FICHIER LOOP | POINT DE MONTAGE"
    echo "------------------------------------------------"
    
    # Liste tous les mappers cryptsetup
    sudo dmsetup ls --target crypt | while read -r mapper rest; do
        echo "Traitement du mapper: $mapper"  # Message de débogage
        
        # Vérifie si le mapper correspond à un volume .vault
        if [[ "$mapper" == *".vault_mapper" ]]; then
            vault_file=$(sudo cryptsetup status "$mapper" | grep 'device:' | awk '{print $2}')
            echo "Fichier vault trouvé: $vault_file"  # Message de débogage
            
            if [ -n "$vault_file" ]; then
                loop_file=$(sudo losetup -j "$vault_file" | awk -F: '{print $1}')
                
                if [ -z "$loop_file" ]; then
                    echo "Erreur: Impossible de trouver le fichier loop pour $vault_file"
                    continue
                fi
                echo "Fichier loop trouvé: $loop_file"  # Message de débogage
                
                mount_point=$(grep "/dev/mapper/$mapper" /proc/mounts | awk '{print $2}')
                
                if [ -z "$mount_point" ]; then
                    # Vérifie dans /mnt/vault sans l'extension .vault
                    base_name="${vault_file##*/}"
                    base_name="${base_name%.vault}"
                    mount_point=$(grep "$MOUNT_ROOT/$base_name" /proc/mounts | awk '{print $2}')
                    
                    if [ -z "$mount_point" ]; then
                        echo "Erreur: Impossible de trouver le point de montage pour $mapper"
                        continue
                    fi
                fi
                echo "Point de montage trouvé: $mount_point"  # Message de débogage
                
                if [ -n "$mount_point" ]; then
                    echo "$vault_file | $mapper | $loop_file | $mount_point"
                else
                    echo "$vault_file | $mapper | $loop_file | Non monté"
                fi
            else
                echo "Aucun fichier .vault trouvé pour le mapper $mapper"
            fi
        fi
    done
    echo "------------------------------------------------"
}

# Fonction pour lister les conteneurs avec leurs noms et emplacements
list_containers() {
    echo "Liste des conteneurs .vault disponibles :"
    echo "------------------------------------------------"
    find "$HOME" -name "*${CONTAINER_EXT}" | while read -r container; do
        echo "$container"
    done
    echo "------------------------------------------------"
}

# Fonction pour lister les clés USB disponibles
list_usb_devices() {
    echo "Périphériques USB disponibles :"
    echo "------------------------------------------------"
    lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT | grep "disk\|part"
    echo "------------------------------------------------"
}

# Fonction pour vérifier et monter un périphérique USB
check_and_mount_usb() {
    local usb_path=$1
    local usb_mount=""
    
    while [ ! -b "$usb_path" ]; do
        log_message "Erreur : Périphérique $usb_path non trouvé"
        read -p "Veuillez entrer un chemin de périphérique USB valide (ex: /dev/sdb1) : " usb_path
    done
    
    usb_mount=$(lsblk -n -o MOUNTPOINT "$usb_path")
    if [ $? -ne 0 ]; then
        log_message "Erreur : Impossible de récupérer le point de montage pour $usb_path"
        exit 1
    fi
    if [ $? -ne 0 ]; then
        log_message "Erreur : Impossible de récupérer le point de montage pour $usb_path"
        read -p "Périphérique non monté. Voulez-vous le monter ? (y/n) : " mount_response
    fi
    
    if [ -z "$usb_mount" ]; then
        read -p "Périphérique non monté. Voulez-vous le monter? (y/n) : " mount_response
        if [[ "$mount_response" == "y" ]]; then
            usb_mount="/mnt/usb_temp"
            sudo mkdir -p "$usb_mount"
            sudo mount "$usb_path" "$usb_mount"
        else
            log_message "Opération annulée"
            exit 1
        fi
    fi
    echo "$usb_mount"
}

# Fonction pour préparer le conteneur USB
prepare_usb_container() {
    local usb_mount=$1
    local container_name=$2
    local size_gb=$3
    local container_path="$usb_mount/$container_name"
    
    local container_size=$((size_gb * 1024))
    check_available_space "$usb_mount" "$container_size"
    create_container "$usb_mount" "$container_name" "$container_size"
    
    echo "$container_path"
}

# Fonction pour configurer le LUKS sur USB
setup_usb_luks() {
    local container_path=$1
    local mapper_name=$2
    check_available_space "$usb_mount" "$container_size"
    echo "Configuration du mot de passe pour le conteneur"
    sudo cryptsetup --type luks2 luksFormat "$container_path"
    sudo cryptsetup luksOpen "$container_path" "$mapper_name"
    format_ext4 "$mapper_name"
}

# Fonction principale pour créer un conteneur USB
create_usb_volume() {
    # 1. Liste et sélection du périphérique USB
    list_usb_devices
    read -p "Entrez le chemin du périphérique USB (ex: /dev/sdb1) : " USB_PATH
    
    # 2. Nom du conteneur
    read -p "Nom du fichier conteneur (sans extension) : " CONTAINER_NAME
    CONTAINER_NAME="${CONTAINER_NAME}${CONTAINER_EXT}"
    
    # 3. Vérification et montage USB
    USB_MOUNT=$(check_and_mount_usb "$USB_PATH")
    
    # 4. Taille et création du conteneur
    read -p "Taille du conteneur en Go : " CONTAINER_SIZE_GB
    CONTAINER_PATH=$(prepare_usb_container "$USB_MOUNT" "$CONTAINER_NAME" "$CONTAINER_SIZE_GB")
    
    # 5. Configuration LUKS
    MAPPER_NAME="${CONTAINER_NAME}_mapper"
    setup_usb_luks "$CONTAINER_PATH" "$MAPPER_NAME"
    
    # 6. Montage final
    mount_luks "$MAPPER_NAME" "$MOUNT_ROOT/${CONTAINER_NAME%$CONTAINER_EXT}"
    
    log_message "Conteneur USB créé avec succès à $CONTAINER_PATH"
}

# Fonction pour ouvrir un conteneur USB avec mot de passe
open_usb_volume() {
    list_usb_devices
    read -p "Entrez le chemin du périphérique USB (ex: /dev/sdb1) : " USB_PATH
    read -p "Nom du fichier conteneur (sans extension) : " CONTAINER_NAME
    CONTAINER_NAME="${CONTAINER_NAME}${CONTAINER_EXT}"
    
    # Vérifier le point de montage USB
    USB_MOUNT=$(lsblk -n -o MOUNTPOINT "$USB_PATH")
    if [ -z "$USB_MOUNT" ]; then
        read -p "Périphérique non monté. Voulez-vous le monter? (y/n) : " MOUNT_RESPONSE
        if [[ "$MOUNT_RESPONSE" == "y" ]]; then
            USB_MOUNT="/mnt/usb_temp"
            sudo mkdir -p "$USB_MOUNT"
            sudo mount "$USB_PATH" "$USB_MOUNT"
        else
            log_message "Opération annulée"
            exit 1
        fi
    fi
    
    CONTAINER_PATH="$USB_MOUNT/$CONTAINER_NAME"
    MAPPER_NAME="${CONTAINER_NAME}_mapper"
    
    # Ouvrir avec mot de passe
    sudo cryptsetup luksOpen "$CONTAINER_PATH" "$MAPPER_NAME"
    mount_luks "$MAPPER_NAME" "$MOUNT_ROOT/${CONTAINER_NAME%$CONTAINER_EXT}"
}

# Format and mount a LUKS volume
# @param $1 Container path
# @param $2 Container name
# @param $3 Key file path
# @return void
format_and_mount_volume() {
    local path=$1
    local name=$2
    local key=$3

    format_luks_volume "$path" "$name" "$key"
    log_message "LUKS volume formatted at $path/$name"

    open_luks "$path" "$name" "$key"
    log_message "LUKS volume opened"

    format_ext4_volume "$MAPPER_NAME"
    log_message "Volume formatted as ext4"

    mount_luks "$MAPPER_NAME" "$MOUNT_ROOT/${name%$CONTAINER_EXT}"
    log_message "Volume mounted successfully"
}

# Add master key to LUKS volume
# @param $1 Volume path
# @param $2 Volume name
# @param $3 Container private key
# @return void
add_master_key_to_volume() {
    local path=$1
    local name=$2
    local private_key=$3
    local MASTER_KEY="$KEYS_DIR/master/priv/master_key.pem"

    # Vérification des fichiers de clés
    if [ ! -f "$private_key" ]; then
        log_message "Error: Private key file not found"
        return 1
    fi

    if [ ! -f "$master_key" ]; then
        log_message "Error: Master key file not found"
        return 1
    fi

    add_luks_key "$path" "$name" "$master_key" "$private_key"
    if [ $? -ne 0 ]; then
        log_message "Error: Failed to add master key"
        return 1
    fi

    log_message "Master key successfully added to volume"
    return 0
}

# Open volume with master key
# @param $1 Volume path
# @param $2 Volume name
# @return void
open_volume_with_master() {
    local container_name=""
    local master_key="$KEYS_DIR/master/priv/master_key.pem"
    
    read -p "Nom du fichier conteneur (sans extension) : " container_name
    
    # Validate input
    if [ -z "$container_name" ]; then
        log_message "Error: No container name provided"
        return 1
    fi
    
    # Set paths
    container_name="${container_name}${CONTAINER_EXT}"
    container_path="$HOME/$container_name"
    
    # Check if container exists
    if [ ! -f "$container_path" ]; then
        log_message "Error: Container not found at $container_path"
        return 1
    fi
    
    # Check if master key exists
    if [ ! -f "$master_key" ]; then
        log_message "Error: Master key not found"
        return 1
    fi
    
    # Open LUKS container with master key
    if ! open_luks "$HOME" "$container_name" "$master_key"; then
        return 1
    fi
    
    # Mount volume
    if ! mount_luks "$MAPPER_NAME" "$MOUNT_ROOT/${container_name%$CONTAINER_EXT}"; then
        log_message "Error: Failed to mount volume"
        sudo cryptsetup luksClose "$MAPPER_NAME" 2>/dev/null
        return 1
    fi
    
    log_message "Volume successfully opened and mounted with master key"
    return 0
}



# Task functions for menu options
# @return void
task_create_volume() {
    read -p "Enter container name (without extension): " container_name
    container_name="${container_name}${CONTAINER_EXT}"
    read -p "Enter container size in GB: " container_size
    create_volume "$container_name" "$container_size"
}

task_create_key_pair() {
    read -p "Enter container name: " container_name
    create_key_pair "$container_name"
}

task_create_master_key() {
    create_master_key
}

task_encrypt_volume() {
    read -p "Enter volume path to encrypt: " volume_path
    read -p "Enter volume name: " volume_name
    encrypt_volume "$volume_path" "$volume_name"
}

task_decrypt_volume() {
    read -p "Enter volume path to decrypt: " volume_path
    read -p "Enter encrypted volume name (without .enc): " volume_name
    decrypt_volume "$volume_path" "${volume_name}.enc"
}

# Fonction pour afficher le menu
show_menu() {
    echo "Choisissez une tâche à exécuter :"
    echo "1) Créer un volume"
    echo "-------------------------------------------------------"
    echo "2) Créer une paire de clés"
    echo "3) Créer une clé maître"
    echo "-------------------------------------------------------"
    echo "4) Chiffrer un volume"
    echo "5) Déchiffrer un volume"
    echo "-------------------------------------------------------"
    echo "6) Ouvrir et monter un volume avec clé privée"
    echo "7) Démonter un volume"
    echo "-------------------------------------------------------"
    echo "8) Déchiffrer et monter un volume avec la clé maître"
    echo "9) Ouvrir et monter un volume avec la clé maître"
    echo "10) Appliquer une nouvelle clé maître sur un conteneur"
    echo "-------------------------------------------------------"
    echo "11) Lister les clés LUKS d'un volume"
    echo "12) Lister les volumes montés"
    echo "13) Lister les conteneurs disponibles"
    echo "-------------------------------------------------------"
    echo "14) Démonter tous les volumes"
    echo "15) Fermer tous les mappers"
    echo "16) Créer un conteneur sur USB avec mot de passe"
    echo "17) Ouvrir un conteneur USB avec mot de passe"
    echo "18) Lister les périphériques USB"
    echo "-------------------------------------------------------"
    echo "19) Quitter"
}

# Fonctions pour les tâches du menu
task_create_volume() {
    create_volume
}

task_create_key_pair() {
    read -p "Nom du fichier conteneur : " CONTAINER_NAME
    create_key_pair "$CONTAINER_NAME"
}

task_create_master_key() {
    create_master_key
}

task_encrypt_volume() {
    read -p "Entrez le chemin du volume à chiffrer : " VOLUME_A_CHIFFRER
    read -p "Entrez le nom du volume à chiffrer : " NOM_VOLUME
    encrypt_volume "$VOLUME_A_CHIFFRER" "$NOM_VOLUME"
}

task_decrypt_volume() {
    read -p "Entrez le chemin du volume à déchiffrer : " VOLUME_A_DECHIFFRER
    read -p "Entrez le nom du volume chiffré (sans extension .enc) : " NOM_VOLUME_CHIFFRE
    decrypt_volume "$VOLUME_A_DECHIFFRER" "${NOM_VOLUME_CHIFFRE}.enc"
}

task_open_volume() {
    open_volume
}

task_unmount_volume() {
    unmount_volume
}

task_decrypt_master() {
    read -p "Entrez le chemin du volume à déchiffrer : " VOLUME_A_DECHIFFRER
    read -p "Entrez le nom du volume chiffré (sans extension .enc) : " NOM_VOLUME_CHIFFRE
    decrypt_master "$VOLUME_A_DECHIFFRER" "${NOM_VOLUME_CHIFFRE}.enc"
}

task_open_master() {
    open_volume_with_master
}

task_apply_master() {
    apply_new_master
}

task_list_luks_keys() {
    list_luks_keys
}

task_list_mounted() {
    list_mounted_vaults
}

task_list_containers() {
    list_containers
}

task_unmount_all() {
    unmount_all_volumes
}

task_close_all() {
    close_all_mappers
}

task_create_usb() {
    create_usb_volume
}

task_open_usb() {
    open_usb_volume
}

task_list_usb() {
    list_usb_devices
}

# Boucle principale
while true; do
    show_menu
    read -p "Entrez le numéro de la tâche (1-19) : " TASK_NUMBER
    
    if ! [[ "$TASK_NUMBER" =~ ^[1-9]$|^1[0-9]$ ]]; then
        echo "Numéro de tâche invalide."
        continue
    fi

    case "$TASK_NUMBER" in
        1)  task_create_volume ;;
        2)  task_create_key_pair ;;
        3)  task_create_master_key ;;
        4)  task_encrypt_volume ;;
        5)  task_decrypt_volume ;;
        6)  task_open_volume ;;
        7)  task_unmount_volume ;;
        8)  task_decrypt_master ;;
        9)  task_open_master ;;
        10) task_apply_master ;;
        11) task_list_luks_keys ;;
        12) task_list_mounted ;;
        13) task_list_containers ;;
        14) task_unmount_all ;;
        15) task_close_all ;;
        16) task_create_usb ;;
        17) task_open_usb ;;
        18) task_list_usb ;;
        19) echo "Au revoir!"; exit 0 ;;
        *) echo "Numéro de tâche invalide." ;;
    esac
    
    echo
    read -p "Appuyez sur Entrée pour continuer..."
    clear
done
