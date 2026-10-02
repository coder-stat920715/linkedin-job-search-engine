package com.example.jobsearch.controller;

import com.example.jobsearch.domain.JobPosting;
import com.example.jobsearch.dto.JobPostingRequest;
import com.example.jobsearch.dto.RecruiterSearchRequest;
import com.example.jobsearch.dto.SearchResponse;
import com.example.jobsearch.pipeline.RecruiterSearchPipeline;
import com.example.jobsearch.service.JobPostingService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1")
@RequiredArgsConstructor
@Tag(name = "Search", description = "Recruiter candidate search and job matching")
public class JobSearchController {

    private final RecruiterSearchPipeline pipeline;
    private final JobPostingService jobPostingService;

    @Operation(summary = "Recruiter Boolean candidate search (L1 retrieval + L2 reranking)")
    @PostMapping("/search/candidates")
    public SearchResponse searchCandidates(@Valid @RequestBody RecruiterSearchRequest request) {
        return pipeline.execute(request);
    }

    @Operation(summary = "Create a job posting")
    @PostMapping("/jobs")
    @ResponseStatus(HttpStatus.CREATED)
    public JobPosting createJob(@Valid @RequestBody JobPostingRequest request) {
        return jobPostingService.create(request);
    }

    @Operation(summary = "Get a job posting")
    @GetMapping("/jobs/{id}")
    public JobPosting getJob(@PathVariable Long id) {
        return jobPostingService.get(id);
    }

    @Operation(summary = "Rank candidates that match a job posting")
    @GetMapping("/jobs/{id}/matches")
    public SearchResponse matches(@PathVariable Long id, @RequestParam(defaultValue = "20") int size) {
        return jobPostingService.matchCandidates(id, Math.max(1, Math.min(size, 100)));
    }
}
