package com.example.jobsearch.event;

import com.example.jobsearch.dto.EngagementEvent;
import com.example.jobsearch.dto.EngagementType;
import com.example.jobsearch.repository.CandidateRepository;
import com.example.jobsearch.service.FeatureStoreService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;

@Component
@RequiredArgsConstructor
public class SessionActivityObserver implements EngagementObserver {

    private final FeatureStoreService featureStore;
    private final CandidateRepository candidates;

    @Override
    public boolean supports(EngagementType type) {
        return type == EngagementType.SESSION_ACTIVITY || type == EngagementType.PROFILE_VIEWED;
    }

    @Override
    @Transactional
    public void onEvent(EngagementEvent event) {
        final double increment = event.type() == EngagementType.SESSION_ACTIVITY ? 1.0 : 0.25;
        featureStore.update(event.candidateId(), f -> f.setSessionActivity(f.getSessionActivity() + increment));
        if (event.type() == EngagementType.SESSION_ACTIVITY) {
            candidates.findById(event.candidateId()).ifPresent(c -> c.setLastActiveAt(Instant.now()));
        }
    }
}
