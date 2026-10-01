#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script de synchronisation de l'état Jellyfin (Docker -> Kubernetes)
# Source : /stockage/library (état actif Docker)
# Destination : /stockage/k8s-jellyfin-config (état dédié Kubernetes)
# ==============================================================================

SOURCE_DIR="/stockage/library"
DEST_DIR="/stockage/k8s-jellyfin-config"

echo "=== Début de la synchronisation Jellyfin ==="
echo "Source : ${SOURCE_DIR}"
echo "Destination : ${DEST_DIR}"

if [ ! -d "${SOURCE_DIR}" ]; then
  echo "Erreur : Le répertoire source ${SOURCE_DIR} n'existe pas." >&2
  exit 1
fi

mkdir -p "${DEST_DIR}"

# Synchronisation rsync avec préservation des droits, propriétaires, horodatages
rsync -aPv --delete \
  --exclude="log/" \
  --exclude="transcodes/" \
  "${SOURCE_DIR}/" "${DEST_DIR}/"

# S'assurer que les permissions appartiennent bien à l'utilisateur UID/GID 1000 (julien)
chown -R 1000:1000 "${DEST_DIR}"

echo "=== Synchronisation terminée avec succès ==="
echo "Le conteneur Docker original reste intact et peut être démarré ou arrêté sans risque."
