package com.example.jobsearch.repository;

import com.example.jobsearch.domain.RecruiterSearch;
import org.springframework.data.jpa.repository.JpaRepository;

public interface RecruiterSearchRepository extends JpaRepository<RecruiterSearch, Long> {
}
