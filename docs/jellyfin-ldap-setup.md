# Jellyfin LDAP Authentication Setup

This guide documents the manual configuration for Jellyfin LDAP authentication using LLDAP with dedicated service user for improved security.

## Important Notes

- **LDAP configuration is manual only** - Not managed by Ansible due to Jellyfin LDAP plugin limitations
- Configuration must be done through the Jellyfin web UI
- Changes require a Jellyfin restart to take effect
- **Security:** Uses dedicated `jellyfin_bind` service user (read-only) instead of admin account

## Prerequisites

### 1. Services Running
- LLDAP service running and accessible at `lldap:3890` (Docker network)
- Jellyfin running and accessible

### 2. LDAP Plugin Installed
- Install the Jellyfin LDAP Authentication plugin:
  1. Navigate to **Dashboard > Plugins > Catalog**
  2. Search for "LDAP"
  3. Click **Install** on "LDAP Authentication"
  4. Restart Jellyfin when prompted

### 3. Users and Groups Created in LLDAP
Users must be assigned to appropriate groups in LLDAP:
- `media` group - for regular Jellyfin access
- `admin` group - for Jellyfin administrator access

### 4. Service User Configured
The dedicated `jellyfin_bind` service user must be properly configured (see next section)

## Service User Setup

**IMPORTANT:** Jellyfin uses a dedicated read-only service account (`jellyfin_bind`) to query LDAP. This follows security best practices by:
- Limiting access to read-only operations
- Preventing privilege escalation if Jellyfin is compromised
- Following the principle of least privilege

### Configure jellyfin_bind Service User

1. **Access LLDAP Web UI:**
   - Navigate to `http://lldap.frey:17170`
   - Login as admin

2. **Verify Service User Exists:**
   - Navigate to **Users**
   - Find user `jellyfin_bind`
   - If user doesn't exist, create it:
     - Click **Add User**
     - Username: `jellyfin_bind`
     - Email: `jellyfin_bind@frey.local` (or similar)
     - Set password from your password manager
     - Click **Create**

3. **Configure User Password:**
   - If password needs to be set/reset:
     - Click on `jellyfin_bind` user
     - Click **Change Password**
     - Enter password from your password manager
     - Confirm and save

4. **Add to Read-Only Group:**
   - Navigate to **Groups**
   - Find group `lldap_strict_readonly`
   - Click on the group
   - Click **Add Member**
   - Select `jellyfin_bind`
   - Click **Save**

5. **Verify Group Membership:**
   - Return to **Users** → `jellyfin_bind`
   - Check that user is member of:
     - ✅ `lldap_strict_readonly` (must have)
     - ❌ NOT in `lldap_admin` or `admin` groups

### Permission Verification

The `jellyfin_bind` service user should have:
- ✅ Read access to users in `ou=people`
- ✅ Read access to groups in `ou=groups`
- ❌ NO ability to create/modify/delete LDAP entries
- ❌ NO administrative privileges

## Jellyfin LDAP Configuration

### Step 1: Access LDAP Plugin Settings

1. Login to Jellyfin as administrator
2. Navigate to: **Dashboard > Plugins > LDAP Authentication**
3. Click the plugin name to open settings

### Step 2: LDAP Server Settings

Configure the connection to LLDAP:

| Setting | Value | Notes |
|---------|-------|-------|
| **LDAP Server** | `lldap` | Docker service name (DNS resolution) |
| **LDAP Port** | `3890` | LLDAP standard LDAP port |
| **Secure LDAP** | `unchecked` | No SSL - internal Docker network |
| **StartTLS** | `unchecked` | Not needed for internal network |
| **LDAP Bind User** | `uid=jellyfin_bind,ou=people,dc=frey,dc=local` | **Service user (read-only)** |
| **LDAP Bind User Password** | `[jellyfin_bind password]` | From password manager |
| **LDAP Base DN for searches** | `dc=frey,dc=local` | Base distinguished name |

**🔒 Security Note:** We use the dedicated `jellyfin_bind` service user instead of the admin account. This limits the damage if Jellyfin is compromised.

**Test Connection:**
1. Click **Save and Test LDAP Server Settings**
2. **Expected Result:**
   ```
   Connect (Success)
   Bind (Success)
   Base Search (Found X Entities)
   ```

**Troubleshooting:**
- **Connect Failed:** Check LLDAP service is running (`docker ps | grep lldap`)
- **Bind Failed:** Verify service user DN and password are correct
- **Base Search (0 Entities):** Check Base DN is `dc=frey,dc=local`

