package com.example.jobsearch.dto;

import jakarta.validation.constraints.NotNull;

import java.time.Instant;

public record EngagementEvent(
        String eventId,
        @NotNull EngagementType type,
        @NotNull Long candidateId,
        Long recruiterId,
        String messageId,
        Instant occurredAt) {
}
