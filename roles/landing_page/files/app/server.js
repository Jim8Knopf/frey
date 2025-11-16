const express = require('express');
const session = require('express-session');
const { Issuer, generators } = require('openid-client');
const path = require('path');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 8080;

// Configuration from environment
const CONFIG = {
  oidc: {
    issuer: process.env.OIDC_ISSUER || 'https://auth.frey/application/o/dashy/',
    clientId: process.env.OIDC_CLIENT_ID || 'dashy',
    redirectUri: process.env.OIDC_REDIRECT_URI || 'https://frey/auth/callback',
    scope: process.env.OIDC_SCOPE || 'openid profile email groups',
  },
  session: {
    secret: process.env.SESSION_SECRET || 'change-me-in-production',
    maxAge: 24 * 60 * 60 * 1000, // 24 hours
  },
  services: JSON.parse(process.env.SERVICES_CONFIG || '[]'),
  wifi: {
    enabled: process.env.WIFI_ENABLED === 'true',
    ssid: process.env.WIFI_SSID || '',
  },
};

// Session middleware
app.use(session({
  secret: CONFIG.session.secret,
  resave: false,
  saveUninitialized: false,
  cookie: {
    secure: false, // Set to true when using HTTPS only
    maxAge: CONFIG.session.maxAge,
  },
}));

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

let oidcClient;

// Initialize OIDC client
async function initOIDC() {
  try {
    const issuer = await Issuer.discover(CONFIG.oidc.issuer);
    oidcClient = new issuer.Client({
      client_id: CONFIG.oidc.clientId,
      redirect_uris: [CONFIG.oidc.redirectUri],
      response_types: ['code'],
    });
    console.log('OIDC client initialized');
  } catch (error) {
    console.error('Failed to initialize OIDC:', error);
  }
}

// Routes
app.get('/api/config', (req, res) => {
  // Check if request is HTTPS (handle reverse proxy headers)
  const isHttps = req.protocol === 'https' ||
                  req.get('X-Forwarded-Proto') === 'https' ||
                  req.get('X-Forwarded-Ssl') === 'on';

  res.json({
    wifi: {
      enabled: CONFIG.wifi.enabled,
      ssid: CONFIG.wifi.ssid,
    },
    isAuthenticated: !!req.session.user,
    isHttps: isHttps,
  });
});

app.get('/api/user', (req, res) => {
  if (!req.session.user) {
    return res.status(401).json({ error: 'Not authenticated' });
  }
  res.json(req.session.user);
});

app.get('/api/services', (req, res) => {
  if (!req.session.user) {
    return res.status(401).json({ error: 'Not authenticated' });
  }

  const userGroups = req.session.user.groups || [];

  // Filter services based on user groups
  const filteredSections = CONFIG.services.map(section => {
    const filteredServices = section.services.filter(service => {
      // If no groups specified, show to all authenticated users
      if (!service.groups || service.groups.length === 0) {
        return true;
      }
      // Check if user has any of the required groups
      return service.groups.some(group => userGroups.includes(group));
    });

    return {
      ...section,
      services: filteredServices,
    };
  }).filter(section => section.services.length > 0); // Hide empty sections

  res.json(filteredSections);
});

app.get('/auth/login', async (req, res) => {
  if (!oidcClient) {
    return res.status(500).send('OIDC not configured');
  }

  const codeVerifier = generators.codeVerifier();
  const codeChallenge = generators.codeChallenge(codeVerifier);

  req.session.codeVerifier = codeVerifier;

  const authUrl = oidcClient.authorizationUrl({
    scope: CONFIG.oidc.scope,
    code_challenge: codeChallenge,
    code_challenge_method: 'S256',
  });

  res.redirect(authUrl);
});

app.get('/auth/callback', async (req, res) => {
  if (!oidcClient) {
    return res.status(500).send('OIDC not configured');
  }

  try {
    const params = oidcClient.callbackParams(req);
    const tokenSet = await oidcClient.callback(
      CONFIG.oidc.redirectUri,
      params,
      { code_verifier: req.session.codeVerifier }
    );

    const userinfo = await oidcClient.userinfo(tokenSet.access_token);

    req.session.user = {
      name: userinfo.name || userinfo.preferred_username,
      email: userinfo.email,
      groups: userinfo.groups || [],
    };

    delete req.session.codeVerifier;
    res.redirect('/');
  } catch (error) {
    console.error('Auth callback error:', error);
    res.status(500).send('Authentication failed');
  }
});

app.get('/auth/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/');
});

// WiFi API endpoints
app.get('/api/wifi/status', async (req, res) => {
  if (!CONFIG.wifi.enabled) {
    return res.status(404).json({ error: 'WiFi not enabled' });
  }

  try {
    // This would need to be implemented to check actual WiFi status
    // For now, return mock data
    res.json({
      connected: false,
      ssid: CONFIG.wifi.ssid,
      available: true,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/api/wifi/connect', async (req, res) => {
  if (!CONFIG.wifi.enabled) {
    return res.status(404).json({ error: 'WiFi not enabled' });
  }

  const { password } = req.body;

  // This would need actual implementation to connect to WiFi
  // Placeholder response
  res.json({ success: true });
});

// Serve index.html for all other routes
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Start server
initOIDC().then(() => {
  app.listen(PORT, () => {
    console.log(`Frey Landing Page running on port ${PORT}`);
  });
});
