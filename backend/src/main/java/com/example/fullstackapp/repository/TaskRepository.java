package com.example.fullstackapp.repository;

import com.example.fullstackapp.model.Task;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface TaskRepository extends JpaRepository<Task, Long> {
    List<Task> findAllByOrderByCreatedAtDesc();

    Page<Task> findByCompleted(boolean completed, Pageable pageable);

    long countByCompleted(boolean completed);

    @Query("""
        SELECT t FROM Task t
        WHERE LOWER(t.title) LIKE :pattern ESCAPE '!'
           OR LOWER(COALESCE(t.description, '')) LIKE :pattern ESCAPE '!'
        """)
    Page<Task> searchAll(@Param("pattern") String pattern, Pageable pageable);

    @Query("""
        SELECT t FROM Task t
        WHERE t.completed = :completed
          AND (LOWER(t.title) LIKE :pattern ESCAPE '!'
               OR LOWER(COALESCE(t.description, '')) LIKE :pattern ESCAPE '!')
        """)
    Page<Task> searchByCompleted(@Param("pattern") String pattern,
                                 @Param("completed") boolean completed,
                                 Pageable pageable);
}
