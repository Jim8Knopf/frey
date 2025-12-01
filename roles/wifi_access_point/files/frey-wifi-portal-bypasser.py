#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import time
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.firefox.options import Options
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import (
    WebDriverException,
    TimeoutException,
    NoSuchElementException,
)

# --- Configuration ---
# Keywords to identify acceptance checkboxes
CHECKBOX_KEYWORDS = [
    "terms",
    "accept",
    "agree",
    "conditions",
    "policy",
]

# Keywords to identify submission buttons
BUTTON_KEYWORDS = [
    "connect",
    "accept",
    "agree",
    "continue",
    "login",
    "submit",
    "free",
]

# URL to test for successful internet connection
SUCCESS_TEST_URL = "http://detectportal.firefox.com/success.txt"


def log(message):
    """Prints a message to stderr."""
    print(f"[PortalBypasser] {message}", file=sys.stderr)


class PortalBypasser:
    def __init__(self, portal_url):
        self.portal_url = portal_url
        self.driver = None

    def _setup_driver(self):
        """Initializes a headless Firefox WebDriver."""
        log("Setting up headless browser (Firefox)...")
        try:
            options = Options()
            options.add_argument("--headless")
            options.add_argument("--disable-gpu")
            options.add_argument("--no-sandbox")
            # Some portals block based on user agent
            options.set_preference(
                "general.useragent.override",
                "Mozilla/5.0 (Windows NT 10.0; rv:102.0) Gecko/20100101 Firefox/102.0",
            )
            self.driver = webdriver.Firefox(options=options)
            self.driver.set_page_load_timeout(30)
            log("Browser setup complete.")
            return True
        except WebDriverException as e:
            log(f"ERROR: Failed to set up Firefox WebDriver: {e}")
            log(
                "Please ensure Firefox and geckodriver are installed and in the system's PATH."
            )
            return False

    def _find_and_click_elements(self):
        """Finds and clicks checkboxes and buttons based on keywords."""
        wait = WebDriverWait(self.driver, 10)

        # 1. Click Checkboxes
        for keyword in CHECKBOX_KEYWORDS:
            try:
                # Find labels containing the keyword and get their associated checkbox
                xpath = f"//label[contains(translate(., 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), '{keyword}')]/input[@type='checkbox'] | //input[@type='checkbox' and contains(translate(@name, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), '{keyword}')]"
                checkboxes = self.driver.find_elements(By.XPATH, xpath)
                for checkbox in checkboxes:
                    if not checkbox.is_selected():
                        log(f"Found and clicking checkbox related to '{keyword}'...")
                        # Sometimes clicks are intercepted, try JS click as a fallback
                        try:
                            wait.until(EC.element_to_be_clickable(checkbox)).click()
                        except Exception:
                            self.driver.execute_script("arguments[0].click();", checkbox)
                        time.sleep(1)
            except NoSuchElementException:
                continue

        # 2. Click Buttons
        for keyword in BUTTON_KEYWORDS:
            try:
                # Find buttons or inputs of type submit/button with keyword in text or value
                xpath = f"//button[contains(translate(., 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), '{keyword}')] | //input[@type='submit' or @type='button'][contains(translate(@value, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), '{keyword}')]"
                buttons = self.driver.find_elements(By.XPATH, xpath)
                if buttons:
                    log(f"Found button related to '{keyword}'. Clicking it.")
                    try:
                        wait.until(EC.element_to_be_clickable(buttons[0])).click()
                    except Exception:
                        self.driver.execute_script("arguments[0].click();", buttons[0])
                    # After clicking a button, we assume it's the final action
                    return True
            except NoSuchElementException:
                continue
        return False # Return false if no button was clicked

    def _test_connection(self):
        """Tests if internet connection is successful."""
        log("Testing for internet connectivity...")
        try:
            self.driver.get(SUCCESS_TEST_URL)
            # "success" is the content of the page on success
            return "success" in self.driver.page_source.lower()
        except (WebDriverException, TimeoutException):
            return False

    def bypass(self):
        """Main method to run the bypass process."""
        if not self._setup_driver():
            return False

        try:
            log(f"Navigating to portal URL: {self.portal_url}")
            self.driver.get(self.portal_url)
            time.sleep(5)  # Allow page to load fully

            self._find_and_click_elements()
            
            log("Waiting a few seconds for connection to establish...")
            time.sleep(10)

            if self._test_connection():
                log("SUCCESS: Captive portal bypassed.")
                return True
            else:
                log("FAILURE: Could not bypass captive portal.")
                return False

        except (WebDriverException, TimeoutException) as e:
            log(f"An error occurred during bypass: {e}")
            return False
        finally:
            if self.driver:
                self.driver.quit()
                log("Browser closed.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 portal_bypasser.py <portal_url>", file=sys.stderr)
        sys.exit(1)

    portal_url_arg = sys.argv[1]
    bypasser = PortalBypasser(portal_url_arg)
    if bypasser.bypass():
        sys.exit(0)
    else:
        sys.exit(1)
