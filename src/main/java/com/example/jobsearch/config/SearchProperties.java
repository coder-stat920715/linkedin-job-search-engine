package com.example.jobsearch.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

@Data
@ConfigurationProperties(prefix = "app.search")
public class SearchProperties {
    private int l1MaxCandidates = 2000;
    private int l2MaxCandidates = 500;
    private double companionDiscount = 0.8;
    private Weights weights = new Weights();

    @Data
    public static class Weights {
        private double skillMatch = 0.40;
        private double inMailResponse = 0.30;
        private double openToWork = 0.20;
        private double freshness = 0.10;
    }
}
