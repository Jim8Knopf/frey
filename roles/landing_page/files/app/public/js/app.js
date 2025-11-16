// App state
let config = null;
let user = null;
let services = null;

// Initialize app
async function init() {
  try {
    // Fetch config
    config = await fetchJSON('/api/config');

    // If authenticated, fetch user and services
    if (config.isAuthenticated) {
      try {
        user = await fetchJSON('/api/user');
        services = await fetchJSON('/api/services');
      } catch (err) {
        console.error('Error fetching user data:', err);
      }
    }

    // Render the app
    render();
  } catch (error) {
    console.error('Initialization error:', error);
    showError('Failed to load application');
  } finally {
    hideLoading();
  }
}

// Fetch JSON helper
async function fetchJSON(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
  }
  return response.json();
}

// Show/hide loading
function hideLoading() {
  document.getElementById('loading').style.display = 'none';
  document.getElementById('content').style.display = 'block';
}

function showError(message) {
  const content = document.getElementById('content');
  content.innerHTML = `
    <div class="container" style="padding: 2rem;">
      <div class="alert alert-error">
        <i class="fas fa-exclamation-triangle"></i>
        ${message}
      </div>
    </div>
  `;
}

// Render application
function render() {
  renderAuthButtons();
  renderWiFiCard();

  // Show certificate guide if not authenticated or on HTTP
  if (!config.isAuthenticated || !config.isHttps) {
    document.getElementById('cert-guide').style.display = 'block';
    document.getElementById('services-dashboard').style.display = 'none';
  } else {
    // Show services dashboard if authenticated via HTTPS
    document.getElementById('cert-guide').style.display = 'none';
    document.getElementById('services-dashboard').style.display = 'block';
    renderServices();
  }
}

// Render auth buttons
function renderAuthButtons() {
  const container = document.getElementById('auth-buttons');

  if (config.isAuthenticated && user) {
    container.innerHTML = `
      <div class="user-info">
        <i class="fas fa-user"></i>
        <span>${escapeHtml(user.name)}</span>
      </div>
      <a href="/auth/logout" class="btn btn-sm">
        <i class="fas fa-sign-out-alt"></i>
        Logout
      </a>
    `;
  } else {
    container.innerHTML = `
      <a href="/auth/login" class="btn btn-sm btn-primary">
        <i class="fas fa-sign-in-alt"></i>
        Login
      </a>
    `;
  }
}

// Render WiFi card
function renderWiFiCard() {
  const wifiCard = document.getElementById('wifi-card');

  if (config.wifi.enabled) {
    wifiCard.style.display = 'block';
    document.getElementById('wifi-ssid').textContent = config.wifi.ssid;

    // Add event listener for connect button
    document.getElementById('wifi-connect-btn').addEventListener('click', connectWiFi);
  } else {
    wifiCard.style.display = 'none';
  }
}

// Connect to WiFi
async function connectWiFi() {
  const password = document.getElementById('wifi-password').value;
  const statusEl = document.getElementById('wifi-status');
  const btn = document.getElementById('wifi-connect-btn');

  if (!password) {
    statusEl.innerHTML = '<div class="alert alert-error">Please enter a password</div>';
    return;
  }

  btn.disabled = true;
  btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Connecting...';

  try {
    const response = await fetch('/api/wifi/connect', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ password }),
    });

    const result = await response.json();

    if (result.success) {
      statusEl.innerHTML = '<div class="alert alert-success"><i class="fas fa-check"></i> Connected successfully!</div>';
      document.getElementById('wifi-password').value = '';
    } else {
      statusEl.innerHTML = '<div class="alert alert-error"><i class="fas fa-times"></i> Connection failed</div>';
    }
  } catch (error) {
    statusEl.innerHTML = '<div class="alert alert-error"><i class="fas fa-times"></i> Connection error</div>';
  } finally {
    btn.disabled = false;
    btn.innerHTML = '<i class="fas fa-link"></i> Connect';
  }
}

// Render services
function renderServices() {
  const container = document.getElementById('services-sections');

  if (!services || services.length === 0) {
    container.innerHTML = `
      <div class="card">
        <p>No services available. Contact your administrator for access.</p>
      </div>
    `;
    return;
  }

  let html = '';

  services.forEach(section => {
    if (section.services.length === 0) return; // Skip empty sections

    html += `
      <div class="services-section">
        <div class="section-header">
          <i class="${escapeHtml(section.icon)}"></i>
          <h2>${escapeHtml(section.name)}</h2>
        </div>
        ${section.description ? `<p class="section-description">${escapeHtml(section.description)}</p>` : ''}
        <div class="services-grid">
          ${section.services.map(service => renderServiceCard(service)).join('')}
        </div>
      </div>
    `;
  });

  container.innerHTML = html;
}

// Render individual service card
function renderServiceCard(service) {
  return `
    <a href="${escapeHtml(service.url)}" target="_blank" class="service-card">
      <div class="service-icon">
        <i class="${escapeHtml(service.icon)}"></i>
      </div>
      <div class="service-title">${escapeHtml(service.title)}</div>
      <div class="service-description">${escapeHtml(service.description)}</div>
      ${service.tags && service.tags.length > 0 ? `
        <div class="service-tags">
          ${service.tags.map(tag => `<span class="tag">${escapeHtml(tag)}</span>`).join('')}
        </div>
      ` : ''}
    </a>
  `;
}

// Escape HTML helper
function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', init);
