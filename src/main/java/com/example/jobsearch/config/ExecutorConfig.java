package com.example.jobsearch.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

@Configuration
public class ExecutorConfig {

    /** Virtual-thread-per-task executor used for parallel L2 scoring (Java 21). */
    @Bean(name = "scoringExecutor")
    public ExecutorService scoringExecutor() {
        return Executors.newVirtualThreadPerTaskExecutor();
    }
}
