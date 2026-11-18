package com.example.fullstackapp.dto;

import java.util.List;

public record TaskSearchResponse(
    List<TaskSearchItem> content,
    int page,
    int size,
    long totalElements,
    int totalPages,
    boolean first,
    boolean last,
    long totalCount,
    long activeCount,
    long completedCount,
    String searchSource
) {}
