# NOVA SERVICES — API Gateway et microservices sécurisés

Architecture de microservices FastAPI (Users, Orders) derrière une API Gateway (BFF),
déployée avec Docker Compose et automatisée avec GitLab CI/CD.

```
Client ──HTTP──▶ 127.0.0.1:3000 ──▶ gateway (réseaux frontend + backend)
                                       ├──▶ users:8000   (réseau backend interne, aucun port publié)
                                       └──▶ orders:8000  (réseau backend interne, aucun port publié)
```

## Structure

```
users/      main.py, requirements.txt, Dockerfile
orders/     main.py, requirements.txt, Dockerfile
gateway/    main.py, requirements.txt, Dockerfile
tests/      test_gateway.py
captures/   sorties-endpoints.txt (sorties des commandes curl)
docker-compose.yml  .gitlab-ci.yml  .gitignore  .dockerignore
```

## Lancer le projet

Sous PowerShell, `>` écrit en UTF-16 et `openssl` n'est souvent pas dans le PATH : génère le `.env` ainsi :

```powershell
$b = New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
$t = -join ($b | ForEach-Object { '{0:x2}' -f $_ })
[IO.File]::WriteAllText("$PWD\.env", "GATEWAY_TOKEN=$t`n")
```

```bash
echo "GATEWAY_TOKEN=$(openssl rand -hex 32)" > .env   # Git Bash / Linux / macOS
docker compose config
docker compose up --build -d
docker compose ps

set -a; source .env; set +a
curl -i http://localhost:3000/users                                              # 401
curl -i -H "Authorization: Bearer $GATEWAY_TOKEN" http://localhost:3000/users    # 200
curl -i -H "Authorization: Bearer $GATEWAY_TOKEN" http://localhost:3000/orders   # 200
curl -i -H "Authorization: Bearer $GATEWAY_TOKEN" http://localhost:3000/profile/1   # 200 (BFF)
curl -i -H "Authorization: Bearer $GATEWAY_TOKEN" http://localhost:3000/profile/999 # 404
curl -i http://localhost:3000/health                                             # 200

