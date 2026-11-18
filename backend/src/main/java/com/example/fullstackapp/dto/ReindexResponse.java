package com.example.fullstackapp.dto;

public record ReindexResponse(
    long indexedCount,
    String status
) {}
