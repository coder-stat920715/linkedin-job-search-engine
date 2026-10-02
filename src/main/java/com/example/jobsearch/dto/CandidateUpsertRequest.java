package com.example.jobsearch.dto;

import jakarta.validation.constraints.NotBlank;

import java.util.Set;

public record CandidateUpsertRequest(
        @NotBlank String fullName,
        String headline,
        String currentCompany,
        String currentTitle,
        String location,
        boolean openToWork,
        boolean immediateJoiner,
        Integer noticePeriodDays,
        Set<String> skills) {
}
