# Frey Landing Page

A custom landing page for the Frey home server that provides conditional content based on authentication state and protocol (HTTP/HTTPS).

## Features

- **Conditional Content Display**:
  - Shows certificate installation guide when not authenticated or accessing via HTTP
  - Shows filtered service dashboard when authenticated via HTTPS

- **OIDC Authentication**: Integrates with Authentik for single sign-on

- **Group-based Access Control**: Services are filtered based on user's group membership

- **WiFi Connection Interface**: Optional WiFi connection helper for AP clients

- **Mobile Optimized**: Responsive design works on all device sizes

## Architecture

- **Backend**: Node.js/Express with `openid-client` for OIDC
- **Frontend**: Vanilla JavaScript (no framework dependencies)
- **Authentication**: OIDC PKCE flow with Authentik
- **Session Management**: Express sessions with server-side storage

## Configuration

Configuration is provided via environment variables (set by Ansible):

- `OIDC_ISSUER`: Authentik OIDC issuer URL
- `OIDC_CLIENT_ID`: OIDC client ID
- `OIDC_REDIRECT_URI`: OAuth callback URL
- `OIDC_SCOPE`: OAuth scopes (openid profile email groups)
- `SESSION_SECRET`: Session encryption key
- `SERVICES_CONFIG`: JSON array of service sections and items
- `WIFI_ENABLED`: Enable WiFi connection interface
- `WIFI_SSID`: WiFi network SSID

## API Endpoints

- `GET /api/config` - Public configuration (auth state, HTTPS state, WiFi config)
- `GET /api/user` - Current user info (authenticated only)
- `GET /api/services` - Filtered services for current user (authenticated only)
- `GET /auth/login` - Initiate OIDC login
- `GET /auth/callback` - OIDC callback handler
- `GET /auth/logout` - Logout and destroy session
- `GET /api/wifi/status` - WiFi connection status
- `POST /api/wifi/connect` - Connect to WiFi network

## Development

```bash
npm install
npm start
```

## Deployment

The application is deployed as a Docker container, built via the Ansible role. The Dockerfile creates a minimal Node.js Alpine image with the application code.
