package com.example.fullstackapp.dto;

import java.util.List;

public record PagedResponse<T>(
    List<T> content,
    int page,
    int size,
    long totalElements,
    int totalPages,
    boolean first,
    boolean last,
    long totalCount,
    long activeCount,
    long completedCount
) {}
