package com.example.jobsearch.l1;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.query.BooleanQueryParserService;
import com.example.jobsearch.query.QueryNodeFactory;
import com.example.jobsearch.repository.CandidateRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class L1CandidateRetrievalServiceTest {

    @Mock
    private CandidateRepository repository;

    private final BooleanQueryParserService parser = new BooleanQueryParserService(new QueryNodeFactory());
    private L1CandidateRetrievalService service;
    private Candidate c1;

    @BeforeEach
    void setUp() {
        service = new L1CandidateRetrievalService(new InvertedIndex(), new CandidateTermExtractor(), repository,
                new SearchProperties());
        c1 = Candidate.builder().id(1L).fullName("A").currentCompany("JPMorgan")
                .currentTitle("Talent Acquisition Specialist").skills(Set.of("Java", "Spring Boot"))
                .openToWork(true).immediateJoiner(true).build();
        Candidate c2 = Candidate.builder().id(2L).fullName("B").currentCompany("Google")
                .currentTitle("Software Engineer").skills(Set.of("Python")).build();
        service.indexCandidate(c1);
        service.indexCandidate(c2);
    }

    @Test
    void retrievesOnlyMatchingCandidatesUsingPhraseAndFlagTerms() {
        when(repository.findAllById(List.of(1L))).thenReturn(List.of(c1));
        var result = service.retrieve(parser.parse("\"talent acquisition\" AND java AND \"immediate joiner\""));
        assertEquals(1, result.totalMatches());
        assertEquals(List.of(c1), result.candidates());
    }

    @Test
    void removedCandidatesAreNoLongerRetrievable() {
        service.removeCandidate(1L);
        var result = service.retrieve(parser.parse("java"));
        assertEquals(0, result.totalMatches());
        assertTrue(result.candidates().isEmpty());
    }
}
