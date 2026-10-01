# Plan d'Action : Repository GitOps Argo CD pour Jellyfin (Port 8097)

Ce document définit la structure, le contenu et les étapes de construction de ce **repository GitOps dédié à Argo CD**.

> [!IMPORTANT]
> **Périmètre strict du projet** :  
> Ce projet a pour **unique objectif de concevoir, structurer et versionner le repository GitOps** (manifests Kubernetes, Kustomize, configuration de l'application Argo CD et gestion des secrets via GitHub).  
> **Aucune commande ni action n'est exécutée sur le serveur distant `192.168.1.160`** par ce projet. Les opérations sur le serveur (création du repo bare, bootstrap local) sont des prérequis administratifs documentés en annexe.

---

## 📌 1. Spécifications & Choix d'Architecture GitOps

### 1.1. Données de Référence de l'Environnement Cible
Les spécifications suivantes sont intégrées dans les manifests du repository pour assurer la continuité de service et la compatibilité totale avec le Jellyfin existant :
- **Serveur Git cible** : `ssh://julien@192.168.1.160/home/julien/argocd.git`
- **Authentification SSH** : Clé utilisateur `id_ed25519`
- **Gestionnaire des secrets** : **GitHub Secrets** (`Settings > Secrets and variables > Actions`)
- **Nœud d'exécution Kubernetes** : `linux2` (`192.168.1.160`) via `nodeSelector`
- **Exposition réseau local** : Port **`8097`** (Service K8s `LoadBalancer` ➔ port conteneur `8096`)
- **Stockage de configuration** : Répertoire dédié `/stockage/k8s-jellyfin-config` (duplicata étanche de `/stockage/library` pour garantir l'indépendance du conteneur Docker original)
- **Stockage médias** : Montages transparents vers `/data/montage1`, `/data/montage2`, `/data/montage3`, `/data/stockage`
- **Image applicative** : `lscr.io/linuxserver/jellyfin:10.11.11-ls44` (tag immuable conforme à [normeetprojet.md](file:///d:/devia/argocd/argocd/normeetprojet.md))
- **Droits internes** : `PUID=1000`, `PGID=1000`

---

## 🔐 2. Gestion des Secrets avec GitHub (Conformité Sécurité)

Conformément à la section 4 de [normeetprojet.md](file:///d:/devia/argocd/argocd/normeetprojet.md) (*aucun secret en clair commité dans Git*), **GitHub est utilisé comme coffre-fort de secrets**.

### 2.1. Secrets Stockés dans GitHub
Dans le repository GitHub (`Settings > Secrets and variables > Actions > Repository secrets`) :

| Nom du Secret GitHub | Description | Destination Kubernetes |
| :--- | :--- | :--- |
| `SSH_PRIVATE_KEY` | Clé privée Ed25519 de `julien` (`id_ed25519`) pour cloner le repo Git | Secret `repo-argocd-git` (namespace `argocd`) |
| `JELLYFIN_ADMIN_PASSWORD` | Mot de passe administrateur initial (optionnel) | Secret `jellyfin-credentials` (namespace `jellyfin`) |
| `KUBECONFIG` | Fichier kubeconfig d'accès au cluster (pour synchronisation CI/CD) | Utilisé par GitHub Actions pour alimenter le cluster |

### 2.2. Mécanisme d'Injection des Secrets
Pour faire le pont entre les secrets stockés sur GitHub et le cluster Kubernetes, deux mécanismes complémentaires sont intégrés :

1. **Workflow GitHub Actions (`.github/workflows/sync-secrets.yaml`)** :
   - Récupère les secrets depuis les variables chiffrées de GitHub.
   - Génère et applique de manière sécurisée les Secrets Kubernetes nécessaires (`repo-argocd-git` et secrets applicatifs) sans jamais les écrire en clair dans l'arborescence Git.
2. **Modèle External Secrets / Sealed Secrets (pour GitOps natif)** :
   - Fichier manifest décrivant la structure attendue du secret pour Argo CD et l'application.

---

## 🗂️ 3. Structure Cible du Repository

Le repository est structuré conformément à la charte [normeetprojet.md](file:///d:/devia/argocd/argocd/normeetprojet.md) :

```text
.
├── .github/                                   # Intégration GitHub & CI/CD
│   └── workflows/
│       ├── validate.yaml                      # Linter Kustomize & conformité PR
│       └── sync-secrets.yaml                  # Déploiement sécurisé des secrets GitHub
│
├── apps/                                      # Déclarations des Applications Argo CD
│   └── workloads/
│       └── jellyfin.yaml                      # Application CRD Argo CD pour Jellyfin
│
├── manifests/                                 # Manifests Kubernetes applicatifs (Kustomize)
│   └── workloads/
│       └── jellyfin/
│           ├── base/                          # Configuration socle mutualisée
│           │   ├── deployment.yaml            # Pod Jellyfin (image immuable, nodeSelector, probes)
│           │   ├── service.yaml               # Service LoadBalancer (port 8097 -> 8096)
│           │   ├── pv-pvc.yaml                # PV & PVC pour la configuration et les médias
│           │   └── kustomization.yaml         # Déclaration des ressources et labels standards
│           └── overlays/
│               └── prod/                      # Déclinaison spécifique environnement production
│                   └── kustomization.yaml     # Namespace jellyfin & configuration de prod
│
├── bootstrap/                                 # Modèles d'initialisation et secrets
│   ├── github-secrets-guide.md                # Guide de configuration des secrets dans GitHub
│   └── repo-secret.template.yaml              # Modèle de Secret Argo CD pour la clé SSH
│
├── scripts/                                   # Scripts utilitaires locaux
│   └── sync-jellyfin-state.sh                 # Script de synchronisation d'état (à usage admin)
│
├── normeetprojet.md                           # Normes et directives d'architecture
├── README.md                                  # Présentation du repository
└── actions.md                                 # Ce document de cadrage
```

---

## 📋 4. Plan de Réalisation du Repository (Actions Locales)

Toutes les étapes ci-dessous sont réalisées **exclusivement en local dans ce repository**.

### Étape 1 : Création des Manifests Kustomize Base (`manifests/workloads/jellyfin/base/`)

#### 1.1. `pv-pvc.yaml`
- Déclaration du `PersistentVolume` (`hostPath: /stockage/k8s-jellyfin-config`) et de son `PersistentVolumeClaim` associé (`jellyfin-config-pvc`) pour isoler l'état Kubernetes de Docker.
- Déclaration des volumes pour les disques médias (`/montage1`, `/montage2`, `/montage3`, `/stockage`).

#### 1.2. `deployment.yaml`
- Image : `lscr.io/linuxserver/jellyfin:10.11.11-ls44`
- Ciblage du nœud : `nodeSelector: kubernetes.io/hostname: linux2`
- Variables d'environnement :
  - `PUID: "1000"`
  - `PGID: "1000"`
  - `TZ: "Etc/UTC"`
  - `JELLYFIN_PublishedServerUrl: "http://192.168.1.160:8097"`
- Montages de volumes :
  - `/config` ➔ volume `jellyfin-config`
  - `/data/montage1` ➔ volume `montage1`
  - `/data/montage2` ➔ volume `montage2`
  - `/data/montage3` ➔ volume `montage3`
  - `/data/stockage` ➔ volume `stockage`
- Sondes de vie et disponibilité (`startupProbe`, `readinessProbe`, `livenessProbe`) sur `/health` port 8096.
- Dimensionnement des ressources (`requests` / `limits`).

#### 1.3. `service.yaml`
- Type : `LoadBalancer`
- Ports :
  - `name: http`
  - `port: 8097` (exposition sur le LAN)
  - `targetPort: 8096` (port conteneur)

#### 1.4. `kustomization.yaml` (Base)
- Inclusion des ressources `deployment.yaml`, `service.yaml`, `pv-pvc.yaml`.
- Labels communs : `app.kubernetes.io/name: jellyfin`, `app.kubernetes.io/component: media-server`, etc.

---

### Étape 2 : Création de l'Overlay Production (`manifests/workloads/jellyfin/overlays/prod/`)
- `kustomization.yaml` configurant le namespace cible `jellyfin` et héritant de `../../base`.

---

### Étape 3 : Création de l'Application Argo CD (`apps/workloads/jellyfin.yaml`)
Déclaration de l'objet `Application` Argo CD :
- `source.repoURL`: `ssh://julien@192.168.1.160/home/julien/argocd.git`
- `source.targetRevision`: `main`
- `source.path`: `manifests/workloads/jellyfin/overlays/prod`
- `destination.server`: `https://kubernetes.default.svc`
- `destination.namespace`: `jellyfin`
- `syncPolicy.automated`: `prune: true`, `selfHeal: true`, `CreateNamespace=true`

---

### Étape 4 : Gestion des Secrets GitHub & Workflows CI/CD
1. **Guide de configuration GitHub Secrets** : [bootstrap/github-secrets-guide.md](file:///d:/devia/argocd/argocd/bootstrap/github-secrets-guide.md) détaillant la création des secrets dans l'interface GitHub.
2. **Workflow GitHub Actions de synchronisation des secrets** : [`.github/workflows/sync-secrets.yaml`](file:///d:/devia/argocd/argocd/.github/workflows/sync-secrets.yaml) pour injecter les secrets GitHub vers le namespace `argocd`.
3. **Template de Secret** : [bootstrap/repo-secret.template.yaml](file:///d:/devia/argocd/argocd/bootstrap/repo-secret.template.yaml) pour le schéma du Secret Argo CD.

---

### Étape 5 : Validation Statique Locale
Exécution en local de la commande de validation Kustomize :
```powershell
kubectl kustomize manifests/workloads/jellyfin/overlays/prod
```
Vérification que l'ensemble des manifests compilent parfaitement et respectent la charte [normeetprojet.md](file:///d:/devia/argocd/argocd/normeetprojet.md).

---

### Étape 6 : Commit Git Local
Finalisation de l'état du repository avec un commit propre documentant l'arborescence complète.

---

## 📖 Annexe : Guide Administrateur (Opérations Externes Hors-Scope)

*Ces étapes sont fournies à titre indicatif pour l'administrateur du cluster. Elles ne sont pas exécutées par ce projet.*

1. **Sur GitHub : Enregistrer les secrets**
   - Se rendre sur `https://github.com/xelnagas/argocd/settings/secrets/actions`
   - Ajouter `SSH_PRIVATE_KEY` avec le contenu de `id_ed25519`.

2. **Sur le serveur `192.168.1.160` : Préparer le dépôt bare**
   ```bash
   mkdir -p /home/julien/argocd.git && git init --bare /home/julien/argocd.git
   ```

3. **Sur le serveur `192.168.1.160` : Initialiser la copie d'état Jellyfin**
   ```bash
   mkdir -p /stockage/k8s-jellyfin-config
   rsync -aPv --delete /stockage/library/ /stockage/k8s-jellyfin-config/
   chown -R 1000:1000 /stockage/k8s-jellyfin-config
   ```

4. **Depuis ce poste : Pousser le repository**
   ```powershell
   git remote add server ssh://julien@192.168.1.160/home/julien/argocd.git
   git push -u server main
   ```

5. **Déployer l'application dans Argo CD**
   ```bash
   kubectl apply -f apps/workloads/jellyfin.yaml
   ```

---

## ✅ Checklist du Projet

- [x] **Tâche 1** : Création de l'arborescence des dossiers (`.github/workflows/`, `apps/`, `manifests/`, `bootstrap/`).
- [x] **Tâche 2** : Écriture de `manifests/workloads/jellyfin/base/pv-pvc.yaml`.
- [x] **Tâche 3** : Écriture de `manifests/workloads/jellyfin/base/deployment.yaml`.
- [x] **Tâche 4** : Écriture de `manifests/workloads/jellyfin/base/service.yaml`.
- [x] **Tâche 5** : Écriture de `manifests/workloads/jellyfin/base/kustomization.yaml`.
- [x] **Tâche 6** : Écriture de `manifests/workloads/jellyfin/overlays/prod/kustomization.yaml`.
- [x] **Tâche 7** : Écriture de `apps/workloads/jellyfin.yaml`.
- [x] **Tâche 8** : Création de la documentation des secrets GitHub (`bootstrap/github-secrets-guide.md`) et des workflows `.github/workflows/`.
- [x] **Tâche 9** : Validation locale `kubectl kustomize`.
- [x] **Tâche 10** : Commit Git local des modifications.
