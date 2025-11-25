#!/usr/bin/env python3
"""
LLDAP Group Creation Script
Automatically creates required groups in LLDAP via GraphQL API
"""

import requests
import json
import sys
import time

def login_to_lldap(lldap_url, admin_user, admin_password):
    """Login to LLDAP and get authentication token"""
    login_url = f"{lldap_url}/auth/simple/login"
    payload = {
        "username": admin_user,
        "password": admin_password
    }

    try:
        response = requests.post(login_url, json=payload, timeout=10)
        response.raise_for_status()
        return response.json()["token"]
    except Exception as e:
        print(f"ERROR: Failed to login to LLDAP: {e}", file=sys.stderr)
        sys.exit(1)

def get_existing_groups(lldap_url, token):
    """Get list of existing groups"""
    graphql_url = f"{lldap_url}/api/graphql"
    query = {"query": "query { groups { id displayName } }"}
    headers = {"Authorization": f"Bearer {token}"}

    try:
        response = requests.post(graphql_url, json=query, headers=headers, timeout=10)
        response.raise_for_status()
        groups = response.json()["data"]["groups"]
        return [g["displayName"] for g in groups]
    except Exception as e:
        print(f"ERROR: Failed to get existing groups: {e}", file=sys.stderr)
        sys.exit(1)

def create_group(lldap_url, token, group_name):
    """Create a new group in LLDAP"""
    graphql_url = f"{lldap_url}/api/graphql"
    mutation = {
        "query": """
            mutation CreateGroup($name: String!) {
                createGroup(name: $name) {
                    id
                    displayName
                }
            }
        """,
        "variables": {"name": group_name}
    }
    headers = {"Authorization": f"Bearer {token}"}

    try:
        response = requests.post(graphql_url, json=mutation, headers=headers, timeout=10)
        response.raise_for_status()
        result = response.json()

        if "errors" in result:
            # Check if error is about group already existing
            error_msg = result["errors"][0]["message"]
            if "already exists" in error_msg.lower():
                return {"status": "exists", "message": f"Group '{group_name}' already exists"}
            else:
                return {"status": "error", "message": error_msg}

        return {"status": "created", "message": f"Group '{group_name}' created successfully"}
    except Exception as e:
        return {"status": "error", "message": f"Failed to create group '{group_name}': {e}"}

def main():
    if len(sys.argv) < 5:
        print("Usage: create_lldap_groups.py <lldap_url> <admin_user> <admin_password> <group1> [group2] ...", file=sys.stderr)
        sys.exit(1)

    lldap_url = sys.argv[1]
    admin_user = sys.argv[2]
    admin_password = sys.argv[3]
    groups_to_create = sys.argv[4:]

    # Wait for LLDAP to be ready
    print(f"Connecting to LLDAP at {lldap_url}...", file=sys.stderr)
    max_retries = 30
    for attempt in range(max_retries):
        try:
            requests.get(lldap_url, timeout=5)
            break
        except:
            if attempt == max_retries - 1:
                print(f"ERROR: LLDAP not accessible after {max_retries} attempts", file=sys.stderr)
                sys.exit(1)
            time.sleep(2)

    # Login
    print(f"Logging in as {admin_user}...", file=sys.stderr)
    token = login_to_lldap(lldap_url, admin_user, admin_password)

    # Get existing groups
    existing_groups = get_existing_groups(lldap_url, token)
    print(f"Existing groups: {', '.join(existing_groups)}", file=sys.stderr)

    # Create groups
    results = []
    changed = False

    for group_name in groups_to_create:
        if group_name in existing_groups:
            print(f"✓ Group '{group_name}' already exists", file=sys.stderr)
            results.append({"group": group_name, "status": "exists"})
        else:
            print(f"Creating group '{group_name}'...", file=sys.stderr)
            result = create_group(lldap_url, token, group_name)

            if result["status"] == "created":
                print(f"✓ {result['message']}", file=sys.stderr)
                changed = True
                results.append({"group": group_name, "status": "created"})
            elif result["status"] == "exists":
                print(f"✓ {result['message']}", file=sys.stderr)
                results.append({"group": group_name, "status": "exists"})
            else:
                print(f"✗ {result['message']}", file=sys.stderr)
                results.append({"group": group_name, "status": "error", "message": result["message"]})

    # Output JSON for Ansible
    output = {
        "changed": changed,
        "groups": results,
        "msg": f"Processed {len(groups_to_create)} groups: {sum(1 for r in results if r['status'] == 'created')} created, {sum(1 for r in results if r['status'] == 'exists')} already existed"
    }

    print(json.dumps(output))

if __name__ == "__main__":
    main()
