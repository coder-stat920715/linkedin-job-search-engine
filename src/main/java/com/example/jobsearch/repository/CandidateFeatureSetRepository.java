package com.example.jobsearch.repository;

import com.example.jobsearch.domain.CandidateFeatureSet;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface CandidateFeatureSetRepository extends JpaRepository<CandidateFeatureSet, Long> {

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select f from CandidateFeatureSet f where f.candidateId = :id")
    Optional<CandidateFeatureSet> findForUpdate(@Param("id") Long id);

    @Modifying
    @Query("update CandidateFeatureSet f set f.sessionActivity = f.sessionActivity * :factor")
    int decaySessionActivity(@Param("factor") double factor);
}
