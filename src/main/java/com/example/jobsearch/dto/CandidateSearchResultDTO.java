package com.example.jobsearch.dto;

import java.util.List;
import java.util.Map;

public record CandidateSearchResultDTO(
        Long candidateId,
        String fullName,
        String headline,
        String currentCompany,
        String currentTitle,
        String location,
        boolean openToWork,
        double score,
        Map<String, Double> scoreBreakdown,
        List<String> matchedSkills) {
}
