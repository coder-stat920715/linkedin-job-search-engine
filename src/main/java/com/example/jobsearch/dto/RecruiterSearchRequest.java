package com.example.jobsearch.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.util.List;

public record RecruiterSearchRequest(
        @Schema(example = "\"JPMorgan\" AND (\"Talent Acquisition\" OR \"Recruiter\") AND \"Java\" AND \"Immediate Joiner\"")
        @NotBlank @Size(max = 2000) String query,
        List<@NotBlank String> requiredSkills,
        String location,
        Boolean openToWorkOnly,
        @Min(0) Integer maxNoticePeriodDays,
        @Min(1) @Max(100) Integer pageSize,
        Long recruiterId) {

    public int effectivePageSize() {
        return pageSize == null ? 20 : pageSize;
    }

    public List<String> skillsOrEmpty() {
        return requiredSkills == null ? List.of() : requiredSkills;
    }
}
