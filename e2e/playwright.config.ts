import { defineConfig, devices } from "@playwright/test";

// Stack: e2e/docker-compose.e2e.yml (ver e2e/README no test-plan). Um worker: a stack e o wa falso são compartilhados.
export default defineConfig({
  testDir: ".",
  testMatch: /.*\.spec\.ts/,
  globalSetup: "./support/global-setup.ts",
  workers: 1,
  fullyParallel: false,
  retries: 0,
  timeout: 90_000,
  reporter: [["list"], ["json", { outputFile: "test-results/results.json" }]],
  use: {
    baseURL: process.env.BASE_URL ?? `http://127.0.0.1:${process.env.E2E_PORT ?? 3555}`,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    locale: "pt-BR",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
