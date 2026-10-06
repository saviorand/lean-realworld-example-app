import { defineConfig } from '@playwright/test';
import { baseConfig } from './specs/playwright.base';

// The RealWorld frontend suite, which scripts/run-frontend-tests.sh copies into ./specs.
export default defineConfig({
  ...baseConfig,
  testDir: './specs',
  reporter: 'list',
  use: { ...baseConfig.use, baseURL: `http://localhost:${process.env.PORT ?? 8000}` },
});
