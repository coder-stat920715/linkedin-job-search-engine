package com.example.jobsearch.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

/** L2 feature-store row: system of record in SQL, hot copy in Redis. */
@Entity
@Table(name = "candidate_feature_scores")
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CandidateFeatureSet {

    @Id
    @Column(name = "candidate_id")
    private Long candidateId;

    @Column(name = "inmails_received", nullable = false)
    private int inMailsReceived;

    @Column(name = "inmails_responded", nullable = false)
    private int inMailsResponded;

    @Column(name = "avg_response_hours", nullable = false)
    private double avgResponseHours;

    @Column(name = "session_activity", nullable = false)
    private double sessionActivity;

    @Column(name = "updated_at")
    private Instant updatedAt;

    public static CandidateFeatureSet empty(Long candidateId) {
        return CandidateFeatureSet.builder().candidateId(candidateId).updatedAt(Instant.now()).build();
    }
}
