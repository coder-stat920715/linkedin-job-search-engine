package com.example.jobsearch.pipeline;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.RecruiterSearch;
import com.example.jobsearch.dto.CandidateSearchResultDTO;
import com.example.jobsearch.dto.RecruiterSearchRequest;
import com.example.jobsearch.dto.SearchResponse;
import com.example.jobsearch.l1.L1CandidateRetrievalService;
import com.example.jobsearch.l2.L2RerankingEngine;
import com.example.jobsearch.l2.ScoredCandidate;
import com.example.jobsearch.l2.ScoringContext;
import com.example.jobsearch.l2.SkillCompanionMatrix;
import com.example.jobsearch.query.BooleanQueryParserService;
import com.example.jobsearch.query.QueryNode;
import com.example.jobsearch.query.TermNormalizer;
import com.example.jobsearch.repository.RecruiterSearchRepository;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/** Orchestrates: parse -> L1 retrieval -> filter chain -> L2 rerank -> page -> audit. */
@Slf4j
@Service
public class RecruiterSearchPipeline {

    private final BooleanQueryParserService parser;
    private final L1CandidateRetrievalService l1;
    private final List<CandidateFilterHandler> filterHandlers;
    private final L2RerankingEngine l2;
    private final SkillCompanionMatrix matrix;
    private final SearchProperties properties;
    private final RecruiterSearchRepository searchRepository;

    public RecruiterSearchPipeline(BooleanQueryParserService parser,
                                   L1CandidateRetrievalService l1,
                                   List<CandidateFilterHandler> filterHandlers,
                                   L2RerankingEngine l2,
                                   SkillCompanionMatrix matrix,
                                   SearchProperties properties,
                                   RecruiterSearchRepository searchRepository) {
        this.parser = parser;
        this.l1 = l1;
        this.filterHandlers = filterHandlers;
        this.l2 = l2;
        this.matrix = matrix;
        this.properties = properties;
        this.searchRepository = searchRepository;
    }

    public SearchResponse execute(RecruiterSearchRequest request) {
        long start = System.nanoTime();
        String searchId = UUID.randomUUID().toString();
        log.info("Search {} started: query='{}'", searchId, request.query());

        QueryNode ast = parser.parse(request.query());
        Set<String> queriedSkills = deriveQueriedSkills(ast, request);

        L1CandidateRetrievalService.L1Result l1Result = l1.retrieve(ast);
        List<Candidate> filtered = new CandidateFilterChain(filterHandlers).proceed(l1Result.candidates(), request);

        List<Candidate> forRerank = filtered.stream()
                .sorted(Comparator.comparing(Candidate::getProfileUpdatedAt,
                        Comparator.nullsLast(Comparator.reverseOrder())))
                .limit(properties.getL2MaxCandidates())
                .toList();

        List<ScoredCandidate> ranked = l2.rerank(forRerank, new ScoringContext(queriedSkills, Instant.now()));
        List<CandidateSearchResultDTO> results = ranked.stream()
                .limit(request.effectivePageSize())
                .map(s -> toDto(s, queriedSkills))
                .toList();

        long tookMs = (System.nanoTime() - start) / 1_000_000;
        audit(request, results.size(), tookMs);
        log.info("Search {} finished: l1={}, filtered={}, returned={}, tookMs={}",
                searchId, l1Result.totalMatches(), filtered.size(), results.size(), tookMs);
        return new SearchResponse(searchId, l1Result.totalMatches(), filtered.size(), tookMs, results);
    }

    private Set<String> deriveQueriedSkills(QueryNode ast, RecruiterSearchRequest request) {
        Set<String> skills = new LinkedHashSet<>();
        request.skillsOrEmpty().forEach(s -> skills.add(TermNormalizer.normalize(s)));
        Set<String> terms = new LinkedHashSet<>();
        ast.collectPositiveTerms(terms);
        terms.stream().filter(matrix::isKnownSkill).forEach(skills::add);
        skills.remove("");
        return skills;
    }

    private CandidateSearchResultDTO toDto(ScoredCandidate s, Set<String> queriedSkills) {
        Candidate c = s.candidate();
        List<String> matched = c.getSkills().stream()
                .filter(skill -> queriedSkills.contains(TermNormalizer.normalize(skill)))
                .sorted()
                .toList();
        return new CandidateSearchResultDTO(c.getId(), c.getFullName(), c.getHeadline(), c.getCurrentCompany(),
                c.getCurrentTitle(), c.getLocation(), c.isOpenToWork(), s.score(), s.breakdown(), matched);
    }

    private void audit(RecruiterSearchRequest request, int resultCount, long tookMs) {
        try {
            searchRepository.save(RecruiterSearch.builder()
                    .recruiterId(request.recruiterId())
                    .rawQuery(request.query())
                    .resultCount(resultCount)
                    .tookMs(tookMs)
                    .createdAt(Instant.now())
                    .build());
        } catch (RuntimeException e) {
            log.warn("Failed to persist search audit record: {}", e.getMessage());
        }
    }
}
