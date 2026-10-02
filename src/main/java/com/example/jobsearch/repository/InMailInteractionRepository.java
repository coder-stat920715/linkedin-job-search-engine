package com.example.jobsearch.repository;

import com.example.jobsearch.domain.InMailInteraction;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface InMailInteractionRepository extends JpaRepository<InMailInteraction, Long> {
    Optional<InMailInteraction> findByMessageId(String messageId);
}
