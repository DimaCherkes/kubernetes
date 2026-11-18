package com.example.fullstackapp.service;

import co.elastic.clients.elasticsearch._types.ElasticsearchException;
import co.elastic.clients.elasticsearch._types.SortOptions;
import co.elastic.clients.elasticsearch._types.SortOrder;
import co.elastic.clients.elasticsearch._types.mapping.FieldType;
import co.elastic.clients.elasticsearch._types.query_dsl.Query;
import co.elastic.clients.elasticsearch._types.query_dsl.QueryBuilders;
import com.example.fullstackapp.dto.ReindexResponse;
import com.example.fullstackapp.dto.TaskSearchItem;
import com.example.fullstackapp.dto.TaskSearchResponse;
import com.example.fullstackapp.exception.ElasticsearchUnavailableException;
import com.example.fullstackapp.model.Task;
import com.example.fullstackapp.model.TaskDocument;
import com.example.fullstackapp.repository.TaskRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.elasticsearch.NoSuchIndexException;
import org.springframework.data.elasticsearch.client.elc.NativeQuery;
import org.springframework.data.elasticsearch.client.elc.NativeQueryBuilder;
import org.springframework.data.elasticsearch.core.ElasticsearchOperations;
import org.springframework.data.elasticsearch.core.IndexOperations;
import org.springframework.data.elasticsearch.core.RefreshPolicy;
import org.springframework.data.elasticsearch.core.SearchHit;
import org.springframework.data.elasticsearch.core.SearchHits;
import org.springframework.data.elasticsearch.core.mapping.IndexCoordinates;
import org.springframework.data.elasticsearch.core.query.DeleteQuery;
import org.springframework.data.elasticsearch.core.query.HighlightQuery;
import org.springframework.data.elasticsearch.core.query.IndexQuery;
import org.springframework.data.elasticsearch.core.query.IndexQueryBuilder;
import org.springframework.data.elasticsearch.core.query.highlight.Highlight;
import org.springframework.data.elasticsearch.core.query.highlight.HighlightField;
import org.springframework.data.elasticsearch.core.query.highlight.HighlightParameters;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Locale;
import java.util.concurrent.atomic.AtomicBoolean;

@Service
public class TaskSearchService {

    private static final Logger log = LoggerFactory.getLogger(TaskSearchService.class);
    private static final IndexCoordinates TASKS_INDEX = IndexCoordinates.of("tasks");
    private static final int REINDEX_BATCH_SIZE = 500;
    private static final String SOURCE_ELASTICSEARCH = "elasticsearch";
    private static final String SOURCE_POSTGRES_FALLBACK = "postgresql-fallback";

    private final ElasticsearchOperations elasticsearchOperations;
    private final TaskRepository taskRepository;
    private final AtomicBoolean indexInitialized = new AtomicBoolean(false);

    public TaskSearchService(ElasticsearchOperations elasticsearchOperations, TaskRepository taskRepository) {
        this.elasticsearchOperations = elasticsearchOperations;
        this.taskRepository = taskRepository;
    }

    private void ensureIndexExists() {
        IndexOperations indexOps = elasticsearchOperations.indexOps(TaskDocument.class);
        if (!indexOps.exists()) {
            try {
                indexOps.createWithMapping();
            } catch (Exception ex) {
                if (!indexOps.exists()) {
                    throw ex;
                }
            }
        }
        indexInitialized.set(true);
    }

    public void indexTask(Task task) {
        if (task == null || task.getId() == null) {
            return;
        }
        TaskDocument document = TaskDocument.fromEntity(task);
        try {
            if (!indexInitialized.get()) {
                ensureIndexExists();
            }
            elasticsearchOperations.withRefreshPolicy(RefreshPolicy.IMMEDIATE).save(document);
        } catch (Exception ex) {
            indexInitialized.set(false);
            if (isIndexNotFound(ex)) {
                try {
                    ensureIndexExists();
                    elasticsearchOperations.withRefreshPolicy(RefreshPolicy.IMMEDIATE).save(document);
                    return;
                } catch (Exception retryEx) {
                    log.warn("Failed to sync task {} to Elasticsearch after index recreation (PostgreSQL write succeeded): {}",
                            task.getId(), retryEx.getMessage());
                    return;
                }
            }
            log.warn("Failed to sync task {} to Elasticsearch (PostgreSQL write succeeded): {}",
                    task.getId(), ex.getMessage());
        }
    }

    public void deleteTask(Long id) {
        if (id == null) {
            return;
        }
        try {
            if (!indexInitialized.get() && !elasticsearchOperations.indexOps(TaskDocument.class).exists()) {
                return;
            }
            indexInitialized.set(true);
            elasticsearchOperations.withRefreshPolicy(RefreshPolicy.IMMEDIATE)
                    .delete(String.valueOf(id), TaskDocument.class);
        } catch (Exception ex) {
            if (isIndexNotFound(ex)) {
                indexInitialized.set(false);
                log.debug("Tasks index not found when deleting task {} from Elasticsearch; ignoring", id);
                return;
            }
            log.warn("Failed to delete task {} from Elasticsearch (PostgreSQL delete succeeded): {}",
                    id, ex.getMessage());
        }
    }

