# Jellyfin LDAP Authentication Setup

This guide documents the manual configuration for Jellyfin LDAP authentication using LLDAP.

## Important Notes

- **LDAP configuration is manual only** - Not managed by Ansible due to the complexity of the Jellyfin LDAP plugin
- Configuration must be done through the Jellyfin web UI
- Changes require a Jellyfin restart to take effect

## Prerequisites

1. LLDAP service running and accessible at `lldap:3890` (Docker network)
2. Jellyfin LDAP Authentication plugin installed
3. Users created in LLDAP and assigned to appropriate groups:
   - `media` group - for regular Jellyfin access
   - `admin` group - for Jellyfin administrator access

## Configuration Steps

### 1. Access Jellyfin LDAP Plugin Settings

Navigate to: **Dashboard > Plugins > LDAP Authentication > Settings**

### 2. LDAP Server Settings

Configure the connection to LLDAP:

| Setting | Value | Notes |
|---------|-------|-------|
| **LDAP Server** | `lldap` | Docker service name |
| **LDAP Port** | `3890` | LLDAP standard port |
| **Secure LDAP** | `unchecked` | No SSL for internal Docker network |
| **StartTLS** | `unchecked` | Not needed for internal network |
| **LDAP Bind User** | `uid=admin,ou=people,dc=frey,dc=local` | Admin user for bind operations |
| **LDAP Bind User Password** | `[admin password]` | Use the LLDAP admin password from `group_vars/all/secrets.yml` |
| **LDAP Base DN for searches** | `dc=frey,dc=local` | Base distinguished name |

**Test:** Click "Save and Test LDAP Server Settings"

**Expected Result:** `Connect (Success); Bind (Success); Base Search (Found X Entities)`

### 3. LDAP User Settings

Configure how users are found and authenticated:

#### Search Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| **LDAP Search Filter** | `(memberOf=cn=media,ou=groups,dc=frey,dc=local)` | Find users in media group |
| **LDAP Search Attributes** | `uid, cn, mail, displayName` | Attributes to search |
| **LDAP Uid Attribute** | `uid` | Unique identifier attribute |
| **LDAP Username Attribute** | `uid` | Username attribute |

#### Administrator Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| **LDAP Admin Base DN** | *(leave empty)* | Uses the main Base DN |
| **LDAP Admin Filter** | `(memberOf=cn=admin,ou=groups,dc=frey,dc=local)` | Find users in admin group |

**Test:** Click "Save and Test LDAP Filter Settings"

**Expected Result:** `Found X user(s), Y admin(s)` (where X > 0)

### 4. Jellyfin User Settings

Configure how Jellyfin handles LDAP users:

| Setting | Value | Notes |
|---------|-------|-------|
| **Enable User Creation** | `checked` | Auto-create users on first LDAP login |
| **Enable access to all libraries** | `checked` | Grant access to all media libraries |

### 5. Save and Restart

1. Click **Save** button at the bottom of the form
2. Restart Jellyfin for changes to take effect:
   ```bash
   docker restart jellyfin
   ```

## Testing Authentication

### Test with Individual User Search

1. In the LDAP settings, scroll to the "Testing" section
2. Enter a username (e.g., `jason` or `admin`) in the "Test Login Name" field
3. Click "Save Search Attribute Settings and Query User"
4. **Expected:** Should find the user and display their DN

### Test Actual Login

1. Log out of Jellyfin
2. On the login screen, enter LDAP credentials:
   - **Username:** LDAP username (e.g., `jason`)
   - **Password:** User's LDAP password
3. Click Login
4. **Expected:** User should be authenticated and Jellyfin user account auto-created

## Group Membership Requirements

For users to access Jellyfin via LDAP, they must be members of the `media` group in LLDAP.

**To add a user to the media group in LLDAP:**

1. Access LLDAP web UI at `http://lldap.frey:17170`
2. Navigate to **Groups**
3. Click on the **media** group
4. Click **Add member**
5. Select the user and save

**For admin access:** Add the user to both `media` and `admin` groups.

## Troubleshooting

### Connection Test Fails

- **Check:** Is LLDAP service running? `docker ps | grep lldap`
- **Check:** Is Jellyfin on the correct Docker network? Should be on `auth_network`
- **Check:** Can Jellyfin resolve `lldap` hostname? `docker exec jellyfin ping lldap`

### Filter Test Returns 0 Users

- **Check:** Are users in the `media` group in LLDAP?
- **Check:** Is the Base DN correct? Should be `dc=frey,dc=local`
- **Check:** Is the search filter correct? Should reference `cn=media,ou=groups,dc=frey,dc=local`

### Individual User Search Fails

- **Check:** Does the user exist in LLDAP?
- **Check:** Is the user in the `media` group?
- **Check:** Are the Search Attributes correct? Should include `uid`

### Login Fails with Correct Credentials

- **Check:** Is "Enable User Creation" checked?
- **Check:** Did you restart Jellyfin after saving LDAP settings?
- **Check:** Check Jellyfin logs: `docker logs jellyfin`

### User Logs In But Has No Access

- **Check:** Is "Enable access to all libraries" checked?
- **Check:** Manually grant library access in Jellyfin Dashboard > Users

## LLDAP Attribute Reference

LLDAP provides these standard attributes for users:

| Attribute | Aliases | Type | Description |
|-----------|---------|------|-------------|
| `uid` | `user_id`, `id` | String | Unique user identifier |
| `displayname` | `display_name`, `cn` | String | User's display name |
| `mail` | `email` | String | User's email address |
| `firstname` | `first_name`, `givenname` | String | User's first name |
| `lastname` | `last_name`, `sn` | String | User's last name |
| `avatar` | `jpegphoto` | JpegPhoto | User's profile picture |

## Security Notes

- **Bind User:** Uses admin account for LDAP bind operations (has full read access to LDAP)
- **Passwords:** LDAP passwords are verified by LLDAP, not stored in Jellyfin
- **Group Membership:** Access control enforced through LLDAP group membership
- **Network Security:** LDAP communication happens over internal Docker network (no encryption needed)

## Related Documentation

- [Jellyfin LDAP Plugin GitHub](https://github.com/jellyfin/jellyfin-plugin-ldapauth)
- [LLDAP Documentation](https://github.com/lldap/lldap)
- [LDAP Filter Syntax Guide](https://confluence.atlassian.com/kb/how-to-write-ldap-search-filters-792496933.html)
