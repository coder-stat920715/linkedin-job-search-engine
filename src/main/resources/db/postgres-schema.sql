CREATE TABLE candidates (
    id                 BIGSERIAL PRIMARY KEY,
    full_name          VARCHAR(255) NOT NULL,
    headline           VARCHAR(500),
    current_company    VARCHAR(255),
    current_title      VARCHAR(255),
    location           VARCHAR(255),
    open_to_work       BOOLEAN NOT NULL DEFAULT FALSE,
    immediate_joiner   BOOLEAN NOT NULL DEFAULT FALSE,
    notice_period_days INT,
    last_active_at     TIMESTAMPTZ,
    profile_updated_at TIMESTAMPTZ
);
CREATE INDEX idx_candidates_company  ON candidates (current_company);
CREATE INDEX idx_candidates_location ON candidates (location);

CREATE TABLE candidate_skills (
    candidate_id BIGINT       NOT NULL REFERENCES candidates (id) ON DELETE CASCADE,
    skill        VARCHAR(255) NOT NULL,
    PRIMARY KEY (candidate_id, skill)
);

CREATE TABLE job_postings (
    id                   BIGSERIAL PRIMARY KEY,
    title                VARCHAR(255) NOT NULL,
    company              VARCHAR(255) NOT NULL,
    location             VARCHAR(255),
    description          VARCHAR(4000),
    min_experience_years INT,
    recruiter_id         BIGINT,
    posted_at            TIMESTAMPTZ,
    active               BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE job_required_skills (
    job_id BIGINT       NOT NULL REFERENCES job_postings (id) ON DELETE CASCADE,
    skill  VARCHAR(255) NOT NULL,
    PRIMARY KEY (job_id, skill)
);

CREATE TABLE recruiter_searches (
    id           BIGSERIAL PRIMARY KEY,
    recruiter_id BIGINT,
    raw_query    VARCHAR(2000) NOT NULL,
    result_count INT NOT NULL,
    took_ms      BIGINT NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL
);

CREATE TABLE inmail_communications (
    id           BIGSERIAL PRIMARY KEY,
    message_id   VARCHAR(255) NOT NULL UNIQUE,
    candidate_id BIGINT NOT NULL,
    recruiter_id BIGINT,
    sent_at      TIMESTAMPTZ NOT NULL,
    responded_at TIMESTAMPTZ
);
CREATE INDEX idx_inmail_candidate ON inmail_communications (candidate_id);
CREATE INDEX idx_inmail_recruiter ON inmail_communications (recruiter_id);

CREATE TABLE candidate_feature_scores (
    candidate_id       BIGINT PRIMARY KEY,
    inmails_received   INT NOT NULL DEFAULT 0,
    inmails_responded  INT NOT NULL DEFAULT 0,
    avg_response_hours DOUBLE PRECISION NOT NULL DEFAULT 0,
    session_activity   DOUBLE PRECISION NOT NULL DEFAULT 0,
    updated_at         TIMESTAMPTZ
);
