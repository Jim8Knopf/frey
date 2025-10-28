# Cookbook Role - Mealie Recipe Manager

Deploys Mealie recipe manager with API access, meal planning, and SSO support.

## Features

- 📚 **Recipe Management** - Store, organize, and share recipes
- 🌐 **URL Scraping** - Import recipes from any website automatically
- 🗓️ **Meal Planning** - Weekly calendar view for planning meals
- 🛒 **Shopping Lists** - Auto-generated from meal plans
- 🔗 **Full REST API** - OpenAPI/Swagger documentation
- 🤖 **n8n/LLM Ready** - Perfect for automation workflows
- 🔐 **SSO Support** - OIDC and LDAP authentication
- 👥 **Multi-user** - Share recipes with family/friends
- 🏷️ **Organization** - Tags, categories, and cookbooks
- 📱 **Mobile-friendly** - Responsive web interface

## Architecture

```
cookbook/
├── mealie            (Recipe manager - port 9925)
└── mealie-postgres   (PostgreSQL database)
```

## Configuration

Edit `group_vars/all/main.yml`:

```yaml
features:
  cookbook: true  # Enable the cookbook feature

cookbook:
  services:
    mealie:
      port: 9925
      version: "latest"
      allow_signup: false  # Control user registration
      oidc_enabled: false  # Enable when SSO is ready
      base_url: "http://cookbook.frey"
```

## Deployment

```bash
# Deploy cookbook
ansible-playbook playbooks/site.yml -i inventory/hosts.yml --tags cookbook

# Or deploy entire stack
ansible-playbook playbooks/site.yml -i inventory/hosts.yml
```

## Access

- **Web UI**: `http://cookbook.frey`
- **API Documentation**: `http://cookbook.frey/docs`
- **Direct Access**: `http://10.20.0.1:9925`

## First-Time Setup

1. Navigate to `http://cookbook.frey`
2. Create an admin account (first user becomes admin)
3. Configure your preferences
4. Start adding recipes!

## API Integration

### Authentication

1. Access Mealie web interface
2. Go to **Settings → Profile → API Tokens**
3. Click **Generate Token**
4. Copy the token
5. Use in API requests: `Authorization: Bearer <your-token>`

### Key API Endpoints

```bash
# List all recipes
GET /api/recipes

# Create a recipe
POST /api/recipes
{
  "name": "Recipe Name",
  "description": "Description",
  "recipeIngredient": ["1 cup flour", "2 eggs"],
  "recipeInstructions": [
    {"text": "Step 1"},
    {"text": "Step 2"}
  ]
}

# Scrape recipe from URL
POST /api/recipes/create-url
{
  "url": "https://example.com/recipe",
  "include_tags": true
}

# Get recipe by ID
GET /api/recipes/{recipe_id}

# List meal plans
GET /api/meal-plans

# Create meal plan
POST /api/meal-plans
{
  "date": "2025-01-15",
  "entryType": "dinner",
  "recipeId": "recipe-uuid"
}

# Get shopping lists
GET /api/shopping-lists
```

### Full API Documentation

Complete interactive API documentation available at:
`http://cookbook.frey/docs`

## n8n Integration Examples

### Example 1: LLM-Generated Recipe

```
1. LLM Node → Generate recipe in JSON format
2. HTTP Request → POST /api/recipes
   - Headers: Authorization: Bearer <token>
   - Body: Recipe JSON
3. Add to meal plan (optional)
```

### Example 2: Recipe Scraper Workflow

```
1. Webhook → Receive URL
2. HTTP Request → POST /api/recipes/create-url
   - Headers: Authorization: Bearer <token>
   - Body: {"url": "{{$node.Webhook.json.url}}"}
3. Send notification
```

### Example 3: Weekly Meal Plan Generator

```
1. Schedule Trigger → Every Sunday
2. HTTP Request → GET /api/recipes (random selection)
3. Loop → Create meal plans for the week
4. HTTP Request → POST /api/meal-plans
5. Generate shopping list → GET /api/shopping-lists
```

## SSO Setup (Future)

When you deploy Authentik or Authelia:

### 1. Update Configuration

Edit `group_vars/all/main.yml`:

```yaml
cookbook:
  services:
    mealie:
      oidc_enabled: true
      oidc_configuration_url: "https://auth.frey/.well-known/openid-configuration"
      oidc_client_id: "mealie"
      oidc_user_group: "mealie_users"      # Users who can login
      oidc_admin_group: "mealie_admins"    # Users who become admins
      oidc_auto_redirect: false            # Auto-redirect to SSO login
```

### 2. Create OIDC Application in Your IdP

**For Authentik:**
- Provider Type: OAuth2/OIDC
- Client ID: `mealie`
- Redirect URIs: `http://cookbook.frey/login/callback`
- Scopes: `openid`, `profile`, `email`, `groups`

