package com.example.jobsearch.controller;

import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.dto.CandidateUpsertRequest;
import com.example.jobsearch.l1.L1CandidateRetrievalService;
import com.example.jobsearch.service.ProfileIngestionService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api/v1")
@RequiredArgsConstructor
@Tag(name = "Profiles", description = "Candidate profile ingestion and index administration")
public class CandidateController {

    private final ProfileIngestionService ingestionService;
    private final L1CandidateRetrievalService l1;

    @Operation(summary = "Create a candidate profile and index it")
    @PostMapping("/candidates")
    @ResponseStatus(HttpStatus.CREATED)
    public Candidate create(@Valid @RequestBody CandidateUpsertRequest request) {
        return ingestionService.create(request);
    }

    @Operation(summary = "Update a candidate profile and re-index it")
    @PutMapping("/candidates/{id}")
    public Candidate update(@PathVariable Long id, @Valid @RequestBody CandidateUpsertRequest request) {
        return ingestionService.update(id, request);
    }

    @Operation(summary = "Get a candidate profile")
    @GetMapping("/candidates/{id}")
    public Candidate get(@PathVariable Long id) {
        return ingestionService.get(id);
    }

    @Operation(summary = "Rebuild the L1 inverted index from the system of record")
    @PostMapping("/admin/index/rebuild")
    public Map<String, Integer> rebuild() {
        return Map.of("indexedCandidates", l1.rebuildIndex());
    }
}
