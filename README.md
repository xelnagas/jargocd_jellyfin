# Repository GitOps Argo CD - Jellyfin (Port 8097)

Ce repository constitue la **source unique de vérité (Single Source of Truth - SSoT)** pour le déploiement GitOps de **Jellyfin** via **Argo CD**.

---

## 📌 Architecture & Spécifications

- **Application** : Jellyfin Media Server (`lscr.io/linuxserver/jellyfin:10.11.11-ls44`)
- **Port d'exposition local** : **`8097`** (via Service `LoadBalancer` natif K3s Klipper)
- **Port conteneur interne** : `8096`
- **Nœud d'exécution** : Assignation stricte sur `linux2` (`nodeSelector: kubernetes.io/hostname: linux2`)
- **Volume de configuration** : `/stockage/k8s-jellyfin-config` (duplicata indépendant de `/stockage/library` pour préserver le conteneur Docker original)
- **Volumes médias** : Montages transparents vers `/data/montage1`, `/data/montage2`, `/data/montage3`, `/data/stockage`
- **Gestion des Secrets** : **GitHub Secrets** (`SSH_PRIVATE_KEY`, etc.) — aucun secret en clair commité.

---

## 🗂️ Structure du Dépôt

```text
.
├── .github/                                   # Intégration GitHub Actions & CI/CD
│   └── workflows/
│       ├── validate.yaml                      # Compilation Kustomize & conformité
│       └── sync-secrets.yaml                  # Synchronisation sécurisée des secrets GitHub
│
├── apps/                                      # Déclarations des Applications Argo CD
│   └── workloads/
│       └── jellyfin.yaml                      # CRD Argo CD Application pour Jellyfin
│
├── manifests/                                 # Manifests Kubernetes (Kustomize)
│   └── workloads/
│       └── jellyfin/
│           ├── base/                          # Déclaration socle (Deployment, Service, PV/PVC)
│           │   ├── deployment.yaml            # Pod Jellyfin (image immuable, probes, resources)
│           │   ├── service.yaml               # Exposition port 8097 (LoadBalancer)
│           │   ├── pv-pvc.yaml                # Persistance /config et montages disques
│           │   └── kustomization.yaml         # Assemblage base et labels
│           └── overlays/
│               └── prod/                      # Overlay spécifique à l'environnement de production
│                   └── kustomization.yaml     # Namespace jellyfin
│
├── bootstrap/                                 # Modèles d'initialisation et guides
│   ├── github-secrets-guide.md                # Guide pas-à-pas pour les secrets GitHub
│   └── repo-secret.template.yaml              # Template Secret SSH pour Argo CD
│
├── scripts/                                   # Utilitaires locaux d'administration
│   └── sync-jellyfin-state.sh                 # Script rsync pour copier l'état Docker vers K8s
│
├── normeetprojet.md                           # Normes d'architecture GitOps
├── actions.md                                 # Plan d'action détaillé du projet
└── README.md                                  # Ce document
```

---

## 🚀 Utilisation & Déploiement

### 1. Validation Locale des Manifests
Pour compiler et vérifier les manifests Kubernetes sans cluster :
```bash
kubectl kustomize manifests/workloads/jellyfin/overlays/prod
```

### 2. Configuration des Secrets
Consultez le guide [bootstrap/github-secrets-guide.md](file:///d:/devia/argocd/argocd/bootstrap/github-secrets-guide.md) pour enregistrer la clé SSH (`SSH_PRIVATE_KEY`) dans GitHub Secrets.

### 3. Synchronisation Argo CD
L'application Argo CD déclarée dans [apps/workloads/jellyfin.yaml](file:///d:/devia/argocd/argocd/apps/workloads/jellyfin.yaml) synchronise automatiquement le dossier `manifests/workloads/jellyfin/overlays/prod` avec le cluster dès qu'un commit est poussé sur la branche `main`.
>>>>>>> 0247e60 (feat(gitops): initialisation du repository argocd jellyfin port 8097 et secrets github)
