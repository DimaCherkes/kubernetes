import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Counter } from 'k6/metrics';

// ==============================================================================
// Custom Performance Metrics
// ==============================================================================
const taskCreateDuration = new Trend('task_create_duration_ms', true);
const taskListDuration = new Trend('task_list_duration_ms', true);
const taskDeleteDuration = new Trend('task_delete_duration_ms', true);
const tasksCreatedCount = new Counter('tasks_created_total');

// ==============================================================================
// Aggressive Stress-Test Configuration
// Targets limits of 2x Backend pods (1000m CPU limit) and Postgres (500m limit)
// ==============================================================================
export const options = {
  stages: [
    { duration: '15s', target: 50 },
    { duration: '45s', target: 100 },
    { duration: '15s', target: 150 },
    { duration: '15s', target: 0 },
  ],
  thresholds: {
    // Не более 5% ошибок даже на пике стресса
    http_req_failed: ['rate<0.05'],
    // 90% запросов должны уложиться в 1 секунду при пиковой нагрузке
    http_req_duration: ['p(90)<1000', 'p(95)<1500'],
  },
};

const BASE_URL = __ENV.TARGET_URL || 'http://localhost';

export default function () {
  const vuId = __VU;
  const iterId = __ITER;

  // ---------------------------------------------------------------------------
  // 1. Чтение статики фронтенда (нагрузка на Ingress + Nginx реплики)
  // ---------------------------------------------------------------------------
  const feRes = http.get(`${BASE_URL}/`, {
    tags: { type: 'frontend', endpoint: 'root' },
  });
  check(feRes, {
    'frontend status is 200': (r) => r.status === 200,
  });

  // ---------------------------------------------------------------------------
  // 2. Чтение списка задач (SELECT из PostgreSQL через Spring Data JPA)
  // ---------------------------------------------------------------------------
  const listStart = Date.now();
  const listRes = http.get(`${BASE_URL}/api/tasks`, {
    headers: { 'Accept': 'application/json' },
    tags: { type: 'backend_api', endpoint: 'get_tasks' },
  });
  taskListDuration.add(Date.now() - listStart);

  check(listRes, {
    'list status is 200': (r) => r.status === 200,
    'list returns valid tasks': (r) => {
      const data = r.json();
      return Array.isArray(data) || (data && Array.isArray(data.content));
    },
  });

  // ---------------------------------------------------------------------------
  // 3. Запись новой задачи (INSERT в PostgreSQL + генерация Trace в Tempo)
  // ---------------------------------------------------------------------------
  const payload = JSON.stringify({
    title: `Stress-Task [VU:${vuId}-Iter:${iterId}]`,
    description: `Load testing pod limits at ${new Date().toISOString()}`,
  });

  const createStart = Date.now();
  const createRes = http.post(`${BASE_URL}/api/tasks`, payload, {
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    tags: { type: 'backend_api', endpoint: 'create_task' },
  });
  taskCreateDuration.add(Date.now() - createStart);

  const createdOk = check(createRes, {
    'create status is 201': (r) => r.status === 201,
    'has created id': (r) => r.json('id') !== undefined,
    'has backend pod header': (r) => r.headers['X-Backend-Pod'] !== undefined,
  });

  if (createdOk) {
    tasksCreatedCount.add(1);
    const createdId = createRes.json('id');

    // -------------------------------------------------------------------------
    // 4. Обновление задачи (UPDATE транзакция)
    // -------------------------------------------------------------------------
    const updatePayload = JSON.stringify({
      title: `Stress-Task [VU:${vuId}-Iter:${iterId}] (Done)`,
      description: 'Completed under stress test load',
      completed: true,
    });

    const updateRes = http.put(`${BASE_URL}/api/tasks/${createdId}`, updatePayload, {
      headers: { 'Content-Type': 'application/json' },
      tags: { type: 'backend_api', endpoint: 'update_task' },
    });
    check(updateRes, { 'update status is 200': (r) => r.status === 200 });

    // -------------------------------------------------------------------------
    // 5. Удаление каждой 3-й задачи (DELETE транзакция для очистки базы)
    // -------------------------------------------------------------------------
    if (iterId % 3 === 0) {
      const delStart = Date.now();
      const delRes = http.del(`${BASE_URL}/api/tasks/${createdId}`, null, {
        tags: { type: 'backend_api', endpoint: 'delete_task' },
      });
      taskDeleteDuration.add(Date.now() - delStart);
      check(delRes, { 'delete status is 204': (r) => r.status === 204 });
    }
  }

  // Агрессивный темп: короткая пауза 100-300 мс между итерациями виртуального пользователя
  sleep(Math.random() * 0.2 + 0.1);
}
