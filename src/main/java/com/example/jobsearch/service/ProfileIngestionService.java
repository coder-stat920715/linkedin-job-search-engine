package com.example.jobsearch.service;

import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.dto.CandidateUpsertRequest;
import com.example.jobsearch.exception.ResourceNotFoundException;
import com.example.jobsearch.l1.L1CandidateRetrievalService;
import com.example.jobsearch.repository.CandidateRepository;
import com.example.jobsearch.util.TxUtils;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.HashSet;

@Slf4j
@Service
@RequiredArgsConstructor
public class ProfileIngestionService {

    private final CandidateRepository candidateRepository;
    private final L1CandidateRetrievalService l1;

    @Transactional
    public Candidate create(CandidateUpsertRequest request) {
        return save(new Candidate(), request);
    }

    @Transactional
    public Candidate update(Long id, CandidateUpsertRequest request) {
        Candidate existing = candidateRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Candidate " + id + " not found"));
        return save(existing, request);
    }

    @Transactional(readOnly = true)
    public Candidate get(Long id) {
        return candidateRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Candidate " + id + " not found"));
    }

    private Candidate save(Candidate c, CandidateUpsertRequest r) {
        c.setFullName(r.fullName());
        c.setHeadline(r.headline());
        c.setCurrentCompany(r.currentCompany());
        c.setCurrentTitle(r.currentTitle());
        c.setLocation(r.location());
        c.setOpenToWork(r.openToWork());
        c.setImmediateJoiner(r.immediateJoiner());
        c.setNoticePeriodDays(r.noticePeriodDays());
        c.setSkills(r.skills() == null ? new HashSet<>() : new HashSet<>(r.skills()));
        c.setProfileUpdatedAt(Instant.now());
        if (c.getLastActiveAt() == null) {
            c.setLastActiveAt(Instant.now());
        }
        Candidate saved = candidateRepository.save(c);
        TxUtils.afterCommit(() -> l1.indexCandidate(saved));
        log.info("Ingested candidate {}", saved.getId());
        return saved;
    }
}
