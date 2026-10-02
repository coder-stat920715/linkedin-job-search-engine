package com.example.jobsearch.service;

import com.example.jobsearch.domain.JobPosting;
import com.example.jobsearch.dto.JobPostingRequest;
import com.example.jobsearch.dto.RecruiterSearchRequest;
import com.example.jobsearch.dto.SearchResponse;
import com.example.jobsearch.exception.ResourceNotFoundException;
import com.example.jobsearch.pipeline.RecruiterSearchPipeline;
import com.example.jobsearch.repository.JobPostingRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.HashSet;
import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class JobPostingService {

    private final JobPostingRepository repository;
    private final RecruiterSearchPipeline pipeline;

    @Transactional
    public JobPosting create(JobPostingRequest r) {
        return repository.save(JobPosting.builder()
                .title(r.title())
                .company(r.company())
                .location(r.location())
                .description(r.description())
                .minExperienceYears(r.minExperienceYears())
                .recruiterId(r.recruiterId())
                .requiredSkills(new HashSet<>(r.requiredSkills()))
                .postedAt(Instant.now())
                .active(true)
                .build());
    }

    @Transactional(readOnly = true)
    public JobPosting get(Long id) {
        return repository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Job posting " + id + " not found"));
    }

    /** Job -> candidates: OR over required skills for recall, L2 skill-companion scoring for precision. */
    public SearchResponse matchCandidates(Long jobId, int size) {
        JobPosting job = get(jobId);
        String query = job.getRequiredSkills().stream()
                .map(s -> "\"" + s.replace("\"", "") + "\"")
                .collect(Collectors.joining(" OR "));
        RecruiterSearchRequest request = new RecruiterSearchRequest(
                query, List.copyOf(job.getRequiredSkills()), job.getLocation(), null, null, size, job.getRecruiterId());
        return pipeline.execute(request);
    }
}