    @EventListener(ApplicationReadyEvent.class)
    public void reindexOnStartup() {
        try {
            long count = reindexInternal(false);
            log.info("Startup Elasticsearch reindex completed: {} task(s)", count);
        } catch (Exception ex) {
            indexInitialized.set(false);
            log.warn("Elasticsearch unavailable during startup reindex; continuing startup: {}", ex.getMessage());
        }
    }

    public ReindexResponse reindexAllTasks() {
        try {
            long indexedCount = reindexInternal(true);
            return new ReindexResponse(indexedCount, "ok");
        } catch (Exception ex) {
            indexInitialized.set(false);
            throw new ElasticsearchUnavailableException(
                    "Elasticsearch is unavailable; reindex failed: " + ex.getMessage(), ex);
        }
    }

    private long reindexInternal(boolean clearExisting) {
        ensureIndexExists();
        if (clearExisting) {
            DeleteQuery deleteAllQuery = DeleteQuery.builder(
                    NativeQuery.builder().withQuery(q -> q.matchAll(m -> m)).build()
            ).build();
            elasticsearchOperations.delete(deleteAllQuery, TaskDocument.class);
        }

        long totalIndexed = 0;
        int page = 0;
        Page<Task> taskPage;
        do {
            taskPage = taskRepository.findAll(PageRequest.of(page, REINDEX_BATCH_SIZE, Sort.by("id")));
            if (!taskPage.isEmpty()) {
                List<IndexQuery> queries = taskPage.getContent().stream()
                        .map(task -> new IndexQueryBuilder()
                                .withId(String.valueOf(task.getId()))
                                .withObject(TaskDocument.fromEntity(task))
                                .build())
                        .toList();
                elasticsearchOperations.bulkIndex(queries, TASKS_INDEX);
                totalIndexed += queries.size();
            }
            page++;
        } while (taskPage.hasNext());

        elasticsearchOperations.indexOps(TaskDocument.class).refresh();
        return totalIndexed;
    }

    public TaskSearchResponse searchTasks(String q, String status, int page, int size) {
        String trimmedQuery = q == null ? "" : q.trim();
        Boolean completedFilter = parseCompletedFilter(status);
        int validatedPage = Math.max(0, page);
        int validatedSize = Math.min(Math.max(1, size), 100);

        long totalCount = taskRepository.count();
        long completedCount = taskRepository.countByCompleted(true);
        long activeCount = Math.max(0, totalCount - completedCount);

        SearchHits<TaskDocument> searchHits = null;
        boolean esSucceeded = false;
        try {
            searchHits = executeElasticsearchSearch(trimmedQuery, completedFilter, validatedPage, validatedSize);
            esSucceeded = true;
        } catch (RuntimeException ex) {
            if (isIndexNotFound(ex)) {
                indexInitialized.set(false);
            }
            log.warn("Elasticsearch search failed (q='{}', status='{}'); falling back to PostgreSQL: {}",
                    trimmedQuery, status, ex.getMessage());
        }

        if (esSucceeded) {
            List<TaskSearchItem> content = searchHits.getSearchHits().stream()
                    .map(this::toSearchItem)
                    .toList();
            long totalElements = searchHits.getTotalHits();
            int totalPages = totalElements == 0 ? 0 : (int) ((totalElements + validatedSize - 1) / validatedSize);
            boolean first = validatedPage == 0;
            boolean last = validatedPage >= totalPages - 1;

            return new TaskSearchResponse(
                    content,
                    validatedPage,
                    validatedSize,
                    totalElements,
                    totalPages,
                    first,
                    last,
                    totalCount,
                    activeCount,
                    completedCount,
                    SOURCE_ELASTICSEARCH
            );
        }

        return searchPostgresFallback(
                trimmedQuery, completedFilter, validatedPage, validatedSize,
                totalCount, activeCount, completedCount
        );
    }

