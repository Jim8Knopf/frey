<template>
  <div class="login-page">
    <section class="guest-onboarding" v-if="!isUserAlreadyLoggedIn">
      <article class="onboarding-card doc-card">
        <div>
          <p class="eyebrow">Documentation</p>
          <h2>Frey User Guide</h2>
          <p>Review every stack and role before requesting access.</p>
        </div>
        <div class="button-row">
          <a
            :href="userGuideUrl"
            target="_blank"
            rel="noopener"
            class="cta-button"
          >
            Open Guide
          </a>
          <a
            :href="certificateGuideUrl"
            target="_blank"
            rel="noopener"
            class="ghost-button"
          >
            Certificate Guide
          </a>
        </div>
      </article>
      <article class="onboarding-card cert-card">
        <div>
          <p class="eyebrow">Trust Frey</p>
          <h2>Install the Root Certificate</h2>
          <p>Download the Frey CA over HTTP, install it, then switch to HTTPS.</p>
        </div>
        <div class="button-row stacked">
          <a
            :href="certificateDownloadUrl"
            class="cta-button"
            download
          >
            Download CA
          </a>
          <div class="protocol-links">
            <span>Dashboard endpoints:</span>
            <a :href="httpOrigin">HTTP</a>
            <span>•</span>
            <a :href="httpsOrigin">HTTPS</a>
          </div>
        </div>
      </article>
    </section>
    <!-- User is already logged in -->
    <div v-if="isUserAlreadyLoggedIn" class="already-logged-in">
      <h2>{{ $t('login.already-logged-in-title') }}</h2>
      <p class="already-logged-in">
        {{ $t('login.already-logged-in-text') }}
        <span class="username">{{ existingUsername }}</span>
      </p>
      <Button class="login-button" :click="stayLoggedIn">
        {{ $t('login.proceed-to-dashboard') }}
      </Button>
      <Button class="login-button" :click="getOut">{{ $t('login.log-out-button') }}</Button>
      <span class="already-logged-in-note">
        You need to log out, in order to proceed as a different user.
      </span>
      <transition name="bounce">
        <p :class="`login-error-message ${status}`" v-show="message">{{ message }}</p>
      </transition>
    </div>
    <!-- OIDC login -->
    <div class="oidc-login" v-if="isOidcEnabled && !isUserAlreadyLoggedIn">
      <h2 class="login-title">Single Sign-On</h2>
      <p class="oidc-description">
        Use Authentik to sign in and unlock personalized tiles.
      </p>
      <Button class="login-button" :click="oidcLogin">
        Continue to Authentik
      </Button>
    </div>
    <!-- Main login form -->
    <form
      class="login-form"
      v-if="(!isUserAlreadyLoggedIn) && !isOidcEnabled && isAuthenticationEnabled">
      <h2 class="login-title">{{ $t('login.title') }}</h2>
      <Input type="text"
        v-model="username"
        :onEnter="submitLogin"
        :label="$t('login.username-label')"
        class="login-field username"
      />
      <Input type="password"
        v-model="password"
        :onEnter="submitLogin"
        :label="$t('login.password-label')"
        class="login-field password"
      />
      <label>{{ $t('login.remember-me-label') }}</label>
      <v-select
        v-model="timeout"
        :selectOnTab="true"
        :options="dropDownMenu"
        :map-keydown="(map) => ({ ...map, 13: () => this.submitLogin() })"
        class="login-time-dropdown"
      />
      <Button class="login-button" :click="submitLogin">
        {{ $t('login.login-button') }}
      </Button>
      <transition name="bounce">
        <p :class="`login-error-message ${status}`" v-show="message">{{ message }}</p>
      </transition>
    </form>
    <!-- Guest login form -->
    <form class="guest-form"
      v-if="isGuestAccessEnabled && !isUserAlreadyLoggedIn && isAuthenticationEnabled">
      <h2 class="login-title">{{ $t('login.guest-label') }}</h2>
      <Button class="login-button" :click="guestLogin">
        {{ $t('login.proceed-guest-button') }}
      </Button>
      <p class="guest-intro">
        {{ $t('login.guest-intro-1') }}<br>
        {{ $t('login.guest-intro-2') }}
      </p>
    </form>
    <!-- Edge case - guest mode enabled, but no users configured -->
    <div class="not-configured" v-if="!isAuthenticationEnabled">
      <h2>{{ $t('login.error') }}</h2>
      <p>{{ $t('login.error-no-user-configured') }}</p>
      <Button class="login-button" :click="guestLogin">
        {{ $t('login.error-go-home-button') }}
      </Button>
    </div>
  </div>
