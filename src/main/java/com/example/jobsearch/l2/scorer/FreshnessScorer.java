package com.example.jobsearch.l2.scorer;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.CandidateFeatureSet;
import com.example.jobsearch.l2.CandidateScorer;
import com.example.jobsearch.l2.ScoringContext;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;

/**
 * Freshness = 0.4 * 2^(-daysSinceProfileUpdate/90) + 0.3 * 2^(-daysSinceLastActive/14) + 0.3 * min(1, sessionActivity/10)
 */
@Component
@RequiredArgsConstructor
public class FreshnessScorer implements CandidateScorer {

    private final SearchProperties properties;

    @Override
    public String name() {
        return "freshness";
    }

    @Override
    public double weight() {
        return properties.getWeights().getFreshness();
    }

    @Override
    public double score(Candidate candidate, CandidateFeatureSet f, ScoringContext context) {
        double profile = halfLifeDecay(candidate.getProfileUpdatedAt(), context.now(), 90.0);
        double active = halfLifeDecay(candidate.getLastActiveAt(), context.now(), 14.0);
        double sessions = Math.min(1.0, f.getSessionActivity() / 10.0);
        return 0.4 * profile + 0.3 * active + 0.3 * sessions;
    }

    private double halfLifeDecay(Instant then, Instant now, double halfLifeDays) {
        if (then == null) {
            return 0.0;
        }
        double days = Math.max(0.0, Duration.between(then, now).toMinutes() / 1440.0);
        return Math.pow(2.0, -days / halfLifeDays);
    }
}
