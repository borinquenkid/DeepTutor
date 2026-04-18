import { test, expect } from "@playwright/test";

const BASE_URL = process.env.WEB_BASE_URL || "http://localhost:3782";

test.describe("Settings Flow :: Zero-Friction UX", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(`${BASE_URL}/settings?tour=true`);
  });

  test("uses student-friendly agent roles instead of technical jargon", async ({ page }) => {
    // Check main tabs/labels
    await expect(page.locator("text=The Brain")).toBeVisible();
    await expect(page.locator("text=The Librarian")).toBeVisible();
    await expect(page.locator("text=The Explorer")).toBeVisible();
  });

  test("provides magic links to get API keys", async ({ page }) => {
    // Navigate to Brain (LLM) tab
    await page.click("text=The Brain");
    
    // Select Gemini provider
    await page.selectOption("select >> nth=0", { label: "Gemini" });
    
    // Check for Magic Link
    const magicLink = page.locator("text=Get Gemini Key");
    await expect(magicLink).toBeVisible();
    await expect(magicLink).toHaveAttribute("href", /aistudio.google.com/);

    // Switch to OpenAI
    await page.selectOption("select >> nth=0", { label: "OpenAI" });
    const openAiLink = page.locator("text=Get OpenAI Key");
    await expect(openAiLink).toBeVisible();
    await expect(openAiLink).toHaveAttribute("href", /platform.openai.com/);
  });

  test("simplified labels in Step header", async ({ page }) => {
    await expect(page.locator("text=Step 1: The Brain")).toBeVisible();
  });
});
