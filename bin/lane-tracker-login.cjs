/* Seed a logged-in East Agile tracker session into a lane's playwright-ticketer
 * Chromium profile, WITHOUT surfacing the password to an agent's context.
 * Driven by lane-qa-login.sh (ticketer target); credentials come in via env
 * (sourced from config/secrets.env). The tracker is a Django app with a
 * cookie-session login; we drive the UI headlessly and the session cookie
 * persists in the user-data-dir, so the playwright-ticketer MCP opens logged in.
 *
 * Robust to tracker UI drift: each field/button is found by trying several
 * selector strategies in order (id -> type -> name -> placeholder -> label ->
 * role), handles both the two-step (email -> Continue -> password) and a
 * single combined form, and detects the unique-code/2FA path so it fails with a
 * clear reason instead of a vague timeout.
 *
 * Env: FRONTEND_DIR USER_DATA_DIR TRACKER_URL EMAIL PASSWORD
 * Never logs the password. Exit 0 on success.
 */
const { createRequire } = require("module");

const FRONTEND_DIR = process.env.FRONTEND_DIR;
const USER_DATA_DIR = process.env.USER_DATA_DIR;
const TRACKER_URL = (process.env.TRACKER_URL || "").replace(/\/$/, "");
const EMAIL = process.env.EMAIL;
const PASSWORD = process.env.PASSWORD;
const LOGIN_TITLE = /log ?in|sign ?in/i; // page title while NOT authenticated

function fail(msg) { console.error("lane-tracker-login: " + msg); process.exit(1); }

(async () => {
  if (!FRONTEND_DIR || !USER_DATA_DIR) fail("FRONTEND_DIR and USER_DATA_DIR are required");
  if (!EMAIL || !PASSWORD) fail("EMAIL and PASSWORD are required (check config/secrets.env TRACKER_*)");

  const req = createRequire(FRONTEND_DIR + "/package.json");
  const { chromium } = req("@playwright/test");

  // Return the first locator (from a strategy list) that is actually visible,
  // or null. Makes the flow resilient to markup changes.
  async function firstVisible(page, strategies, timeoutMs = 12000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      for (const make of strategies) {
        try {
          const loc = make().first();
          if (await loc.isVisible()) return loc;
        } catch { /* selector not applicable on this render */ }
      }
      await page.waitForTimeout(300);
    }
    return null;
  }
  const emailStrategies = (p) => [
    () => p.locator("#email"),
    () => p.locator('input[type="email"]'),
    () => p.locator('input[name="email" i]'),
    () => p.getByPlaceholder(/email|name@/i),
    () => p.getByLabel(/email/i),
  ];
  const pwStrategies = (p) => [
    () => p.locator('input[type="password"]'),
    () => p.locator('input[name="password" i]'),
    () => p.getByPlaceholder(/password/i),
    () => p.getByLabel(/password/i),
  ];
  const submit = async (p) => {
    const btn = await firstVisible(p, [
      () => p.getByRole("button", { name: /continue|next|log ?in|sign ?in|submit/i }),
      () => p.locator('button[type="submit"]'),
      () => p.locator('input[type="submit"]'),
    ], 4000);
    if (btn) { await btn.click().catch(() => p.keyboard.press("Enter")); }
    else { await p.keyboard.press("Enter"); }
  };

  let ctx;
  try {
    ctx = await chromium.launchPersistentContext(USER_DATA_DIR, { headless: true });
    const page = ctx.pages()[0] || (await ctx.newPage());
    await page.goto(TRACKER_URL + "/", { waitUntil: "networkidle", timeout: 30000 });
    await page.waitForTimeout(1000);

    // Already authenticated (profile still valid)? Nothing to do.
    if (!LOGIN_TITLE.test(await page.title()) && !(await firstVisible(page, emailStrategies(page), 1500))) {
      await ctx.close();
      console.log(`lane-tracker-login: ${EMAIL} already authenticated — session kept`);
      return;
    }

    // Enter email (present in both the two-step and combined forms).
    const emailField = await firstVisible(page, emailStrategies(page), 15000);
    if (!emailField) fail("could not find the email field (tracker login UI changed?)");
    await emailField.fill(EMAIL);

    // Password may already be on the page (combined form) or appear after Continue.
    let pwField = await firstVisible(page, pwStrategies(page), 1500);
    if (!pwField) {
      await submit(page); // Continue past the email step
      await page.waitForTimeout(1500);
      pwField = await firstVisible(page, pwStrategies(page), 15000);
    }
    if (!pwField) {
      // No password field surfaced — likely the passwordless "unique code" path.
      const otp = await firstVisible(page, [
        () => page.getByText(/unique code|one-time|verification code|check your email/i),
        () => page.locator('input[autocomplete="one-time-code"]'),
      ], 2000);
      if (otp) fail("tracker is on the unique-code/2FA path (no password field) — seed this profile by logging in once by hand");
      fail("could not find the password field (tracker login UI changed?)");
    }
    await pwField.fill(PASSWORD);
    await submit(page);
    await page.waitForTimeout(4000);

    // Verify: reload and confirm we're not bounced back to a login screen.
    await page.goto(TRACKER_URL + "/", { waitUntil: "networkidle", timeout: 30000 });
    await page.waitForTimeout(1500);
    const stillLogin = LOGIN_TITLE.test(await page.title())
      || !!(await firstVisible(page, emailStrategies(page), 1500));
    if (stillLogin) {
      fail(`login rejected for ${EMAIL} (wrong password, or a unique-code/2FA step is required)`);
    }
    await ctx.close(); // flush the session cookie into the user-data-dir
  } catch (e) {
    try { if (ctx) await ctx.close(); } catch { /* ignore */ }
    fail(`seeding the tracker profile failed: ${e.message}`);
  }

  console.log(`lane-tracker-login: ${EMAIL} session seeded into ${USER_DATA_DIR}`);
})();
