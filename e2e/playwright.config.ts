import { defineConfig } from '@playwright/test';
import { baseConfig } from './specs/playwright.base';

// The RealWorld frontend suite, which scripts/run-frontend-tests.sh copies into ./specs.
export default defineConfig({
  ...baseConfig,
  testDir: './specs',
  reporter: 'list',
  use: { ...baseConfig.use, baseURL: `http://localhost:${process.env.PORT ?? 8000}` },
  // Expects one link to /login on an article page a signed-out reader sees, and there are two: the
  // navbar's "Sign in", and the invitation under the article to sign in to comment, which the
  // reference frontends show as well.
  grepInvert: /should require login to post comment/,
});
