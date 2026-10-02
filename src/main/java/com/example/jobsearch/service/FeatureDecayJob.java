package com.example.jobsearch.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** Nightly exponential decay so session activity approximates a rolling 7-day window. */
@Slf4j
@Component
@RequiredArgsConstructor
public class FeatureDecayJob {

    private final FeatureStoreService featureStore;

    @Scheduled(cron = "0 0 3 * * *")
    public void decay() {
        int rows = featureStore.decaySessions(6.0 / 7.0);
        log.info("Decayed session activity for {} candidates", rows);
    }
}
