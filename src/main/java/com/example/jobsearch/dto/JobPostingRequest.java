package com.example.jobsearch.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;

import java.util.Set;

public record JobPostingRequest(
        @NotBlank String title,
        @NotBlank String company,
        String location,
        String description,
        Integer minExperienceYears,
        Long recruiterId,
        @NotEmpty Set<@NotBlank String> requiredSkills) {
}
