package com.example.jobsearch.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class SwaggerConfig {

    @Bean
    public OpenAPI jobSearchOpenApi() {
        return new OpenAPI().info(new Info()
                .title("Job Search & Recruiter Candidate Matching API")
                .version("1.0.0")
                .description("L1 Boolean retrieval + L2 multi-factor reranking over candidate profiles")
                .contact(new Contact().name("Search & Matching Infrastructure")));
    }
}
