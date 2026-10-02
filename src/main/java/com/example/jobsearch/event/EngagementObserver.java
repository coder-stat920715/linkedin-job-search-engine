package com.example.jobsearch.event;

import com.example.jobsearch.dto.EngagementEvent;
import com.example.jobsearch.dto.EngagementType;

/** Observer Pattern: observers subscribe to engagement events by type. */
public interface EngagementObserver {
    boolean supports(EngagementType type);

    void onEvent(EngagementEvent event);
}