    private SearchHits<TaskDocument> executeElasticsearchSearch(
            String trimmedQuery, Boolean completedFilter, int page, int size) {
        boolean hasQuery = !trimmedQuery.isEmpty();

        Query coreQuery = hasQuery
                ? QueryBuilders.multiMatch(m -> m
                        .query(trimmedQuery)
                        .fields("title^2", "description")
                        .fuzziness("AUTO"))
                : QueryBuilders.matchAll(ma -> ma);

        Query finalQuery = (completedFilter != null)
                ? QueryBuilders.bool(b -> b
                        .must(coreQuery)
                        .filter(f -> f.term(t -> t.field("completed").value(completedFilter.booleanValue()))))
                : coreQuery;

        NativeQueryBuilder queryBuilder = NativeQuery.builder()
                .withQuery(finalQuery)
                .withPageable(PageRequest.of(page, size))
                .withTrackTotalHits(true);

        if (hasQuery) {
            HighlightParameters highlightParameters = HighlightParameters.builder()
                    .withPreTags("<mark>")
                    .withPostTags("</mark>")
                    .withNumberOfFragments(0)
                    .build();
            Highlight highlight = new Highlight(highlightParameters, List.of(
                    new HighlightField("title"),
                    new HighlightField("description")
            ));
            queryBuilder.withHighlightQuery(new HighlightQuery(highlight, TaskDocument.class));
            queryBuilder.withSort(
                    SortOptions.of(s -> s.score(sc -> sc.order(SortOrder.Desc))),
                    SortOptions.of(s -> s.field(f -> f
                            .field("createdAt")
                            .order(SortOrder.Desc)
                            .unmappedType(FieldType.Date)))
            );
        } else {
            queryBuilder.withSort(
                    SortOptions.of(s -> s.field(f -> f
                            .field("createdAt")
                            .order(SortOrder.Desc)
                            .unmappedType(FieldType.Date)))
            );
        }

        return elasticsearchOperations.search(queryBuilder.build(), TaskDocument.class);
    }

    private TaskSearchResponse searchPostgresFallback(
            String trimmedQuery, Boolean completedFilter, int page, int size,
            long totalCount, long activeCount, long completedCount) {
        Pageable pageable = PageRequest.of(page, size, Sort.by(Sort.Direction.DESC, "createdAt", "id"));
        Page<Task> taskPage;

        if (trimmedQuery.isEmpty()) {
            if (completedFilter != null) {
                taskPage = taskRepository.findByCompleted(completedFilter, pageable);
            } else {
                taskPage = taskRepository.findAll(pageable);
            }
        } else {
            String escaped = trimmedQuery.toLowerCase(Locale.ROOT)
                    .replace("!", "!!")
                    .replace("%", "!%")
                    .replace("_", "!_");
            String pattern = "%" + escaped + "%";
            if (completedFilter != null) {
                taskPage = taskRepository.searchByCompleted(pattern, completedFilter, pageable);
            } else {
                taskPage = taskRepository.searchAll(pattern, pageable);
            }
        }

        List<TaskSearchItem> content = taskPage.getContent().stream()
                .map(task -> {
                    String description = task.getDescription() != null ? task.getDescription() : "";
                    return new TaskSearchItem(
                            task.getId(),
                            task.getTitle(),
                            description,
                            task.isCompleted(),
                            task.getCreatedAt(),
                            task.getTitle(),
                            description
                    );
                })
                .toList();

        return new TaskSearchResponse(
                content,
                taskPage.getNumber(),
                taskPage.getSize(),
                taskPage.getTotalElements(),
                taskPage.getTotalPages(),
                taskPage.isFirst(),
                taskPage.isLast(),
                totalCount,
                activeCount,
                completedCount,
                SOURCE_POSTGRES_FALLBACK
        );
    }

    private TaskSearchItem toSearchItem(SearchHit<TaskDocument> hit) {
        TaskDocument doc = hit.getContent();
        String rawId = doc.getId() != null ? doc.getId() : hit.getId();
        Long taskId = rawId != null ? Long.valueOf(rawId) : null;
        String description = doc.getDescription() != null ? doc.getDescription() : "";
        String highlightedTitle = firstHighlightOrFallback(hit.getHighlightField("title"), doc.getTitle());
        String highlightedDescription = firstHighlightOrFallback(hit.getHighlightField("description"), description);

        return new TaskSearchItem(
                taskId,
                doc.getTitle(),
                description,
                doc.isCompleted(),
                doc.getCreatedAt(),
                highlightedTitle,
                highlightedDescription
        );
    }

    private static String firstHighlightOrFallback(List<String> highlights, String fallback) {
        if (highlights != null && !highlights.isEmpty()) {
            return highlights.get(0);
        }
        return fallback;
    }

    private static Boolean parseCompletedFilter(String status) {
        if ("active".equalsIgnoreCase(status)) {
            return Boolean.FALSE;
        }
        if ("completed".equalsIgnoreCase(status)) {
            return Boolean.TRUE;
        }
        return null;
    }

    private static boolean isIndexNotFound(Throwable ex) {
        Throwable current = ex;
        while (current != null) {
            if (current instanceof NoSuchIndexException) {
                return true;
            }
            if (current instanceof ElasticsearchException esEx
                    && esEx.response() != null
                    && esEx.response().error() != null
                    && "index_not_found_exception".equals(esEx.response().error().type())) {
                return true;
            }
            String message = current.getMessage();
            if (message != null && (message.contains("index_not_found_exception")
                    || message.contains("IndexNotFoundException"))) {
                return true;
            }
            current = current.getCause();
        }
        return false;
    }
}
