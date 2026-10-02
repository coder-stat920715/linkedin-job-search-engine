package com.example.jobsearch.pipeline;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.RecruiterSearch;
import com.example.jobsearch.dto.RecruiterSearchRequest;
import com.example.jobsearch.dto.SearchResponse;
import com.example.jobsearch.l1.L1CandidateRetrievalService;
import com.example.jobsearch.l2.L2RerankingEngine;
import com.example.jobsearch.l2.ScoredCandidate;
import com.example.jobsearch.l2.SkillCompanionMatrix;
import com.example.jobsearch.query.BooleanQueryParserService;
import com.example.jobsearch.query.QueryNodeFactory;
import com.example.jobsearch.repository.RecruiterSearchRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class RecruiterSearchPipelineTest {

    @Mock
    private L1CandidateRetrievalService l1;
    @Mock
    private L2RerankingEngine l2;
    @Mock
    private RecruiterSearchRepository searchRepository;

    private Candidate candidate(long id, String location, boolean open) {
        return Candidate.builder().id(id).fullName("C" + id).location(location).openToWork(open)
                .skills(Set.of("Java")).build();
    }

    @Test
    void appliesFilterChainThenRerankThenAudits() {
        Candidate a = candidate(1L, "Mumbai", true);
        Candidate b = candidate(2L, "Pune", true);
        Candidate c = candidate(3L, "Mumbai", false);
        when(l1.retrieve(any())).thenReturn(new L1CandidateRetrievalService.L1Result(List.of(a, b, c), 3));
        when(l2.rerank(anyList(), any())).thenAnswer(inv -> {
            List<Candidate> in = inv.getArgument(0);
            return in.stream().map(x -> new ScoredCandidate(x, 0.9, Map.of("skillMatch", 0.9))).toList();
        });

        RecruiterSearchPipeline pipeline = new RecruiterSearchPipeline(
                new BooleanQueryParserService(new QueryNodeFactory()), l1,
                List.of(new LocationFilterHandler(), new OpenToWorkFilterHandler(), new NoticePeriodFilterHandler()),
                l2, new SkillCompanionMatrix(), new SearchProperties(), searchRepository);

        SearchResponse response = pipeline.execute(
                new RecruiterSearchRequest("\"java\"", List.of("Java"), "Mumbai", true, null, 10, 7L));

        assertEquals(3, response.l1Matches());
        assertEquals(1, response.afterFilters());
        assertEquals(1, response.results().size());
        assertEquals(1L, response.results().get(0).candidateId());
        assertEquals(List.of("Java"), response.results().get(0).matchedSkills());
        verify(searchRepository).save(any(RecruiterSearch.class));
    }
}
