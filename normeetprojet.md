# Normes, Contraintes et Bonnes Pratiques GitOps (Argo CD)

Ce document formalise les règles architecturales, contraintes opérationnelles et bonnes pratiques applicables à ce repository. Ce repository constitue la **source unique de vérité (Single Source of Truth - SSoT)** pour l'état désiré des applications et composants d'infrastructure déployés par **Argo CD** sur le(s) cluster(s) Kubernetes.

---

## 1. Principes Fondamentaux GitOps

1. **Source Unique de Vérité (SSoT)** :
   - Tout ce qui est déployé sur le cluster Kubernetes **doit** être décrit dans ce repository Git.
   - Toute modification sur le cluster doit transiter par un commit / Pull Request Git.
2. **Interdiction des modifications manuelles (Anti-Drift)** :
   - L'usage de `kubectl apply`, `kubectl edit`, `kubectl patch` ou de dashboards directs pour modifier l'état opérationnel est strictement proscrit.
   - Argo CD est configuré avec l'auto-guérison (`selfHeal: true`) : toute modification hors-Git sera écrasée et alignée sur le repository.
3. **Traçabilité & Immutabilité** :
   - Tout changement d'état est auditable grâce à l'historique Git (qui, quoi, quand, pourquoi).
   - Les rollbacks s'effectuent par un `git revert` du commit concerné.

---

## 2. Structure Recommandée du Repository

Pour garantir la scalabilité, l'isolation des environnements et la maintenance, l'arborescence suivante est préconisée :

```text
.
├── bootstrap/                     # Point d'entrée Argo CD (Pattern "App of Apps" ou ApplicationSets)
│   ├── root-app-dev.yaml          # Application racine pour le cluster/environnement Dev
│   ├── root-app-staging.yaml      # Application racine pour Staging
│   └── root-app-prod.yaml         # Application racine pour Prod
│
├── apps/                          # Déclarations des CRD Argo CD (Application / ApplicationSet)
│   ├── infrastructure/            # Outils transverses (Ingress, Cert-Manager, Monitoring...)
│   └── workloads/                 # Applications métiers
│
├── manifests/                     # Manifests Kubernetes bruts ou bases Kustomize / Helm
│   ├── infrastructure/
│   │   ├── ingress-nginx/
│   │   └── cert-manager/
│   └── workloads/
│       └── backend-api/
│           ├── base/              # Configuration commune (Deployment, Service, ServiceAccount...)
│           │   ├── deployment.yaml
│           │   ├── service.yaml
│           │   └── kustomization.yaml
│           └── overlays/          # Déclinaisons par environnement
│               ├── dev/
│               │   ├── kustomization.yaml
│               │   └── patches/
│               └── prod/
│                   ├── kustomization.yaml
│                   └── patches/
│
└── normeetprojet.md               # Ce document de référence
```

