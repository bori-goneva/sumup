create table cases_with_escalation
(
    case_id        text primary key,
    agent          text,
    manager        text,
    escalated_at   timestamp with time zone,
    first_reply_at timestamp with time zone
);

create table schedule
(
    agent           text,
    channel         text,
    schedule_date   timestamp with time zone,
    total_tp        integer,
    scheduled_hours integer
);

create table touchpoints
(
    tp_id                 text primary key,
    case_id               text,
    channel               text,
    agent                 text,
    manager               text,
    agent_country         text,
    tp_reason             text,
    tp_detailed_reason    text,
    agent_handling_time   integer,
    agent_tenure_in_month integer,
    is_elite_squad        boolean,
    created_at            timestamp with time zone,
    foreign key (case_id) references cases_with_escalation (case_id)
);