const request = require('supertest');
const { createApp } = require('../src/app');

describe('taskflow-api', () => {
  test('health', async () => {
    const res = await request(createApp()).get('/health');
    expect(res.body.status).toBe('ok');
  });
});
