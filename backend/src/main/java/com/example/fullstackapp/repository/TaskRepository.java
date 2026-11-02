package com.example.fullstackapp.repository;

import com.example.fullstackapp.model.Task;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface TaskRepository extends JpaRepository<Task, Long> {
    List<Task> findAllByOrderByCreatedAtDesc();

    Page<Task> findByCompleted(boolean completed, Pageable pageable);

    long countByCompleted(boolean completed);
}
