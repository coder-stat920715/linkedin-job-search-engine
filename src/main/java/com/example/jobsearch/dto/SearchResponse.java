package com.example.jobsearch.dto;

import java.util.List;

public record SearchResponse(
        String searchId,
        int l1Matches,
        int afterFilters,
        long tookMs,
        List<CandidateSearchResultDTO> results) {
}