docker compose down
```

## Tests

```bash
python -m pip install -r gateway/requirements.txt pytest
export GATEWAY_TOKEN=ci-test-token
python -m pytest -q        # 5 passed
```

## Mesures de sécurité mises en place

| Mesure | Où |
|---|---|
| Image légère `python:3.12-slim`, `pip --no-cache-dir`, utilisateur non-root `app` | Dockerfiles |
| Healthcheck sur `/health` | Dockerfiles + `docker-compose.yml` |
| Seul le port de la Gateway est publié, et uniquement sur `127.0.0.1:3000` | `docker-compose.yml` |
| Réseau `backend` en `internal: true` pour Users / Orders | `docker-compose.yml` |
| `read_only`, `tmpfs /tmp`, `cap_drop: ALL`, `no-new-privileges` | `docker-compose.yml` |
| Le jeton est obligatoire (`${GATEWAY_TOKEN:?…}`) et vient de `.env`, exclu de Git et des images | `docker-compose.yml`, `.gitignore`, `.dockerignore` |
| Jeton Bearer comparé en temps constant (`secrets.compare_digest`) | `gateway/main.py` |
| Timeout de 5 s vers les microservices, erreurs backend masquées (502 générique) | `gateway/main.py` |
| Login au Registry via `CI_REGISTRY_USER` / `CI_REGISTRY_PASSWORD`, images taguées `$CI_COMMIT_SHA` | `.gitlab-ci.yml` |

## Checklist de sécurité

- [x] Le fichier `.env` est exclu de Git.
- [x] La Gateway exige un jeton sur les endpoints métier.
- [x] Les services Users et Orders ne publient aucun port sur la machine hôte.
- [x] Les communications internes passent par un réseau Docker dédié.
- [x] Les conteneurs tournent avec un utilisateur non-root.
- [x] Les requêtes vers les microservices ont un timeout.
- [x] Les erreurs backend ne révèlent pas les détails techniques au client.
- [x] La pipeline utilise les variables prédéfinies du Registry GitLab.
- [x] Les images sont taguées avec le SHA du commit.
- [ ] Les images et dépendances sont analysées avant un déploiement de production (amélioration optionnelle : `pip-audit`, Trivy, SAST GitLab).

## Questions de compréhension

### 1. Quels avantages l'API Gateway apporte-t-elle ?

Elle offre un **point d'entrée unique** : le client ne connaît qu'une URL (`localhost:3000`) et
ignore l'organisation interne des microservices, qui peuvent donc évoluer (renommage, découpage,
changement de port) sans impact côté client. Elle **centralise les règles transverses** —
authentification, timeouts, gestion des erreurs, et potentiellement limitation de débit, journalisation
ou CORS — au lieu de les dupliquer dans chaque service. Elle permet enfin l'**agrégation BFF** :
avec `/profile/{id}`, le client obtient l'utilisateur et ses commandes en une seule requête, la
Gateway interrogeant les deux services en parallèle (`asyncio.gather`), ce qui réduit le nombre
d'allers-retours réseau, particulièrement coûteux sur mobile.

### 2. Quels sont les inconvénients d'une API Gateway ?

- **Point de défaillance unique** : si la Gateway tombe, toute l'API devient indisponible ; il faut
  la redonder (plusieurs instances derrière un load balancer).
- **Latence supplémentaire** : chaque requête traverse un saut réseau de plus.
- **Risque de « monolithe distribué »** : si on y place trop de logique métier, elle devient complexe,
  difficile à faire évoluer et crée un couplage entre équipes.
- **Coût d'exploitation** : elle doit être supervisée, mise à jour, dimensionnée, et elle gère des
  secrets sensibles, ce qui en fait une cible privilégiée.

### 3. Comment gérer l'authentification et la sécurité ?

- **Authentifier à la Gateway** : valider des jetons d'accès (ici un Bearer statique pour le TP ;
  en production des jetons OAuth 2.0 / OIDC courts, signés, émis par un fournisseur d'identité, dont
  on vérifie signature, expiration, audience).
- **Autoriser par ressource** : vérifier que l'appelant a le droit d'accéder au profil ou aux
  commandes demandés (rôles, scopes, propriété de la donnée) — authentification ≠ autorisation.
- **Chiffrer** : HTTPS/TLS dès que le trafic quitte un environnement local maîtrisé, voire mTLS entre services.
- **Protéger les secrets** : variables d'environnement hors dépôt, variables masquées/protégées
  GitLab ou gestionnaire de secrets (Vault…), avec rotation.
- **Limiter l'exposition** : seul le port de la Gateway est publié, les services internes restent
  sur un réseau privé ; limiter le débit (rate limiting) et valider les entrées.
- **Défense en profondeur** : le réseau privé n'est pas une authentification, les microservices
  doivent eux aussi contrôler les autorisations sensibles sur leurs données.
- **Durcir et analyser** : conteneurs non-root, en lecture seule, sans capacités ; scan des
  dépendances et des images dans la pipeline.

### 4. Quelle différence entre une API Gateway et un reverse proxy NGINX ?

Un **reverse proxy** comme NGINX travaille essentiellement au niveau HTTP/transport : il route les
requêtes vers des backends, termine TLS, répartit la charge, met en cache, réécrit des en-têtes.
Une **API Gateway** est orientée **gestion d'API** : en plus du routage, elle gère l'authentification
et l'autorisation des clients, les quotas et la limitation de débit, les clés d'API, la
transformation de requêtes/réponses, l'agrégation de plusieurs services (BFF), le versionnement,
l'observabilité par API. Les deux se recoupent : NGINX (avec modules, Lua ou NGINX Plus) peut remplir
une partie de ces fonctions, et beaucoup d'API Gateways (Kong, par exemple) sont elles-mêmes
construites sur NGINX. Dans ce TP, la Gateway FastAPI fait ce qu'un NGINX seul ne ferait pas
simplement : vérifier un jeton et agréger les réponses de deux services.

## Publication sur GitLab

```bash
git init
git add .
git status          # vérifier que .env n'apparaît pas
git commit -m "Initial E-Shop API Gateway project"
git branch -M main
git remote add origin URL_DE_TON_DEPOT_GITLAB
git push -u origin main
```

Puis dans GitLab : *Build > Pipelines* (stages `test` et `build`), puis *Deploy > Container Registry*
pour vérifier les images `users`, `orders` et `gateway` taguées avec le SHA du commit.
#   t p - n o v a - a p i g a t e w a y  
 