</template>

<script>
import router from '@/router';
import Button from '@/components/FormElements/Button';
import Input from '@/components/FormElements/Input';
import Defaults, { localStorageKeys } from '@/utils/defaults';
import { InfoHandler, WarningInfoHandler, InfoKeys } from '@/utils/ErrorHandler';
import {
  checkCredentials,
  login,
  isLoggedIn,
  logout,
  isGuestAccessEnabled,
} from '@/utils/Auth';
import { getOidcAuth, isOidcEnabled } from '@/utils/OidcAuth';

export default {
  name: 'login',
  components: {
    Button,
    Input,
  },
  data() {
    return {
      username: '',
      password: '',
      message: '',
      status: 'waiting', // wating, error, success
      timeout: undefined,
    };
  },
  computed: {
    appConfig() {
      return this.$store.getters.appConfig;
    },
    /* Data for timeout dropdown menu, translated label + value in ms */
    dropDownMenu() {
      return [
        { label: this.$t('login.remember-me-never'), time: 0 },
        { label: this.$t('login.remember-me-hour'), time: 14400 * 1000 },
        { label: this.$t('login.remember-me-day'), time: 86400 * 1000 },
        { label: this.$t('login.remember-me-week'), time: 604800 * 1000 },
        { label: this.$t('login.remember-me-long-time'), time: 604800 * 52 * 1000 },
      ];
    },
    /* Translations for login response messages */
    responseMessages() {
      return {
        missingUsername: this.$t('login.error-missing-username'),
        missingPassword: this.$t('login.error-missing-password'),
        incorrectUsername: this.$t('login.error-incorrect-username'),
        incorrectPassword: this.$t('login.error-incorrect-password'),
        successMsg: this.$t('login.success-message'),
      };
    },
    existingUsername() {
      return localStorage[localStorageKeys.USERNAME];
    },
    users() {
      const auth = this.appConfig.auth || {};
      return Array.isArray(auth) ? auth : auth.users || [];
    },
    isOidcEnabled() {
      return isOidcEnabled();
    },
    freyLinks() {
      return this.appConfig.freyLinks || {};
    },
    userGuideUrl() {
      const path = this.freyLinks.userGuide || '/assets/docs/frey-user-guide.html';
      return new URL(path, window.location.origin).toString();
    },
    certificateGuideUrl() {
      const path = this.freyLinks.certificateGuide || '/assets/docs/frey-ca.html';
      return new URL(path, window.location.origin).toString();
    },
    certificateDownloadUrl() {
      const path = this.freyLinks.certificateDownload || '/assets/frey-root-ca.crt';
      return new URL(path, window.location.origin).toString();
    },
    httpOrigin() {
      const url = new URL(window.location.href);
      url.protocol = 'http:';
      url.pathname = '/';
      url.search = '';
      url.hash = '';
      return url.toString().replace(/\/$/, '');
    },
    httpsOrigin() {
      const url = new URL(window.location.href);
      url.protocol = 'https:';
      url.pathname = '/';
      url.search = '';
      url.hash = '';
      return url.toString().replace(/\/$/, '');
    },
    isUserAlreadyLoggedIn() {
      const loggedIn = (!this.users || this.users.length === 0 || isLoggedIn());
      return (loggedIn && this.existingUsername);
    },
    isGuestAccessEnabled() {
      return isGuestAccessEnabled();
    },
    isAuthenticationEnabled() {
      const localAuthReady = this.appConfig && this.appConfig.auth && this.users.length > 0;
      return this.isOidcEnabled || localAuthReady;
    },
  },
  methods: {
    /* Checks form is filled in, then initiates the login, and redirects to /home */
    submitLogin() {
      // Use selected timeout, if available,else revedrt to zero
      const timeout = this.timeout ? this.timeout.time : 0;
      // Check users credentials
      const response = checkCredentials(
        this.username,
        this.password,
        this.users, // All users
        this.responseMessages, // Translated response messages
      );
      this.message = response.msg; // Show error or success message to the user
      this.status = response.correct ? 'success' : 'error';
      if (response.correct) { // Yay, credentials were correct :)
        login(this.username, this.password, timeout); // Login, to set the cookie
        this.goHome();
        InfoHandler(`Succesfully signed in as ${this.username}`, InfoKeys.AUTH);
      } else {
        WarningInfoHandler('Unable to Sign In', InfoKeys.AUTH, this.message);
      }
    },
    /* Calls function to double-check guest access enabled, then log in as guest */
    guestLogin() {
      const isAllowed = this.isGuestAccessEnabled;
      if (isAllowed) {
        this.$toasted.show(this.$t('login.logged-in-guest'), { className: 'toast-success' });
        InfoHandler('Logged in as Guest', InfoKeys.AUTH);
        this.goHome();
      } else {
        this.$toasted.show(this.$t('login.error-guest-access'), { className: 'toast-error' });
        WarningInfoHandler('Guest Access Not Allowed', InfoKeys.AUTH);
      }
    },
    /* Calls logout, shows status message, and refreshed page */
    getOut() {
      logout();
      this.status = 'success';
      this.message = 'Logging out...';
      this.refreshPage();
    },
    oidcLogin() {
      const oidc = getOidcAuth();
      if (oidc) {
        oidc.beginLogin();
      } else {
        this.$toasted.show(this.$t('login.error'), { className: 'toast-error' });
      }
    },
    /* Logged in user redirects to home page */
    stayLoggedIn() {
      this.status = 'success';
      this.message = 'Redirecting...';
      this.goHome();
    },
    /* Refreshes the page */
    refreshPage() {
      setTimeout(() => { location.reload(); }, 250); // eslint-disable-line no-restricted-globals
    },
    /* Redirects to the homepage */
    goHome() {
      setTimeout(() => { // Wait a short while, then redirect back home
        router.push({ path: '/' });
      }, 250);
    },
    /* Since Theme setter isn't loaded at this point, we must manually get and apply users theme */
    setTheme() {
      const theme = localStorage[localStorageKeys.THEME] || Defaults.theme;
      document.getElementsByTagName('html')[0].setAttribute('data-theme', theme);
    },
  },
  created() {
    this.setTheme();
    setTimeout(() => { this.timeout = this.dropDownMenu[0]; }, 1); //eslint-disable-line
  },
};

