package com.example.jobsearch.l2;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.CandidateFeatureSet;
import com.example.jobsearch.l2.scorer.FreshnessScorer;
import com.example.jobsearch.l2.scorer.InMailResponsivenessScorer;
import com.example.jobsearch.l2.scorer.OpenToWorkScorer;
import com.example.jobsearch.l2.scorer.SkillCompanionScorer;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.Instant;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ScorersTest {

    private final SearchProperties props = new SearchProperties();
    private final Instant now = Instant.now();

    private ScoringContext ctx(String... skills) {
        return new ScoringContext(Set.of(skills), now);
    }

    private Candidate candidate(boolean open, boolean immediate, String... skills) {
        return Candidate.builder().id(1L).fullName("X").openToWork(open).immediateJoiner(immediate)
                .skills(Set.of(skills)).build();
    }

    private CandidateFeatureSet features(int received, int responded, double avgHours, double sessions) {
        return CandidateFeatureSet.builder().candidateId(1L).inMailsReceived(received)
                .inMailsResponded(responded).avgResponseHours(avgHours).sessionActivity(sessions).build();
    }

    @Test
    void skillScorerGivesFullCreditForDirectMatches() {
        SkillCompanionScorer scorer = new SkillCompanionScorer(new SkillCompanionMatrix(), props);
        double s = scorer.score(candidate(false, false, "Java", "Spring Boot"), features(0, 0, 0, 0),
                ctx("java", "spring boot"));
        assertEquals(1.0, s, 1e-9);
    }

    @Test
    void skillScorerGivesDiscountedCreditForCompanionSkills() {
        SkillCompanionScorer scorer = new SkillCompanionScorer(new SkillCompanionMatrix(), props);
        double s = scorer.score(candidate(false, false, "Spring Boot"), features(0, 0, 0, 0), ctx("java"));
        assertEquals(0.9 * 0.8, s, 1e-9);
    }

    @Test
    void skillScorerIsNeutralWithoutQueriedSkills() {
        SkillCompanionScorer scorer = new SkillCompanionScorer(new SkillCompanionMatrix(), props);
        assertEquals(0.5, scorer.score(candidate(false, false, "Java"), features(0, 0, 0, 0), ctx()), 1e-9);
    }

    @Test
    void responsiveCandidatesOutscoreUnresponsiveOnes() {
        InMailResponsivenessScorer scorer = new InMailResponsivenessScorer(props);
        double good = scorer.score(candidate(true, false), features(10, 9, 2, 0), ctx());
        double bad = scorer.score(candidate(true, false), features(10, 0, 0, 0), ctx());
        assertTrue(good > bad);
        assertTrue(good <= 1.0 && bad >= 0.0);
    }

    @Test
    void openToWorkScoring() {
        OpenToWorkScorer scorer = new OpenToWorkScorer(props);
        assertEquals(1.0, scorer.score(candidate(true, true), features(0, 0, 0, 0), ctx()), 1e-9);
        assertEquals(0.8, scorer.score(candidate(true, false), features(0, 0, 0, 0), ctx()), 1e-9);
        assertEquals(0.1, scorer.score(candidate(false, false), features(0, 0, 0, 0), ctx()), 1e-9);
    }

    @Test
    void freshnessDecaysWithAge() {
        FreshnessScorer scorer = new FreshnessScorer(props);
        Candidate fresh = candidate(true, false);
        fresh.setProfileUpdatedAt(now);
        fresh.setLastActiveAt(now);
        Candidate stale = candidate(true, false);
        stale.setProfileUpdatedAt(now.minus(Duration.ofDays(400)));
        stale.setLastActiveAt(now.minus(Duration.ofDays(400)));
        assertTrue(scorer.score(fresh, features(0, 0, 0, 10), ctx()) > 0.99);
        assertTrue(scorer.score(stale, features(0, 0, 0, 0), ctx()) < 0.1);
    }
}
