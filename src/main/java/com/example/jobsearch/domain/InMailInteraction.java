package com.example.jobsearch.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

@Entity
@Table(name = "inmail_communications", indexes = {
        @Index(name = "idx_inmail_candidate", columnList = "candidate_id"),
        @Index(name = "idx_inmail_recruiter", columnList = "recruiter_id")})
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class InMailInteraction {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "message_id", nullable = false, unique = true)
    private String messageId;

    @Column(name = "candidate_id", nullable = false)
    private Long candidateId;

    @Column(name = "recruiter_id")
    private Long recruiterId;

    @Column(name = "sent_at", nullable = false)
    private Instant sentAt;

    @Column(name = "responded_at")
    private Instant respondedAt;
}