</script>

<style lang="scss">

.guest-onboarding {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 1.25rem;
  margin: 0 auto 2rem;
  width: min(1100px, 100%);
}

.onboarding-card {
  background: rgba(13, 19, 33, 0.9);
  border: 1px solid rgba(148, 163, 184, 0.35);
  border-radius: 18px;
  padding: 1.75rem;
  min-height: 220px;
  box-shadow: 0 25px 55px rgba(2, 6, 23, 0.55);
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}

.doc-card {
  background: radial-gradient(circle at top, rgba(79, 70, 229, 0.35), rgba(15, 23, 42, 0.95));
}

.cert-card {
  background: radial-gradient(circle at top, rgba(17, 94, 89, 0.35), rgba(15, 23, 42, 0.95));
}

.eyebrow {
  text-transform: uppercase;
  letter-spacing: 0.25em;
  font-size: 0.75rem;
  color: rgba(248, 250, 252, 0.7);
  margin-bottom: 0.25rem;
}

.button-row {
  display: flex;
  gap: 0.75rem;
  flex-wrap: wrap;
  margin-top: 1.25rem;
}

.button-row.stacked {
  flex-direction: column;
}

.cta-button,
.ghost-button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0.9rem 1.4rem;
  border-radius: 999px;
  font-weight: 600;
  text-decoration: none;
  transition: transform 0.2s ease, box-shadow 0.2s ease;
}

