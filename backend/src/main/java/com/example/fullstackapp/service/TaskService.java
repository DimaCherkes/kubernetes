package com.example.fullstackapp.service;

import com.example.fullstackapp.dto.PagedResponse;
import com.example.fullstackapp.dto.TaskCreateRequest;
import com.example.fullstackapp.dto.TaskResponse;
import com.example.fullstackapp.dto.TaskUpdateRequest;
import com.example.fullstackapp.model.Task;
import com.example.fullstackapp.exception.ResourceNotFoundException;
import com.example.fullstackapp.repository.TaskRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional
public class TaskService {

    private static final Logger log = LoggerFactory.getLogger(TaskService.class);

    private final TaskRepository taskRepository;

    public TaskService(TaskRepository taskRepository) {
        this.taskRepository = taskRepository;
    }

    @Transactional(readOnly = true)
    public PagedResponse<TaskResponse> getTasks(int page, int size, String filter) {
        int validatedPage = Math.max(0, page);
        int validatedSize = Math.min(Math.max(1, size), 100);
        Pageable pageable = PageRequest.of(validatedPage, validatedSize, Sort.by(Sort.Direction.DESC, "createdAt", "id"));

        Page<Task> taskPage;
        if ("active".equalsIgnoreCase(filter)) {
            taskPage = taskRepository.findByCompleted(false, pageable);
        } else if ("completed".equalsIgnoreCase(filter)) {
            taskPage = taskRepository.findByCompleted(true, pageable);
        } else {
            taskPage = taskRepository.findAll(pageable);
        }

        long totalCount = taskRepository.count();
        long completedCount = taskRepository.countByCompleted(true);
        long activeCount = Math.max(0, totalCount - completedCount);

        List<TaskResponse> content = taskPage.getContent().stream()
                .map(this::toResponse)
                .toList();

        return new PagedResponse<>(
                content,
                taskPage.getNumber(),
                taskPage.getSize(),
                taskPage.getTotalElements(),
                taskPage.getTotalPages(),
                taskPage.isFirst(),
                taskPage.isLast(),
                totalCount,
                activeCount,
                completedCount
        );
    }

    @Transactional(readOnly = true)
    public List<TaskResponse> getAllTasks() {
        log.debug("Fetching all tasks from repository");
        return taskRepository.findAllByOrderByCreatedAtDesc()
                .stream()
                .map(this::toResponse)
                .toList();
    }

    @Transactional(readOnly = true)
    public TaskResponse getTaskById(Long id) {
        log.debug("Fetching task from repository with id: {}", id);
        Task task = taskRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Task not found with id: " + id));
        return toResponse(task);
    }

    public TaskResponse createTask(TaskCreateRequest request) {
        log.info("Persisting new task with title: {}", request.title());
        Task task = new Task();
        task.setTitle(request.title());
        task.setDescription(request.description() != null ? request.description() : "");
        task.setCompleted(request.completed() != null ? request.completed() : false);
        Task saved = taskRepository.save(task);
        log.info("Persisted task successfully with id: {}", saved.getId());
        return toResponse(saved);
    }

    public TaskResponse updateTask(Long id, TaskUpdateRequest request) {
        log.info("Updating task with id: {}", id);
        Task task = taskRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Task not found with id: " + id));
        if (request.title() != null && !request.title().isBlank()) {
            task.setTitle(request.title());
        }
        if (request.description() != null) {
            task.setDescription(request.description());
        }
        if (request.completed() != null) {
            task.setCompleted(request.completed());
        }
        Task updated = taskRepository.save(task);
        log.info("Updated task successfully with id: {}", updated.getId());
        return toResponse(updated);
    }

    public void deleteTask(Long id) {
        log.info("Deleting task with id: {}", id);
        if (!taskRepository.existsById(id)) {
            throw new ResourceNotFoundException("Task not found with id: " + id);
        }
        taskRepository.deleteById(id);
        log.info("Deleted task successfully with id: {}", id);
    }

    private TaskResponse toResponse(Task task) {
        return new TaskResponse(
                task.getId(),
                task.getTitle(),
                task.getDescription(),
                task.isCompleted(),
                task.getCreatedAt()
        );
    }
}
