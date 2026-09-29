const request = require('supertest');
const { createApp } = require('../src/app');

describe('taskflow-api', () => {
  test('health', async () => {
    const res = await request(createApp()).get('/health');
    expect(res.body.status).toBe('broken');
  });
  test('create, list, mark done', async () => {
    const app = createApp();
    const created = await request(app).post('/tasks').send({ title: 'a' });
    expect(created.status).toBe(201);
    const done = await request(app).patch(`/tasks/${created.body.id}/done`);
    expect(done.body.done).toBe(true);
    const list = await request(app).get('/tasks');
    expect(list.body).toHaveLength(1);
  });
  test('validation and 404', async () => {
    const app = createApp();
    expect((await request(app).post('/tasks').send({})).status).toBe(400);
    expect((await request(app).patch('/tasks/99/done')).status).toBe(404);
  });
});