.cta-button {
  background: linear-gradient(135deg, #f97316, #facc15);
  color: #0f172a;
  box-shadow: 0 15px 40px rgba(249, 115, 22, 0.55);
}

.ghost-button {
  border: 1px solid rgba(255, 255, 255, 0.5);
  color: #f8fafc;
}

.cta-button:hover,
.ghost-button:hover {
  transform: translateY(-1px);
}

.protocol-links {
  display: flex;
  gap: 0.4rem;
  flex-wrap: wrap;
  color: rgba(248, 250, 252, 0.85);
  font-size: 0.9rem;
}

.protocol-links a {
  color: #fef3c7;
  text-decoration: underline;
}

.guest-onboarding + .already-logged-in,
.guest-onboarding + .oidc-login,
.guest-onboarding + .login-form {
  margin-top: 0;
}

.guest-onboarding {
  @media (max-width: 700px) {
    grid-template-columns: 1fr;
  }
}

/* Login page base styles */
.login-page {
  display: flex;
  align-items: center;
  justify-content: center;
  justify-content: space-evenly;
  min-height: calc(100vh - var(--footer-height));

  .oidc-login {
    text-align: center;
    max-width: 24rem;
    .oidc-description {
      margin-bottom: 1rem;
      opacity: var(--dimming-factor);
    }
  }

  /* User is already logged in note */
  div.already-logged-in {
    margin: 0 auto 0.5rem;
    p.already-logged-in {
      margin: 0 auto 0.5rem;
      text-align: center;
    }
    span.username {
      font-weight: bold;
      text-transform: capitalize;
    }
    span.already-logged-in-note {
      font-size: 0.8rem;
      opacity: var(--dimming-factor);
      text-align: left;
    }
  }

  /* Login form container */
  form.login-form, form.guest-form, div.already-logged-in, div.not-configured {
    background: var(--login-form-background);
    color: var(--login-form-color);
    border: 1px solid var(--login-form-color);
    border-radius: var(--curve-factor);
    font-size: 1.4rem;
    padding: 2rem;
    margin: 2rem;
    max-width: 22rem;
    display: flex;
    flex-direction: column;

    /* Login form title */
    h2 {
      font-size: 2rem;
      margin: 0 0 1rem 0;
      text-align: center;
      cursor: default;
    }

    /* Set sizings for input fields and login button */
    .login-field input, Button.login-button {
      width: 20rem;
      margin: 0.5rem auto;
      font-size: 1.4rem;
      padding: 0.5rem 1rem;
    }

    /* Custom colors for username/ password input fields */
    .login-field input {
      color: var(--login-form-color);
      border-color: var(--login-form-color);
      background: var(--login-form-background);
    }
    /* Custom colors for Login Button */
    Button.login-button {
      background: var(--login-form-color);
      border-color: var(--login-form-background);
      color: var(--login-form-background);
      &:hover {
        color: var(--login-form-color);
        border-color: var(--login-form-color);
        background: var(--login-form-background);
      }
      &:active, &:focus {
        box-shadow: 1px 1px 6px var(--login-form-color);
      }
    }
    /* Apply color to status message, depending on status */
    p.login-error-message {
      font-size: 1rem;
      text-align: center;
      &.waiting { color: var(--login-form-color); }
      &.success { color: var(--success); }
      &.error { color: var(--warning); }
    }
    p.guest-intro {
      font-size: 0.8rem;
      opacity: var(--dimming-factor);
      text-align: left;
    }
  }
}

/* Enter animations for error/ success message */
.bounce-enter-active { animation: bounce-in 0.25s; }
.bounce-leave-active { animation: bounce-in 0.25s reverse; }
@keyframes bounce-in {
  0% { transform: scale(0); }
  50% { transform: scale(1.25); }
  100% { transform: scale(1); }
}

/* Custom styles for dropdown component */
.v-select.login-time-dropdown {
  margin: 0.5rem 0;
  .vs__dropdown-toggle {
    border-color: var(--login-form-color);
    background: var(--login-form-background);
    cursor: pointer;
    span.vs__selected {
      color: var(--login-form-color);
    }
    .vs__actions svg path { fill: var(--login-form-color); }
  }
  ul.vs__dropdown-menu {
    background: var(--login-form-background);
    border-color: var(--login-form-color);
    li {
      color: var(--login-form-color);
      &:hover {
        color: var(--login-form-background);
        background: var(--login-form-color);
      }
      &.vs__dropdown-option--highlight {
        color: var(--login-form-background) !important;
        background: var(--login-form-color);
      }
    }
  }
}
</style>
