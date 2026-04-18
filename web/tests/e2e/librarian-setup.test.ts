import { test, expect } from "@playwright/test";

const BASE_URL = process.env.WEB_BASE_URL || "http://localhost:3782";

test.describe("Librarian (Embedding) Setup", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(`${BASE_URL}/settings?tour=true`);
    await page.waitForLoadState("networkidle");
    
    // Dismiss tour spotlight if visible
    const skipTour = page.getByRole("button", { name: /Skip tour/i });
    if (await skipTour.isVisible()) {
        await skipTour.click();
    }
  });

  test("can select Gemini and see magic link for The Librarian", async ({ page }) => {
    // 1. Navigate to The Librarian tab
    const librarianTab = page.getByRole("button", { name: "The Librarian" }).first();
    await librarianTab.click({ force: true });
    
    await page.screenshot({ path: "librarian-tab.png" });

    // 2. Ensure a profile exists
    // Looking for the button specifically in the right side or by its text
    const addProfileButton = page.locator('button:has-text("Profile")').first();
    await addProfileButton.click({ force: true });

    // 3. Find the provider dropdown
    // Wait for the profile editor to appear
    await expect(page.locator('select')).toBeVisible({ timeout: 10000 });
    const providerSelect = page.locator('select').first();

    // 4. Select Gemini
    await providerSelect.selectOption({ label: "Gemini" }, { force: true });

    // 5. Verify the Magic Link for Gemini appears specifically for the Librarian
    const magicLink = page.getByRole("link", { name: "Get Gemini Key" });
    await expect(magicLink).toBeVisible();
    await expect(magicLink).toHaveAttribute("href", /aistudio.google.com/);
    
    // 6. Verify the placeholder or label for API Key
    const apiKeyLabel = page.getByText("API Key", { exact: true });
    await expect(apiKeyLabel).toBeVisible();
  });
});