**For Authelia:**
- Similar configuration in `configuration.yml`

### 3. Redeploy

```bash
ansible-playbook playbooks/site.yml -i inventory/hosts.yml --tags cookbook
```

### 4. Optional: Disable Password Login

```yaml
cookbook:
  services:
    mealie:
      allow_signup: false
      allow_password_login: false  # SSO-only mode
```

## LDAP Authentication

For corporate/enterprise LDAP:

```yaml
cookbook:
  services:
    mealie:
      ldap_enabled: true
      ldap_server_url: "ldap://ldap.frey:389"
      ldap_base_dn: "dc=frey,dc=local"
      ldap_query_bind: "cn=admin,dc=frey,dc=local"
      ldap_query_password: "your-password"
      ldap_user_filter: "(memberOf=cn=mealie_users,ou=groups,dc=frey,dc=local)"
      ldap_admin_filter: "(memberOf=cn=mealie_admins,ou=groups,dc=frey,dc=local)"
```

## Storage & Data

### Locations

- **Application Data**: `/opt/frey/appdata/mealie`
- **Database**: `/opt/frey/appdata/mealie-db`
- **Docker Compose**: `/opt/frey/stacks/cookbook`

### Backup

```bash
# Backup database
docker exec mealie_postgres pg_dump -U mealie mealie > mealie_backup_$(date +%Y%m%d).sql

# Backup application data
tar -czf mealie_data_backup_$(date +%Y%m%d).tar.gz /opt/frey/appdata/mealie

# Restore database
docker exec -i mealie_postgres psql -U mealie mealie < mealie_backup.sql
```

## Maintenance

### View Logs

```bash
# All containers
docker compose -C /opt/frey/stacks/cookbook logs -f

# Mealie only
docker logs mealie -f

# Database only
docker logs mealie_postgres -f
```

### Restart Service

```bash
# Restart all
docker compose -C /opt/frey/stacks/cookbook restart

# Restart Mealie only
docker restart mealie
```

### Update Mealie

```bash
# Pull latest images
docker compose -C /opt/frey/stacks/cookbook pull

# Recreate containers with new images
docker compose -C /opt/frey/stacks/cookbook up -d
```

### Check Health

```bash
# Container status
docker ps | grep mealie

# Health check
curl http://cookbook.frey/api/app/about
```

## Troubleshooting

### Can't Access Web Interface

1. **Check if container is running:**
   ```bash
   docker ps | grep mealie
   ```

2. **Check logs for errors:**
   ```bash
   docker logs mealie
   ```

3. **Verify DNS resolution:**
   ```bash
   nslookup cookbook.frey 10.20.0.1
   ```

4. **Test direct access:**
   ```bash
   curl http://10.20.0.1:9925
   ```

### Database Connection Issues

```bash
# Check database is running
docker ps | grep mealie_postgres

# Check database logs
docker logs mealie_postgres

# Test database connection
docker exec mealie_postgres pg_isready -U mealie
```

### API Authentication Fails

1. Regenerate API token in web interface
2. Check token format: `Authorization: Bearer <token>`
3. Verify API docs access: `http://cookbook.frey/docs`

### SSO Not Working

1. Check OIDC configuration URL is accessible
2. Verify redirect URI matches IdP configuration
3. Check group memberships in IdP
4. View Mealie logs: `docker logs mealie | grep -i oidc`

## Advanced Configuration

### Custom Environment Variables

Add to `roles/cookbook/templates/.env.j2`:

```bash
# Performance tuning
WEB_CONCURRENCY=2
MAX_WORKERS=1

# Storage
MAX_UPLOAD_SIZE=100

# Features
ALLOW_SHARING=true
ALLOW_EXPORTS=true
```

### Network Configuration

The cookbook uses two networks:
- **cookbook_network**: Internal communication (Mealie ↔ PostgreSQL)
- **proxy**: External access via Traefik

### Resource Limits

Add to docker-compose if needed:

```yaml
services:
  mealie:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
```

## Related Documentation

- [Mealie Official Docs](https://docs.mealie.io/)
- [Mealie API Documentation](https://docs.mealie.io/documentation/getting-started/api/)
- [n8n Integration Examples](https://community.n8n.io/search?q=mealie)
- [Authentik OIDC Setup](https://docs.goauthentik.io/integrations/services/mealie/)
- [Authelia OIDC Setup](https://www.authelia.com/integration/openid-connect/clients/mealie/)

## Support

- Project issues: Check Ansible playbook logs
- Mealie issues: [GitHub Issues](https://github.com/mealie-recipes/mealie/issues)
- Community: [Mealie Discord](https://discord.gg/QuStdQGSGK)
