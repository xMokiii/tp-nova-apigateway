# tp-nova-apigateway

TP NOVA SERVICES : deux microservices FastAPI (users, orders) derrière une API Gateway, avec Docker Compose et CI/CD.

## Lancement

Créer un fichier `.env` :

```
GATEWAY_TOKEN=<jeton généré avec openssl rand -hex 32>
```

```bash
docker compose up --build -d
docker compose ps
```

Seule la gateway est exposée, sur `localhost:3000`. Routes : `/health` (publique), `/users`, `/orders`, `/profile/{id}` (avec `Authorization: Bearer <jeton>`).

```bash
set -a; source .env; set +a
curl -i http://localhost:3000/users
curl -i -H "Authorization: Bearer $GATEWAY_TOKEN" http://localhost:3000/profile/1
```

## Tests

```bash
pip install -r gateway/requirements.txt pytest
GATEWAY_TOKEN=ci-test-token python -m pytest -q
```

Tests d'intégration (stack lancée) :

```bash
sh scripts/integration-test.sh
```

## CI/CD

- `.gitlab-ci.yml` : tests puis build/push des images dans le GitLab Container Registry.
- `.github/workflows/ci.yml` : tests, tests d'intégration avec Docker Compose, puis push des images sur ghcr.io (branche main).

Les images sont taguées avec le SHA du commit.

## Questions

### 1. Avantages de l'API Gateway

Le client n'a qu'un seul point d'entrée et ne connaît pas l'organisation interne des services, qui peuvent changer sans impact pour lui. La sécurité (authentification, timeouts, gestion des erreurs) est centralisée au lieu d'être dupliquée dans chaque service. Elle permet aussi d'agréger plusieurs réponses : `/profile/1` renvoie l'utilisateur et ses commandes en une requête, les deux appels étant faits en parallèle.

### 2. Inconvénients

- Point de défaillance unique si elle n'est pas redondée.
- Un saut réseau en plus, donc de la latence.
- Elle peut devenir trop complexe si on y met trop de logique.
- Elle demande de la supervision, des mises à jour et une gestion des secrets.

### 3. Authentification et sécurité

Valider les jetons à la gateway (en production plutôt OAuth 2.0 / OIDC avec des jetons courts), puis vérifier les autorisations sur chaque ressource : avoir un jeton valide ne veut pas dire avoir le droit de voir tous les profils. Utiliser HTTPS, garder les secrets hors du dépôt (variables masquées, gestionnaire de secrets) avec rotation, limiter le débit et ne pas exposer les services internes. Le réseau privé ne remplace pas l'authentification : les services doivent aussi contrôler l'accès à leurs données sensibles.

### 4. API Gateway vs reverse proxy NGINX

NGINX route les requêtes, gère TLS, les en-têtes, le load balancing et le cache. Une API Gateway est faite pour gérer des API : authentification, quotas, gestion des clients, agrégation (BFF). Les deux se recoupent, NGINX peut être configuré pour faire une partie de ce travail, et certaines gateways comme Kong sont basées dessus.