### Step 3: LDAP User Settings

Configure how users are found and authenticated:

#### Search Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| **LDAP Search Filter** | `(memberOf=cn=media,ou=groups,dc=frey,dc=local)` | Only users in `media` group |
| **LDAP Search Attributes** | `uid, cn, mail, displayName` | Attributes to search |
| **LDAP Uid Attribute** | `uid` | Unique identifier |
| **LDAP Username Attribute** | `uid` | Username for login |

#### Administrator Configuration

| Setting | Value | Notes |
|---------|-------|-------|
| **LDAP Admin Base DN** | *(leave empty)* | Uses main Base DN |
| **LDAP Admin Filter** | `(memberOf=cn=admin,ou=groups,dc=frey,dc=local)` | Users in `admin` group |

**Test Filters:**
1. Click **Save and Test LDAP Filter Settings**
2. **Expected Result:** `Found X user(s), Y admin(s)` (where X > 0)

**Troubleshooting:**
- **Found 0 users:** Verify users are in the `media` group in LLDAP
- **Search timeout:** Check network connectivity to LLDAP

### Step 4: Jellyfin User Settings

Configure how Jellyfin handles LDAP users:

| Setting | Value | Notes |
|---------|-------|-------|
| **Enable User Creation** | `checked` | Auto-create users on first login |
| **Enable access to all libraries** | `checked` | Grant access to all media |

**Alternative:** Uncheck "Enable access to all libraries" if you want to manually assign library access per user.

### Step 5: Test Individual User Lookup

Before saving, test with a specific user:

1. Scroll to **Testing** section
2. Enter a username in "Test Login Name" field (e.g., your LDAP username)
3. Click **Save Search Attribute Settings and Query User**
4. **Expected Result:** User details displayed with DN path

**Troubleshooting:**
- **User not found:** Check user exists in LLDAP and is in `media` group
- **Permission denied:** Verify `jellyfin_bind` has read access

### Step 6: Save and Restart

1. Click **Save** at the bottom of the settings page
2. Restart Jellyfin container:
   ```bash
   docker restart jellyfin
   ```
3. Wait 10-15 seconds for Jellyfin to fully restart

## Testing Authentication

### Test 1: LDAP Login

1. Log out of Jellyfin (or use incognito/private browsing)
2. On the login screen, enter LDAP credentials:
   - **Username:** Your LDAP username (e.g., `jason`)
   - **Password:** Your LDAP password
3. Click **Sign In**
4. **Expected:** User authenticated and Jellyfin account auto-created

### Test 2: Verify User Creation

1. Login to Jellyfin as admin
2. Navigate to **Dashboard > Users**
3. **Expected:** New user appears with name from LDAP

### Test 3: Verify Library Access

1. Login as the LDAP user
2. **Expected:** Can see and access media libraries

## Group Membership Requirements

For users to access Jellyfin via LDAP, they must be members of the **`media` group** in LLDAP.

### Add User to Media Group

1. Access LLDAP web UI at `http://lldap.frey:17170`
2. Navigate to **Groups**
3. Click on **media** group
4. Click **Add Member**
5. Select the user
6. Click **Save**

### Grant Admin Access

For Jellyfin administrative privileges:
1. Add user to **`admin` group** in LLDAP (in addition to `media`)
2. User will have Jellyfin admin rights on next login

## Troubleshooting

### Connection Test Fails

**Symptoms:** "Connect Failed" when testing LDAP server settings

**Solutions:**
- Check LLDAP service is running: `docker ps | grep lldap`
- Verify Jellyfin can resolve `lldap` hostname: `docker exec jellyfin nslookup lldap`
- Ensure Jellyfin is on correct Docker network (should see `lldap` in network)
- Check LLDAP port is `3890`

### Bind Test Fails

**Symptoms:** "Bind Failed" or "Authentication Failed"

**Solutions:**
- Verify Bind User DN is exactly: `uid=jellyfin_bind,ou=people,dc=frey,dc=local`
- Check password is correct (try resetting in LLDAP)
- Ensure `jellyfin_bind` user exists and is active in LLDAP
- Verify user is not disabled in LLDAP

### Filter Test Returns 0 Users

**Symptoms:** "Found 0 user(s)"

**Solutions:**
- Verify users exist in LLDAP
- Check users are in the `media` group:
  - LLDAP → Groups → media → Members
- Verify Base DN is `dc=frey,dc=local`
- Check search filter: `(memberOf=cn=media,ou=groups,dc=frey,dc=local)`

