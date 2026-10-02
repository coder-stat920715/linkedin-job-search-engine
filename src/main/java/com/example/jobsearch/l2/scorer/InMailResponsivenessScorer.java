package com.example.jobsearch.l2.scorer;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.CandidateFeatureSet;
import com.example.jobsearch.l2.CandidateScorer;
import com.example.jobsearch.l2.ScoringContext;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * Bayesian-smoothed response rate (prior 0.3, strength 5) blended with an exponential speed factor:
 * score = 0.8 * (responded + 5*0.3) / (received + 5) + 0.2 * exp(-avgResponseHours / 48)
 */
@Component
@RequiredArgsConstructor
public class InMailResponsivenessScorer implements CandidateScorer {

    private static final double PRIOR_RATE = 0.3;
    private static final double PRIOR_STRENGTH = 5.0;

    private final SearchProperties properties;

    @Override
    public String name() {
        return "inMailResponse";
    }

    @Override
    public double weight() {
        return properties.getWeights().getInMailResponse();
    }

    @Override
    public double score(Candidate candidate, CandidateFeatureSet f, ScoringContext context) {
        double rate = (f.getInMailsResponded() + PRIOR_STRENGTH * PRIOR_RATE) / (f.getInMailsReceived() + PRIOR_STRENGTH);
        double speed = f.getInMailsResponded() == 0 ? 0.5 : Math.exp(-f.getAvgResponseHours() / 48.0);
        return Math.min(1.0, 0.8 * rate + 0.2 * speed);
    }
}
