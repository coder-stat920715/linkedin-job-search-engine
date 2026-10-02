package com.example.jobsearch.controller;

import com.example.jobsearch.domain.CandidateFeatureSet;
import com.example.jobsearch.dto.EngagementEvent;
import com.example.jobsearch.event.EngagementEventPublisher;
import com.example.jobsearch.service.FeatureStoreService;
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
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1")
@RequiredArgsConstructor
@Tag(name = "Engagement", description = "Engagement events feeding the L2 feature store")
public class EngagementController {

    private final EngagementEventPublisher publisher;
    private final FeatureStoreService featureStore;

    @Operation(summary = "Publish an engagement event (InMail sent/responded, session activity, profile view)")
    @PostMapping("/engagement/events")
    @ResponseStatus(HttpStatus.ACCEPTED)
    public EngagementEvent publish(@Valid @RequestBody EngagementEvent event) {
        return publisher.publish(event);
    }

    @Operation(summary = "Inspect a candidate's L2 feature set")
    @GetMapping("/candidates/{id}/features")
    public CandidateFeatureSet features(@PathVariable Long id) {
        return featureStore.get(id);
    }
}
