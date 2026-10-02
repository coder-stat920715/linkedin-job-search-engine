package com.example.jobsearch.config;

import com.example.jobsearch.domain.CandidateFeatureSet;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.serializer.Jackson2JsonRedisSerializer;
import org.springframework.data.redis.serializer.StringRedisSerializer;

@Configuration
public class RedisConfig {

    @Bean
    public RedisTemplate<String, CandidateFeatureSet> featureRedisTemplate(RedisConnectionFactory factory,
                                                                           ObjectMapper objectMapper) {
        RedisTemplate<String, CandidateFeatureSet> template = new RedisTemplate<>();
        template.setConnectionFactory(factory);
        StringRedisSerializer keySerializer = new StringRedisSerializer();
        Jackson2JsonRedisSerializer<CandidateFeatureSet> valueSerializer =
                new Jackson2JsonRedisSerializer<>(objectMapper, CandidateFeatureSet.class);
        template.setKeySerializer(keySerializer);
        template.setHashKeySerializer(keySerializer);
        template.setValueSerializer(valueSerializer);
        template.setHashValueSerializer(valueSerializer);
        template.afterPropertiesSet();
        return template;
    }
}
