# Guide de Configuration des Secrets GitHub

Ce guide décrit la procédure pour configurer et stocker les secrets requis dans GitHub afin d'alimenter **Argo CD** et le cluster Kubernetes, en stricte conformité avec la politique de sécurité [normeetprojet.md](file:///d:/devia/argocd/argocd/normeetprojet.md) (*aucun secret en clair dans le code*).

---

## 📌 1. Accès à l'Interface GitHub Secrets

1. Rendez-vous sur votre repository GitHub :  
   `https://github.com/xelnagas/argocd`
2. Cliquez sur l'onglet **Settings** (Paramètres).
3. Dans le menu de gauche, développez **Secrets and variables** > **Actions**.
4. Cliquez sur le bouton vert **New repository secret**.

---

## 🔑 2. Liste des Secrets à Configurer

### 2.1. `SSH_PRIVATE_KEY` (Requis pour Argo CD)
- **Nom du secret** : `SSH_PRIVATE_KEY`
- **Description** : Clé privée SSH d'authentification pour cloner le dépôt Git depuis le serveur `192.168.1.160`.
- **Valeur** : Contenu complet de votre clé privée locale (`C:\Users\julien\.ssh\id_ed25519`) incluant les en-têtes :
  ```text
  -----BEGIN OPENSSH PRIVATE KEY-----
  ...
  -----END OPENSSH PRIVATE KEY-----
  ```

### 2.2. `KUBECONFIG` (Optionnel pour GitHub Actions)
- **Nom du secret** : `KUBECONFIG`
- **Description** : Fichier Kubeconfig encodé ou texte brut permettant au workflow GitHub Actions de communiquer avec l'API Kubernetes K3s du serveur `192.168.1.160` pour synchroniser les secrets sans intervention manuelle.

### 2.3. `JELLYFIN_ADMIN_PASSWORD` (Optionnel)
- **Nom du secret** : `JELLYFIN_ADMIN_PASSWORD`
- **Description** : Mot de passe administrateur pour l'initialisation éventuelle de services auxiliaires.

---

## 🚀 3. Consommation des Secrets dans le Cluster

Une fois les secrets saisis dans GitHub :
- Le workflow GitHub Actions [`.github/workflows/sync-secrets.yaml`](file:///d:/devia/argocd/argocd/.github/workflows/sync-secrets.yaml) peut être déclenché (manuellement via *Run workflow* ou automatiquement) pour créer ou mettre à jour le Secret `repo-argocd-git` dans le namespace `argocd`.
- Alternativement, si vous préférez appliquer le Secret manuellement depuis le serveur ou le poste local, utilisez le modèle [bootstrap/repo-secret.template.yaml](file:///d:/devia/argocd/argocd/bootstrap/repo-secret.template.yaml).
