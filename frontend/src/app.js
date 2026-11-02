/**
 * Kubernetes Full-Stack Task Manager SPA
 * Vanilla ES6 JavaScript Client with Server-Side Pagination
 */

'use strict';

(function () {
  // Configuration
  const API_BASE = '/api/tasks';
  const TOAST_DURATION_MS = 4000;

  // State
  let tasks = [];
  let currentFilter = 'all'; // 'all' | 'active' | 'completed'
  let currentPage = 0;
  let pageSize = 20;
  let totalPages = 1;
  let totalElements = 0;
  let totalCount = 0;
  let activeCount = 0;
  let completedCount = 0;
  let isSubmitting = false;
  let toastTimer = null;

  // DOM Elements
  const toastBanner = document.getElementById('toast-banner');
  const toastMessage = document.getElementById('toast-message');
  const toastIcon = document.getElementById('toast-icon');
  const toastCloseBtn = document.getElementById('toast-close-btn');

  const connectionIndicator = document.querySelector('.status-indicator');
  const connectionText = document.querySelector('.status-text');

  const totalCountEl = document.getElementById('total-count');
  const completedCountEl = document.getElementById('completed-count');
  const pendingCountEl = document.getElementById('pending-count');

  const filterAllCountEl = document.getElementById('filter-all-count');
  const filterActiveCountEl = document.getElementById('filter-active-count');
  const filterCompletedCountEl = document.getElementById('filter-completed-count');

  const taskForm = document.getElementById('task-form');
  const taskTitleInput = document.getElementById('task-title');
  const taskDescInput = document.getElementById('task-desc');
  const addTaskBtn = document.getElementById('add-task-btn');
  const clearFormBtn = document.getElementById('clear-form-btn');

  const filterButtons = document.querySelectorAll('.filter-btn');
  const refreshBtn = document.getElementById('refresh-btn');
  const refreshIcon = document.getElementById('refresh-icon');

  const taskListEl = document.getElementById('task-list');
  const loadingSpinner = document.getElementById('loading-spinner');
  const emptyState = document.getElementById('empty-state');
  const emptyTitle = document.getElementById('empty-title');
  const emptyDesc = document.getElementById('empty-desc');

  // Pagination Elements
  const paginationBar = document.getElementById('pagination-bar');
  const pageStartEl = document.getElementById('page-start');
  const pageEndEl = document.getElementById('page-end');
  const pageTotalEl = document.getElementById('page-total');
  const currentPageNumEl = document.getElementById('current-page-num');
  const totalPagesNumEl = document.getElementById('total-pages-num');
  const firstPageBtn = document.getElementById('first-page-btn');
  const prevPageBtn = document.getElementById('prev-page-btn');
  const nextPageBtn = document.getElementById('next-page-btn');
  const lastPageBtn = document.getElementById('last-page-btn');
  const pageSizeSelect = document.getElementById('page-size-select');

  // =========================================================================
  // Toast & Status Utilities
  // =========================================================================

  function showToast(message, type = 'error', duration = TOAST_DURATION_MS) {
    if (toastTimer) {
      clearTimeout(toastTimer);
      toastTimer = null;
    }

    toastMessage.textContent = message;
    toastBanner.className = `toast-banner ${type}`;

    if (type === 'success') {
      toastIcon.textContent = '✅';
    } else if (type === 'info') {
      toastIcon.textContent = 'ℹ️';
    } else {
      toastIcon.textContent = '⚠️';
    }

    toastBanner.classList.remove('hidden');

    if (duration > 0) {
      toastTimer = setTimeout(() => {
        hideToast();
      }, duration);
    }
  }

  function hideToast() {
    if (toastTimer) {
      clearTimeout(toastTimer);
      toastTimer = null;
    }
    toastBanner.classList.add('hidden');
  }

  function setConnectionStatus(online) {
    if (connectionIndicator) {
      connectionIndicator.className = `status-indicator ${online ? 'online' : 'offline'}`;
    }
    if (connectionText) {
      connectionText.textContent = online ? 'Ingress /api/tasks (Ready)' : 'Backend unreachable';
    }
  }

  function formatDate(isoString) {
    if (!isoString) return 'Just now';
    try {
      const date = new Date(isoString);
      if (isNaN(date.getTime())) return 'Recently';
      return date.toLocaleDateString(undefined, {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      });
    } catch {
      return 'Recently';
    }
  }

  // =========================================================================
  // API Fetch Helper
  // =========================================================================

  async function apiFetch(endpoint, options = {}) {
    const defaultHeaders = {
      'Accept': 'application/json'
    };

    if (options.body) {
      defaultHeaders['Content-Type'] = 'application/json';
    }

    const config = {
      ...options,
      headers: {
        ...defaultHeaders,
        ...(options.headers || {})
      }
    };

    try {
      const response = await fetch(endpoint, config);

      // Extract pod headers
      const bePod = response.headers.get('X-Backend-Pod');
      if (bePod) {
        updatePodBadge('be', bePod);
      }
      const fePod = response.headers.get('X-Frontend-Pod');
      if (fePod) {
        updatePodBadge('fe', fePod);
      }

      if (response.status === 204) {
        setConnectionStatus(true);
        return null;
      }

      if (!response.ok) {
        let errorDetail = `HTTP ${response.status} ${response.statusText}`;
        try {
          const errorJson = await response.json();
          if (errorJson.message) {
            errorDetail = errorJson.message;
          } else if (errorJson.error) {
            errorDetail = errorJson.error;
          }
        } catch {
          // Response body was not JSON, fallback to status text
        }
        const error = new Error(errorDetail);
        error.status = response.status;
        throw error;
      }

      setConnectionStatus(true);
      return await response.json();
    } catch (err) {
      if (err.name === 'TypeError' || err.message.includes('fetch')) {
        setConnectionStatus(false);
      }
      throw err;
    }
  }

  // =========================================================================
  // UI Rendering & Counter Management
  // =========================================================================

  function updateCounters() {
    totalCountEl.textContent = totalCount.toLocaleString();
    completedCountEl.textContent = completedCount.toLocaleString();
    pendingCountEl.textContent = activeCount.toLocaleString();

    filterAllCountEl.textContent = totalCount.toLocaleString();
    filterActiveCountEl.textContent = activeCount.toLocaleString();
    filterCompletedCountEl.textContent = completedCount.toLocaleString();
  }

  function updatePaginationUI() {
    if (!paginationBar) return;
    if (totalElements === 0) {
      paginationBar.classList.add('hidden');
      return;
    }
    paginationBar.classList.remove('hidden');

    const startIdx = totalElements > 0 ? currentPage * pageSize + 1 : 0;
    const endIdx = Math.min((currentPage + 1) * pageSize, totalElements);

    if (pageStartEl) pageStartEl.textContent = startIdx.toLocaleString();
    if (pageEndEl) pageEndEl.textContent = endIdx.toLocaleString();
    if (pageTotalEl) pageTotalEl.textContent = totalElements.toLocaleString();

    if (currentPageNumEl) currentPageNumEl.textContent = (currentPage + 1).toLocaleString();
    if (totalPagesNumEl) totalPagesNumEl.textContent = Math.max(1, totalPages).toLocaleString();

    if (firstPageBtn) firstPageBtn.disabled = currentPage <= 0;
    if (prevPageBtn) prevPageBtn.disabled = currentPage <= 0;
    if (nextPageBtn) nextPageBtn.disabled = currentPage >= totalPages - 1;
    if (lastPageBtn) lastPageBtn.disabled = currentPage >= totalPages - 1;
  }

  function renderTasks() {
    taskListEl.innerHTML = '';

    if (totalElements === 0) {
      if (currentFilter === 'active') {
        emptyTitle.textContent = 'No active tasks';
        emptyDesc.textContent = 'All tasks are marked as completed! Nice work!';
      } else if (currentFilter === 'completed') {
        emptyTitle.textContent = 'No completed tasks';
        emptyDesc.textContent = 'Finish tasks and mark them complete to view them here.';
      } else {
        emptyTitle.textContent = 'No tasks found';
        emptyDesc.textContent = 'Get started by creating your first task using the form above.';
      }
      emptyState.classList.remove('hidden');
      updatePaginationUI();
      return;
    }

    emptyState.classList.add('hidden');

    tasks.forEach(task => {
      const li = createTaskElement(task);
      taskListEl.appendChild(li);
    });

    updatePaginationUI();
  }

  function createTaskElement(task) {
    const li = document.createElement('li');
    li.className = `task-item ${task.completed ? 'completed' : ''}`;
    li.dataset.id = task.id;

    // Toggle button / checkbox
    const toggleBtn = document.createElement('button');
    toggleBtn.type = 'button';
    toggleBtn.className = 'task-toggle-btn';
    toggleBtn.title = task.completed ? 'Mark as incomplete' : 'Mark as complete';
    toggleBtn.setAttribute('aria-label', toggleBtn.title);

    const visualCheckbox = document.createElement('div');
    visualCheckbox.className = 'checkbox-visual';
    if (task.completed) {
      visualCheckbox.innerHTML = `
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
          <polyline points="20 6 9 17 4 12"></polyline>
        </svg>
      `;
    }
    toggleBtn.appendChild(visualCheckbox);

    toggleBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      toggleTask(task.id, Boolean(task.completed), task.title, task.description);
    });

    // Task content wrapper
    const contentDiv = document.createElement('div');
    contentDiv.className = 'task-content';

    const headerDiv = document.createElement('div');
    headerDiv.className = 'task-header';

    const titleEl = document.createElement('span');
    titleEl.className = 'task-title';
    titleEl.textContent = task.title;

    headerDiv.appendChild(titleEl);

    // Optional description
    if (task.description && task.description.trim()) {
      const descEl = document.createElement('p');
      descEl.className = 'task-desc';
      descEl.textContent = task.description;
      headerDiv.appendChild(descEl);
    }

    // Task metadata
    const metaDiv = document.createElement('div');
    metaDiv.className = 'task-meta';

    const idBadge = document.createElement('span');
    idBadge.className = 'badge badge-id';
    idBadge.textContent = `#${task.id}`;

    const dateSpan = document.createElement('span');
    dateSpan.className = 'task-date';
    dateSpan.textContent = formatDate(task.createdAt);

    metaDiv.appendChild(idBadge);
    metaDiv.appendChild(dateSpan);

    contentDiv.appendChild(headerDiv);
    contentDiv.appendChild(metaDiv);

    // Actions (Delete button)
    const actionsDiv = document.createElement('div');
    actionsDiv.className = 'task-actions';

    const deleteBtn = document.createElement('button');
    deleteBtn.type = 'button';
    deleteBtn.className = 'btn-delete';
    deleteBtn.title = 'Delete task';
    deleteBtn.setAttribute('aria-label', `Delete task ${task.title}`);
    deleteBtn.innerHTML = `
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <polyline points="3 6 5 6 21 6"></polyline>
        <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
        <line x1="10" y1="11" x2="10" y2="17"></line>
        <line x1="14" y1="11" x2="14" y2="17"></line>
      </svg>
    `;

    deleteBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      deleteTask(task.id);
    });

    actionsDiv.appendChild(deleteBtn);

    li.appendChild(toggleBtn);
    li.appendChild(contentDiv);
    li.appendChild(actionsDiv);

    return li;
  }

  // =========================================================================
  // Task Operations (CRUD with Pagination)
  // =========================================================================

  async function loadTasks(page = currentPage) {
    loadingSpinner.classList.remove('hidden');
    emptyState.classList.add('hidden');
    refreshIcon.classList.add('rotating');
    refreshBtn.disabled = true;

    try {
      currentPage = Math.max(0, page);
      const url = `${API_BASE}?page=${currentPage}&size=${pageSize}&filter=${currentFilter}`;
      const data = await apiFetch(url, { method: 'GET' });

      if (data && Array.isArray(data.content)) {
        tasks = data.content;
        currentPage = data.page;
        totalPages = data.totalPages;
        totalElements = data.totalElements;
        totalCount = data.totalCount;
        activeCount = data.activeCount;
        completedCount = data.completedCount;
      } else if (Array.isArray(data)) {
        tasks = data;
        currentPage = 0;
        totalPages = 1;
        totalElements = data.length;
        totalCount = data.length;
        completedCount = data.filter(t => Boolean(t.completed)).length;
        activeCount = totalCount - completedCount;
      } else {
        tasks = [];
        totalElements = 0;
      }

      updateCounters();
      renderTasks();
    } catch (err) {
      console.error('Error loading tasks:', err);
      showToast(`Failed to load tasks: ${err.message}. Is the backend pod running?`, 'error', 6000);
      emptyTitle.textContent = 'Backend connection error';
      emptyDesc.textContent = 'Unable to fetch tasks from /api/tasks. Check Kubernetes Ingress and backend pod status.';
      emptyState.classList.remove('hidden');
      if (paginationBar) paginationBar.classList.add('hidden');
    } finally {
      loadingSpinner.classList.add('hidden');
      refreshIcon.classList.remove('rotating');
      refreshBtn.disabled = false;
    }
  }

  async function createTask(title, description) {
    if (isSubmitting) return;

    const trimmedTitle = title.trim();
    if (!trimmedTitle) {
      showToast('Task title cannot be empty or just whitespace.', 'error');
      taskTitleInput.focus();
      return;
    }

    isSubmitting = true;
    addTaskBtn.disabled = true;
    const originalBtnHtml = addTaskBtn.innerHTML;
    addTaskBtn.innerHTML = `
      <div class="spinner" style="width:16px;height:16px;border-width:2px;margin:0;" aria-hidden="true"></div>
      <span>Adding...</span>
    `;

    try {
      const payload = {
        title: trimmedTitle,
        description: description ? description.trim() : ''
      };

      await apiFetch(API_BASE, {
        method: 'POST',
        body: JSON.stringify(payload)
      });

      // Reset form
      taskForm.reset();
      taskTitleInput.focus();
      showToast('Task created successfully!', 'success');

      // Refresh to first page to show the newly created task at the top
      currentPage = 0;
      await loadTasks(0);
    } catch (err) {
      console.error('Error creating task:', err);
      showToast(`Failed to create task: ${err.message}`, 'error');
    } finally {
      isSubmitting = false;
      addTaskBtn.disabled = false;
      addTaskBtn.innerHTML = originalBtnHtml;
    }
  }

  async function toggleTask(id, currentCompleted, title, description) {
    const taskIndex = tasks.findIndex(t => t.id === id);
    if (taskIndex === -1) return;

    const newCompleted = !currentCompleted;

    // Optimistically update
    tasks[taskIndex].completed = newCompleted;
    if (newCompleted) {
      activeCount = Math.max(0, activeCount - 1);
      completedCount++;
    } else {
      activeCount++;
      completedCount = Math.max(0, completedCount - 1);
    }
    updateCounters();
    renderTasks();

    try {
      const payload = {
        title: title || tasks[taskIndex].title,
        description: description || tasks[taskIndex].description || '',
        completed: newCompleted
      };

      await apiFetch(`${API_BASE}/${id}`, {
        method: 'PUT',
        body: JSON.stringify(payload)
      });

      // If active filter is set to active/completed, refresh list to properly remove item from view
      if (currentFilter !== 'all') {
        loadTasks(currentPage);
      }
    } catch (err) {
      console.error('Error updating task:', err);
      // Revert optimistic update
      tasks[taskIndex].completed = currentCompleted;
      loadTasks(currentPage);
      showToast(`Failed to update task: ${err.message}`, 'error');
    }
  }

  async function deleteTask(id) {
    try {
      await apiFetch(`${API_BASE}/${id}`, {
        method: 'DELETE'
      });
      showToast('Task deleted successfully.', 'info', 2500);

      // Check if we just deleted the last item on the page
      if (tasks.length === 1 && currentPage > 0) {
        currentPage--;
      }
      loadTasks(currentPage);
    } catch (err) {
      console.error('Error deleting task:', err);
      if (err.status === 404) {
        showToast('Task was already deleted.', 'info');
        loadTasks(currentPage);
      } else {
        showToast(`Failed to delete task: ${err.message}`, 'error');
      }
    }
  }

  // =========================================================================
  // Event Listeners Initialization
  // =========================================================================

  function initEventListeners() {
    // Form submission
    taskForm.addEventListener('submit', (e) => {
      e.preventDefault();
      createTask(taskTitleInput.value, taskDescInput.value);
    });

    // Form clear button
    clearFormBtn.addEventListener('click', () => {
      taskForm.reset();
      taskTitleInput.focus();
    });

    // Toast close
    toastCloseBtn.addEventListener('click', hideToast);

    // Refresh button
    refreshBtn.addEventListener('click', () => {
      loadTasks(currentPage);
    });

    // Filter tabs
    filterButtons.forEach(btn => {
      btn.addEventListener('click', () => {
        const filter = btn.dataset.filter;
        if (filter === currentFilter) return;

        filterButtons.forEach(b => {
          b.classList.remove('active');
          b.setAttribute('aria-selected', 'false');
        });
        btn.classList.add('active');
        btn.setAttribute('aria-selected', 'true');
        currentFilter = filter;
        currentPage = 0;
        loadTasks(0);
      });
    });

    // Pagination Controls
    if (firstPageBtn) {
      firstPageBtn.addEventListener('click', () => {
        if (currentPage > 0) loadTasks(0);
      });
    }

    if (prevPageBtn) {
      prevPageBtn.addEventListener('click', () => {
        if (currentPage > 0) loadTasks(currentPage - 1);
      });
    }

    if (nextPageBtn) {
      nextPageBtn.addEventListener('click', () => {
        if (currentPage < totalPages - 1) loadTasks(currentPage + 1);
      });
    }

    if (lastPageBtn) {
      lastPageBtn.addEventListener('click', () => {
        if (currentPage < totalPages - 1) loadTasks(totalPages - 1);
      });
    }

    if (pageSizeSelect) {
      pageSizeSelect.addEventListener('change', (e) => {
        pageSize = parseInt(e.target.value, 10) || 20;
        currentPage = 0;
        loadTasks(0);
      });
    }
  }

  // =========================================================================
  // Pod Identification Utilities
  // =========================================================================

  function updatePodBadge(type, podName) {
    const el = document.getElementById(`${type}-pod-name`);
    if (!el || !podName) return;
    const badge = el.closest('.pod-badge');
    if (el.textContent !== podName) {
      el.textContent = podName;
      if (badge) {
        badge.classList.add('updated');
        setTimeout(() => badge.classList.remove('updated'), 600);
      }
    }
  }

  async function detectFrontendPod() {
    try {
      const resp = await fetch('/', { method: 'HEAD', cache: 'no-store' });
      const fePod = resp.headers.get('X-Frontend-Pod');
      if (fePod) {
        updatePodBadge('fe', fePod);
      }
    } catch (err) {
      console.warn('Could not query frontend pod header:', err);
    }
  }

  // Initial load
  document.addEventListener('DOMContentLoaded', () => {
    initEventListeners();
    detectFrontendPod();
    loadTasks(0);
  });
})();
