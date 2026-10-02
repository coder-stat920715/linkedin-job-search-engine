package com.example.jobsearch.l1;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.query.QueryNode;
import com.example.jobsearch.repository.CandidateRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Set;

/** L1 fast retrieval: Boolean AST evaluation on the inverted index, then hydrate candidates from the system of record. */
@Slf4j
@Service
@RequiredArgsConstructor
public class L1CandidateRetrievalService {

    private final InvertedIndex index;
    private final CandidateTermExtractor extractor;
    private final CandidateRepository candidateRepository;
    private final SearchProperties properties;

    public record L1Result(List<Candidate> candidates, int totalMatches) {
    }

    public void indexCandidate(Candidate candidate) {
        index.upsert(candidate.getId(), extractor.extract(candidate));
    }

    public void removeCandidate(Long candidateId) {
        index.remove(candidateId);
    }

    @EventListener(ApplicationReadyEvent.class)
    @Order(1)
    public void rebuildOnStartup() {
        log.info("L1 index rebuilt with {} candidates", rebuildIndex());
    }

    public int rebuildIndex() {
        index.clear();
        candidateRepository.findAll().forEach(this::indexCandidate);
        return index.size();
    }

    public L1Result retrieve(QueryNode ast) {
        Set<Long> ids = index.search(ast);
        int total = ids.size();
        List<Long> limited = ids.stream().sorted().limit(properties.getL1MaxCandidates()).toList();
        List<Candidate> candidates = limited.isEmpty() ? List.of() : candidateRepository.findAllById(limited);
        log.debug("L1 retrieved {} matches, hydrated {}", total, candidates.size());
        return new L1Result(candidates, total);
    }
}
