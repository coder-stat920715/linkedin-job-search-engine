package com.example.jobsearch.l2;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.CandidateFeatureSet;
import com.example.jobsearch.l2.scorer.FreshnessScorer;
import com.example.jobsearch.l2.scorer.InMailResponsivenessScorer;
import com.example.jobsearch.l2.scorer.OpenToWorkScorer;
import com.example.jobsearch.l2.scorer.SkillCompanionScorer;
import com.example.jobsearch.service.FeatureStoreService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class L2RerankingEngineTest {

    @Mock
    private FeatureStoreService featureStore;

    private final ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor();

    @AfterEach
    void tearDown() {
        executor.close();
    }

    @Test
    void ranksStrongResponsiveFreshCandidateFirst() {
        SearchProperties props = new SearchProperties();
        L2RerankingEngine engine = new L2RerankingEngine(List.of(
                new SkillCompanionScorer(new SkillCompanionMatrix(), props),
                new InMailResponsivenessScorer(props),
                new OpenToWorkScorer(props),
                new FreshnessScorer(props)), featureStore, executor);

        Instant now = Instant.now();
        Candidate strong = Candidate.builder().id(1L).fullName("Strong").openToWork(true).immediateJoiner(true)
                .skills(Set.of("Java", "Spring Boot")).profileUpdatedAt(now).lastActiveAt(now).build();
        Candidate weak = Candidate.builder().id(2L).fullName("Weak").openToWork(false)
                .skills(Set.of("Python")).profileUpdatedAt(now.minus(Duration.ofDays(400)))
                .lastActiveAt(now.minus(Duration.ofDays(400))).build();

        when(featureStore.getBatch(anyCollection())).thenReturn(Map.of(
                1L, CandidateFeatureSet.builder().candidateId(1L).inMailsReceived(10).inMailsResponded(9)
                        .avgResponseHours(2).sessionActivity(8).build(),
                2L, CandidateFeatureSet.builder().candidateId(2L).inMailsReceived(10).inMailsResponded(0).build()));

        List<ScoredCandidate> ranked = engine.rerank(List.of(weak, strong),
                new ScoringContext(Set.of("java", "spring boot"), now));

        assertEquals(2, ranked.size());
        assertEquals(1L, ranked.get(0).candidate().getId());
        assertTrue(ranked.get(0).score() > ranked.get(1).score());
        assertTrue(ranked.get(0).score() <= 1.0 && ranked.get(1).score() >= 0.0);
        assertEquals(4, ranked.get(0).breakdown().size());
    }
}
