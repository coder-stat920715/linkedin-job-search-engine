package com.example.jobsearch.domain;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.HashSet;
import java.util.Set;

@Entity
@Table(name = "candidates", indexes = {
        @Index(name = "idx_candidates_company", columnList = "current_company"),
        @Index(name = "idx_candidates_location", columnList = "location")})
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Candidate {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String fullName;

    @Column(length = 500)
    private String headline;

    @Column(name = "current_company")
    private String currentCompany;

    private String currentTitle;

    @Column(name = "location")
    private String location;

    private boolean openToWork;
    private boolean immediateJoiner;
    private Integer noticePeriodDays;
    private Instant lastActiveAt;
    private Instant profileUpdatedAt;

    @ElementCollection(fetch = FetchType.EAGER)
    @CollectionTable(name = "candidate_skills", joinColumns = @JoinColumn(name = "candidate_id"))
    @Column(name = "skill", nullable = false)
    @Builder.Default
    private Set<String> skills = new HashSet<>();
}
