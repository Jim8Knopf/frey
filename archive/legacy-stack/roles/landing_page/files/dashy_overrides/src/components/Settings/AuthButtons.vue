<template>
  <div>
    <!-- If auth configured, show status text -->
    <span class="user-type-note">{{ makeUserGreeting() }}</span>
    <div class="display-options">
      <!-- If user logged in, show logout button -->
      <IconLogout
        v-if="userType == userStateEnum.loggedIn"
        @click="logout()"
        v-tooltip="tooltip($t('settings.sign-out-tooltip'))"
        class="layout-icon" tabindex="-2"
      />
      <!-- If not logged in, and guest mode enabled, show login button -->
      <IconLogin
        v-if="userType == userStateEnum.guestAccess"
        @click="goToLogin()"
        v-tooltip="tooltip($t('settings.sign-in-tooltip'))"
        class="layout-icon login-callout"
        tabindex="-2"
        aria-label="Sign in"
      />
      <!-- If user logged in via keycloak, show keycloak logout button -->
      <IconLogout
        v-if="userType == userStateEnum.keycloakEnabled"
        @click="keycloakLogout()"
        v-tooltip="tooltip($t('settings.sign-out-tooltip'))"
        class="layout-icon" tabindex="-2"
      />
      <!-- If user logged in via oidc, show oidc logout button -->
      <IconLogout
        v-if="userType == userStateEnum.oidcEnabled"
        @click="oidcLogout()"
        v-tooltip="tooltip($t('settings.sign-out-tooltip'))"
        class="layout-icon" tabindex="-2"
      />
    </div>
  </div>
</template>

<script>
import router from '@/router';
import { logout as registerLogout } from '@/utils/Auth';
import { getKeycloakAuth } from '@/utils/KeycloakAuth';
import { getOidcAuth, isOidcEnabled } from '@/utils/OidcAuth';
import { localStorageKeys, userStateEnum } from '@/utils/defaults';
import IconLogout from '@/assets/interface-icons/user-logout.svg';
import IconLogin from '@/assets/interface-icons/user-login.svg';

export default {
  name: 'AuthButtons',
  components: {
    IconLogout,
    IconLogin,
  },
  props: {
    userType: Number,
  },
  data() {
    return {
      userStateEnum,
    };
  },
  methods: {
    logout() {
      registerLogout();
      this.$toasted.show(this.$t('login.logout-message'));
      setTimeout(() => {
        router.push({ path: '/login' });
      }, 500);
    },
    oidcLogout() {
      const oidc = getOidcAuth();
      this.$toasted.show(this.$t('login.logout-message'));
      setTimeout(() => {
        oidc.logout();
      }, 500);
    },
    keycloakLogout() {
      const keycloak = getKeycloakAuth();
      this.$toasted.show(this.$t('login.logout-message'));
      setTimeout(() => {
        keycloak.logout();
      }, 500);
    },
    goToLogin() {
      if (isOidcEnabled()) {
        const oidc = getOidcAuth();
        if (oidc) {
          oidc.beginLogin();
          return;
        }
      }
      router.push({ path: '/login' });
    },
    tooltip(content) {
      return { content, trigger: 'hover focus', delay: 250 };
    },
    makeUserGreeting() {
      if (this.userType === userStateEnum.loggedIn
        || this.userType === userStateEnum.keycloakEnabled) {
        const username = localStorage[localStorageKeys.USERNAME];
        return username ? this.$t('settings.sign-in-welcome', { username }) : '';
      }
      if (this.userType === userStateEnum.guestAccess) {
        return this.$t('settings.sign-in-tooltip');
      }
      return '';
    },
  },
};
</script>

<style scoped lang="scss">
@import '@/styles/style-helpers.scss';

span.user-type-note {
  color: var(--settings-text-color);
  margin-right: 0.5rem;
}

.display-options {
  @extend .svg-button;
  color: var(--settings-text-color);
}

.login-callout {
  width: 2.85rem;
  height: 2.85rem;
  padding: 0.4rem;
  border-radius: 999px;
  border: 2px solid var(--accent-color, #f97316);
  color: #f97316;
  background: linear-gradient(135deg, rgba(249, 115, 22, 0.15), rgba(20, 184, 166, 0.15));
  box-shadow: 0 12px 30px rgba(249, 115, 22, 0.35);
  transition: transform 0.2s ease, box-shadow 0.2s ease;
}

.login-callout:hover,
.login-callout:focus {
  transform: translateY(-2px) scale(1.05);
  box-shadow: 0 18px 35px rgba(249, 115, 22, 0.45);
  outline: none;
}

</style>
