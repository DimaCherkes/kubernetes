package com.example.fullstackapp.dto;

import jakarta.validation.constraints.Size;

public record TaskUpdateRequest(
    @Size(max = 255, message = "Title must not exceed 255 characters")
    String title,

    String description,
    Boolean completed
) {}
