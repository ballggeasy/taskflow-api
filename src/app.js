const express = require('express');

function createApp() {
  const app = express();
  app.use(express.json());
  const tasks = [];
  let nextId = 1;

  app.get('/health', (req, res) => res.json({ status: 'ok' }));
  app.get('/tasks', (req, res) => res.json(tasks));
  app.post('/tasks', (req, res) => {
    if (!req.body || !req.body.title) {
      return res.status(400).json({ error: 'title required' });
    }
    const task = { id: nextId++, title: req.body.title, done: false };
    tasks.push(task);
    return res.status(201).json(task);
  });
  app.patch('/tasks/:id/done', (req, res) => {
    const task = tasks.find((t) => t.id === Number(req.params.id));
    if (!task) return res.status(404).json({ error: 'not found' });
    task.done = true;
    return res.json(task);
  });
  return app;
}

module.exports = { createApp };
