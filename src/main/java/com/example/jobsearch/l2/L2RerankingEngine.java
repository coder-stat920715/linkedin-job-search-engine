package com.example.jobsearch.l2;

import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.CandidateFeatureSet;
import com.example.jobsearch.service.FeatureStoreService;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;

/** Score = sum(w_i * s_i) / sum(w_i), so the final score stays in [0, 1]. Candidates are scored in parallel. */
@Slf4j
@Service
public class L2RerankingEngine {

    private final List<CandidateScorer> scorers;
    private final FeatureStoreService featureStore;
    private final ExecutorService executor;

    public L2RerankingEngine(List<CandidateScorer> scorers,
                             FeatureStoreService featureStore,
                             @Qualifier("scoringExecutor") ExecutorService executor) {
        this.scorers = scorers;
        this.featureStore = featureStore;
        this.executor = executor;
    }

    public List<ScoredCandidate> rerank(List<Candidate> candidates, ScoringContext context) {
        if (candidates.isEmpty()) {
            return List.of();
        }
        double totalWeight = scorers.stream().mapToDouble(CandidateScorer::weight).sum();
        if (totalWeight <= 0) {
            throw new IllegalStateException("Sum of scorer weights must be positive");
        }
        Map<Long, CandidateFeatureSet> features =
                featureStore.getBatch(candidates.stream().map(Candidate::getId).toList());
        Map<String, String> mdc = MDC.getCopyOfContextMap();

        List<CompletableFuture<ScoredCandidate>> futures = candidates.stream()
                .map(c -> CompletableFuture.supplyAsync(() -> scoreOne(c,
                        features.getOrDefault(c.getId(), CandidateFeatureSet.empty(c.getId())),
                        context, totalWeight, mdc), executor))
                .toList();

        List<ScoredCandidate> ranked = futures.stream()
                .map(CompletableFuture::join)
                .sorted(Comparator.comparingDouble(ScoredCandidate::score).reversed()
                        .thenComparing(s -> s.candidate().getId()))
                .toList();
        log.debug("L2 reranked {} candidates using {} scorers", ranked.size(), scorers.size());
        return ranked;
    }

    private ScoredCandidate scoreOne(Candidate c, CandidateFeatureSet f, ScoringContext ctx,
                                     double totalWeight, Map<String, String> mdc) {
        if (mdc != null) {
            MDC.setContextMap(mdc);
        }
        try {
            Map<String, Double> breakdown = new LinkedHashMap<>();
            double weighted = 0.0;
            for (CandidateScorer scorer : scorers) {
                double s = Math.max(0.0, Math.min(1.0, scorer.score(c, f, ctx)));
                breakdown.put(scorer.name(), s);
                weighted += scorer.weight() * s;
            }
            return new ScoredCandidate(c, weighted / totalWeight, breakdown);
        } finally {
            MDC.clear();
        }
    }
}
