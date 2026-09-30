const { defineConfig } = require('@playwright/test');

module.exports = defineConfig({
  testDir: '.',
  timeout: 30000,
  reporter: [
    ['list'],
    ['junit', { outputFile: '../reports/e2e-junit.xml' }],
    ['html', { outputFolder: '../playwright-report', open: 'never' }],
  ],
  use: { baseURL: process.env.API_URL || 'http://localhost:8080' },
});
