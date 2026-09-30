const { test, expect } = require('@playwright/test');

test('list tasks', async ({ request }) => {
  const res = await request.get('/tasks');
  expect(res.ok()).toBeTruthy();
  expect(Array.isArray(await res.json())).toBe(true);
});

test('create task', async ({ request }) => {
  const res = await request.post('/tasks', { data: { title: 'e2e task' } });
  expect(res.status()).toBe(201);
  const task = await res.json();
  expect(task).toMatchObject({ title: 'e2e task', done: false });
});

test('mark task done', async ({ request }) => {
  const created = await (await request.post('/tasks', { data: { title: 'finish me' } })).json();
  const res = await request.patch(`/tasks/${created.id}/done`);
  expect(res.ok()).toBeTruthy();
  expect((await res.json()).done).toBe(true);
});