### Individual User Search Fails

**Symptoms:** Cannot find specific user in test

**Solutions:**
- Verify user exists in LLDAP
- Check user is in `media` group
- Ensure Search Attributes include `uid`: `uid, cn, mail, displayName`
- Try searching by exact `uid` (case-sensitive)

### Login Fails with Correct Credentials

**Symptoms:** User cannot login even with correct password

**Solutions:**
- Verify "Enable User Creation" is checked
- Restart Jellyfin after saving LDAP settings: `docker restart jellyfin`
- Check Jellyfin logs for LDAP errors: `docker logs jellyfin | grep -i ldap`
- Verify user filter includes the user: test with individual user lookup
- Ensure user's LDAP account is not disabled

### User Logs In But Has No Access

**Symptoms:** User authenticated but sees no libraries

**Solutions:**
- Check "Enable access to all libraries" is checked in LDAP settings
- Manually grant library access:
  - Dashboard → Users → [User] → Library Access
- Verify user is actually in Jellyfin users list
- Check user hasn't been disabled in Jellyfin

### Service User Permission Errors

**Symptoms:** "Access Denied" or "Insufficient Permissions"

**Solutions:**
- Verify `jellyfin_bind` is in `lldap_strict_readonly` group
- Check service user is NOT disabled
- Ensure service user can read `ou=people` and `ou=groups`
- Test bind manually if possible
- Verify service user is NOT in admin groups (security issue if it is)

## LLDAP Attribute Reference

LLDAP provides these standard attributes that Jellyfin can use:

| Attribute | Aliases | Type | Description |
|-----------|---------|------|-------------|
| `uid` | `user_id`, `id` | String | Unique user identifier (username) |
| `displayname` | `display_name`, `cn` | String | User's display name |
| `mail` | `email` | String | User's email address |
| `givenname` | `first_name`, `firstname` | String | User's first name |
| `sn` | `last_name`, `lastname` | String | User's last name (surname) |
| `memberOf` | - | DN List | Groups the user belongs to |

## Security Best Practices

### Service User Security

✅ **DO:**
- Use dedicated `jellyfin_bind` service user for LDAP queries
- Keep service user in `lldap_strict_readonly` group only
- Rotate service account password periodically
- Store password securely (password manager, not in git)
- Monitor service user login attempts

❌ **DO NOT:**
- Use admin account for Jellyfin LDAP bind
- Share `jellyfin_bind` password with other services
- Give service user write permissions
- Add service user to admin groups

### General Security

- **LDAP Communication:** Happens over internal Docker network (encrypted transport not needed)
- **Password Verification:** LDAP passwords are verified by LLDAP, never stored by Jellyfin
- **Access Control:** Enforced through LLDAP group membership (`media`, `admin`)
- **User Creation:** Only users in allowed LDAP groups can create Jellyfin accounts
- **Network Isolation:** LLDAP and Jellyfin communicate on isolated Docker network

### Service User Naming Convention

For consistency across the project:
- **Format:** `{service}_bind` (e.g., `jellyfin_bind`, `authelia_bind`)
- **DN:** `uid={service}_bind,ou=people,dc=frey,dc=local`
- **Group:** Always in `lldap_strict_readonly`
- **Purpose:** Read-only LDAP queries only

## Related Documentation

- [Jellyfin LDAP Plugin GitHub](https://github.com/jellyfin/jellyfin-plugin-ldapauth)
- [LLDAP Documentation](https://github.com/lldap/lldap)
- [LDAP Filter Syntax Guide](https://confluence.atlassian.com/kb/how-to-write-ldap-search-filters-792496933.html)
- [LLDAP Best Practices (2025)](https://blog.stonegarden.dev/articles/2025/01/lldap/)

## Quick Reference

### Service User Credentials

```
Username: jellyfin_bind
DN: uid=jellyfin_bind,ou=people,dc=frey,dc=local
Group: lldap_strict_readonly
Password: [stored in password manager]
```

### LDAP Connection Details

```
Server: lldap
Port: 3890
Base DN: dc=frey,dc=local
Secure: No (internal network)
```

### User Filters

```
User Search: (memberOf=cn=media,ou=groups,dc=frey,dc=local)
Admin Filter: (memberOf=cn=admin,ou=groups,dc=frey,dc=local)
Search Attributes: uid, cn, mail, displayName
```

### Required LLDAP Groups

- `media` - Required for Jellyfin access
- `admin` - Optional, grants Jellyfin admin privileges
- `lldap_strict_readonly` - Required for service users only