### Directives d'organisation :
- **Séparation Base / Overlays** : Utiliser Kustomize pour mutualiser les configurations communes (`base/`) et ne spécialiser que les variables environnementales dans les `overlays/` (réplicas, ressources, variables d'environnement, ingress host).
- **Découpage Infrastructure vs Workloads** : Séparer strictement les composants d'infrastructure système des applications métiers.

---

## 3. Contraintes et Normes Argo CD

### 3.1. Définition des Applications (`Application` CRD)
Chaque application doit respecter un schéma standardisé :

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: backend-api-prod
  namespace: argocd
  labels:
    env: prod
    tier: backend
  finalizers:
    - resources-finalizer.argocd.argoproj.io # Supprime les ressources K8s si l'Application est supprimée
spec:
  project: default
  source:
    repoURL: https://github.com/votre-organisation/argocd.git
    targetRevision: main # Ou une branche/tag précis
    path: manifests/workloads/backend-api/overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: backend-prod
  syncPolicy:
    automated:
      prune: true     # Supprime les ressources retirées du repository
      selfHeal: true  # Écrase tout drift manuel appliqué directement sur le cluster
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
```

### 3.2. Ordonnancement des Déploiements (Sync Waves)
Pour gérer les dépendances (ex: CRD ou Secret requis avant le Pod applicatif), utiliser l'annotation `argocd.argoproj.io/sync-wave` :

| Vague (Wave) | Rôle typique | Exemples |
| :--- | :--- | :--- |
| **Wave -2** | Namespaces, CRDs | CRDs personnalisées, Namespaces dédiés |
| **Wave -1** | Sécurité, Certificats, Secrets | `ExternalSecret`, `SealedSecret`, `Issuer` |
| **Wave 0** (défaut) | Infrastructure socle & Dépendances | ConfigMaps, PVC, RBAC, Services, Databases |
| **Wave 1** | Migrations / Jobs pré-démarrage | `Job` de migration SQL (avec hooks Argo si besoin) |
| **Wave 2** | Workloads applicatifs | `Deployment`, `StatefulSet` |
| **Wave 3** | Exposition & Monitoring | `Ingress`, `ServiceMonitor`, `PrometheusRule` |

### 3.3. Gestion du Drift et `ignoreDifferences`
Certaines ressources sont mutées à chaud par Kubernetes (ex: `HorizontalPodAutoscaler` qui modifie `replicas`, ou des Mutating Admission Webhooks qui injectent des annotations/champs).
- Il est **obligatoire** de déclarer ces exemptions dans la ressource `Application` via `ignoreDifferences` pour éviter des synchronisations en boucle (Out of Sync perpétuel) :

```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas # Laisser le HPA gérer le nombre de réplicas
```

---

## 4. Gestion Impérative des Secrets

> **RÈGLE CRITIQUE DE SÉCURITÉ** :  
> Aucun secret en clair (pas même encodé en Base64 Kubernetes) ne doit être commité dans ce repository.

### Solutions autorisées :
1. **External Secrets Operator (ESO)** *(Recommandé)* :
   - Ne commiter dans Git que des ressources `ExternalSecret` et `SecretStore`.
   - Les valeurs réelles résident dans un coffre-fort externe (HashiCorp Vault, AWS Secrets Manager, GCP Secret Manager, Azure Key Vault).
2. **Sealed Secrets (Bitnami)** :
   - Chiffrement asymétrique via `kubeseal`.
   - Seul le contrôleur sur le cluster détient la clé privée pour déchiffrer le secret. Le `SealedSecret` chiffré peut être commité en toute sécurité.
3. **SOPS / Age** :
   - Fichiers chiffrés à la racine du repo et déchiffrés par un plugin Argo CD (KSOPS / ArgoCD Vault Plugin).

---

## 5. Normes de Qualité des Manifests Kubernetes

Tous les manifests déclarés dans ce repository doivent se conformer aux standards suivants :

### 5.1. Conventions de Nommage et Labels
- **Nommage** : Utiliser exclusivement le format `kebab-case` en minuscules (`backend-api`, `database-cluster`).
- **Labels Standards Kubernetes (Recommandés)** :
  ```yaml
  metadata:
    labels:
      app.kubernetes.io/name: backend-api
      app.kubernetes.io/instance: backend-api-prod
      app.kubernetes.io/version: "1.4.2"
      app.kubernetes.io/component: backend
      app.kubernetes.io/part-of: ecommerce-platform
      app.kubernetes.io/managed-by: argocd
  ```

### 5.2. Gestion des Images Docker
- **Interdiction formelle du tag `:latest`** :
  - Toujours utiliser un tag immuable : version SemVer (`v1.4.2`) ou hash Git commit SHA (`sha-a1b2c3d`).
- **Image Pull Policy** :
  - Définir `imagePullPolicy: IfNotPresent` pour les tags immuables.

### 5.3. Dimensionnement des Ressources (`requests` / `limits`)
Chaque conteneur **doit obligatoirement** définir des limites et demandes de ressources :
- `requests` : Garantit l'ordonnancement par le kube-scheduler.
- `limits` : Prévient la surconsommation CPU et les blocages mémoire (OOM).

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"
```

### 5.4. Sondes de Santé (Health Checks)
Tout workload applicatif avec exposition réseau doit configurer :
- `livenessProbe` : Vérifie que le conteneur est en vie (redémarrage si échec).
- `readinessProbe` : Vérifie que l'application est prête à recevoir du trafic (retrait des endpoints du Service si échec).
- `startupProbe` : À privilégier pour les applications lentes au démarrage (évite de tuer le conteneur prématurément).

### 5.5. Sécurité des Pods (Security Context)
Dans la mesure du possible, respecter les directives de durcissement Pod Security Standards (Restricted) :

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    fsGroup: 10001
  containers:
    - name: app
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop:
            - ALL
```

### 5.6. Haute Disponibilité et Résilience
- **PodDisruptionBudget (PDB)** : Déclarer un PDB pour les services de production (ex: `minAvailable: 1`) pour éviter l'interruption lors de l'éviction de nœuds.
- **Affinité et Anti-Affinité** : Configurer `podAntiAffinity` pour disperser les pods d'un même service sur plusieurs nœuds ou zones de disponibilité.

---

## 6. Workflow Git et Processus de Contribution

1. **Stratégie de Branches** :
   - La branche `main` représente l'état désiré déployé en production (ou staging selon la convention).
   - Les modifications se font systématiquement via des branches de fonctionnalités (`feature/xxx`, `fix/xxx`, `chore/xxx`).
2. **Pull Requests & Code Review** :
   - Aucune modification poussée directement sur `main` (branche protégée).
   - Validation requise par au moins 1 reviewer (DevOps / SRE / Lead Dev).
3. **Validation Automatisée en CI (GitHub Actions / GitLab CI)** :
   Toute PR doit passer les vérifications suivantes avant d'être éligible au merge :
   - `yamllint` : Respect de la syntaxe YAML et indentations.
   - `kubeconform` / `kubeval` : Validation de la conformité des schémas Kubernetes.
   - `kustomize build` ou `helm lint` : Compilation sans erreur des manifests.
   - Scan de sécurité : Détection des vulnérabilités ou mauvaises configurations (`trivy config`, `polaris`, `checkov`).
4. **Politique de Merge** :
   - `Squash and Merge` ou `Rebase and Merge` pour conserver un historique Git propre et lisible.

---

## 7. Checklist "Prêt pour le Déploiement" (Pre-Merge Checklist)

Avant de valider et merger une Pull Request :

- [ ] L'arborescence respecte la structure standard (`base/`, `overlays/`).
- [ ] Aucun secret en clair n'est présent (vérification SealedSecret / ExternalSecret).
- [ ] Le tag de l'image est immuable (pas de `:latest`).
- [ ] Les `requests` et `limits` de ressources (CPU/RAM) sont renseignées.
- [ ] Les sondes `readinessProbe` et `livenessProbe` sont configurées et fonctionnelles.
- [ ] Les labels standards `app.kubernetes.io/*` sont positionnés.
- [ ] Le `sync-wave` est configuré si un ordonnancement est requis.
- [ ] Les `ignoreDifferences` sont déclarés en cas de mutation automatique (ex: HPA replicas).
- [ ] Les tests de validation statique (linter, schema validator) sont au vert en CI.
