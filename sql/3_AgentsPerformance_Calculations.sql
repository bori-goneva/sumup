/*
Elite Squad SLA Performance Analysis
--------------------------------------------------------------------------------
Objective: Calculate SLA adherence for the Elite Squad support team
Requirements:
- Response time should be within 6 hours
- Only consider business hours (Mon-Fri, 9AM-6PM)
- Exclude weekends from calculations
 */

-- I. Create temp tables filtered from non-elite-squad agents (and keep source data untouched)

-- AGENTS-RELATED
-- 1. create a simple elite-squad agents list to filter by

-- filter out the elite squad agents' touchpoints
create temp table elite_agents_list as (
select distinct agent -- 22/27
from elite.touchpoints
where is_elite_squad = true -- 8317/10000
);


--  2. schedule only of elite-squad agents
create temp table elite_schedule as (
    select sch.*,
           ((sch.total_tp::float)/(sch.scheduled_hours)) as tp_per_hour -- touchpoint productivity of elite squad agents
           -- that will be compared to their sla compliance
    from elite_agents_list a
    left join elite.schedule sch
    on a.agent = sch.agent
);

-- select *
-- from elite_schedule;

-- -- check counts of elite_schedule
-- select distinct schedule_date
-- from elite_schedule;
-- -- 2613 records, 2206 about elite squad agents
-- -- 1198 (agent x schedule_date); 66 schedule dates from 2024-03-01 till 2024-05-30

-- CASES-related
-- 3. cases with escalation handled only by elite-squad agents
-- cases_with_escalation: 7248 in total, 5792 only of elite agents

-- select distinct agent
-- from elite.cases_with_escalation; --27 agents in total
-- -- ! so cases_with_escalation doesn't only contain elite squad agents' cases (as it is in the instructions)
-- -- because it has all 27 distinct agents, incl. non-elite squad ones
-- -- where instructions:
-- -- "Escalations: Dataset containing information about cases that were escalated to
-- -- SumUp's elite squad team."

-- -- a check whether on each case, only 1 agent has worked
-- select distinct c.case_id
-- from elite_esccases c
--          left outer join elite.touchpoints tp
--                          on c.case_id = tp.case_id
-- group by c.case_id,c.agent;
-- --> YES

create temp table elite_esccases AS (
    select esc.*
    from elite.cases_with_escalation esc
    right join elite_agents_list a
    on esc.agent = a.agent
);


-- 4. touchpoints created on the escalated cases handled only by elite-squad agents

-- Now we do not filter touchpoints by is_elite_squad flag only
-- because whether a touchpoint is of our interest or not
-- depends on whether it is related to a case with escalation handled by elite-squad agent
-- so we need to start the filtering process from the elite_esccases

-- -- first check if all agents solving cases_with_escalation match the touchpoints.is_elite_squad
-- select count(*)
-- from elite.touchpoints t --8317
-- right join elite_agents_list a
-- on t.agent = a.agent; -- 8317
--
-- select count(*)
-- from elite.touchpoints t
-- where is_elite_squad = true; --8317
-- --> yes

-- -- check counts of
-- select count(*)
-- from elite.touchpoints t
-- inner join elite.cases_with_escalation esc
-- on t.case_id = esc.case_id;
-- -- 7248 distinct cases with escalation; 1888 distinct touchpoints for them (in touchpoints)
-- -- 10000 total touchpoints with 4414 non-null case_id rows, 3952 distinct case_id;
-- select count(*)
-- from elite.cases_with_escalation
-- where case_id is not null;
-- -- 5601 case ids don't have relevant info in touchpoints

create temp table elite_esccases_touchpoints as (
select t.*
from elite.touchpoints t
inner join elite_esccases esc -- filter by all found in elite_esccases
on t.agent = esc.agent
and t.case_id = esc.case_id
-- 1515
);

-- II. KPIs

-- CASE-related

-- 1. SLA adherence: 6h
-- let's first adjust the sla actions (escalation, first reply) to working hours
create temp table elite_esccases_sla_actions as (
    select *,
    -- convert original dates to working business hours dates
    -- sla_escalated_at
        case
            -- Check if the date is a weekend (0 = Sunday, 6 = Saturday) or outside working hours (before 9 AM or after 6 PM)
            when extract(dow from escalated_at) in (0, 6)
                     or extract(hour from escalated_at) >= 18
                     or extract(hour from escalated_at) < 9
            then
                (
                    -- start with the beginning of the day
                    date_trunc('day', escalated_at) +
                    -- add the appropriate number of days based on the day of the week and time
                    interval '1 day' *
                    (case
                        when extract(dow from escalated_at) = 5 then 3  -- friday: move to monday (+3 days)
                        when extract(dow from escalated_at) = 6 then 2  -- saturday: move to monday (+2 days)
                        when extract(dow from escalated_at) = 0 then 1  -- sunday: move to monday (+1 day)
                        else (case when extract(hour from escalated_at) >= 18 then 1 else 0 end)  -- after 6 pm: move to next day, before 9 am: stay on same day
                    end) +
                    -- set the time to 9 am
                    interval '9 hour'
                )::timestamp
                -- if it's a weekday and within working hours, keep the original timestamp
            else escalated_at
        end
            as sla_escalated_at,

    -- sla_first_reply_at
    case
        when extract(dow from first_reply_at) in (0,6)
            then date_trunc('day', first_reply_at - interval '1 day' * (case when extract(dow from first_reply_at) = 0 then 2 else 1 end)) + interval '9 hour'
        when extract(hour from first_reply_at) not between 9 and 17
            then date_trunc('day', first_reply_at) + interval '9 hour'
        else first_reply_at
    end
      as sla_first_reply_at

    from elite_esccases
);

-- select *
-- from elite_esccases_kpis;

-- we'll split the time calculation in 3 parts:
-- escalation hours: time until end of the working day at the day of adjusted escalation
-- first reply hours: time from start of working day until the moment of adjusted first reply
-- full working day: number of full working days in the difference between the dates of adjusted escalation and adjusted first reply
create temp table elite_esccases_sla_timesplit as (
    select
        agent,
        case_id,
        sla_escalated_at,
        sla_first_reply_at,

        case
            -- same-day case: calculate only the time difference if on the same day
            when date(sla_escalated_at) = date(sla_first_reply_at)
                then 0 -- only first_reply_hours will 'cover' the few-hour difference
            else
                -- remaining working hours on escalation day
                greatest(
                        0,
                        18 - (extract(hour from sla_escalated_at) + extract(minute from sla_escalated_at) / 60.0)
                )
        end
        as escalation_hours,

        -- working hours for first reply day
        case
            -- same-day case: only first_reply_hours will 'cover' the few-hour difference
            when date(sla_escalated_at) = date(sla_first_reply_at)
                then extract(epoch from (sla_first_reply_at - sla_escalated_at)) / 3600.0
            else
                greatest(
                        0,
                        least(
                                18, -- upper bound: 6 pm
                                extract(hour from sla_first_reply_at) + extract(minute from sla_first_reply_at) / 60.0
                        ) - 9 -- lower bound: 9 am
                )
            end
            as first_reply_hours,

        -- full working days between adjusted both escalation and first reply
        (select count(*)
         from generate_series(
                      cast(sla_escalated_at as date) + interval '1 day',
                      cast(sla_first_reply_at as date) - interval '1 day',
                      '1 day'::interval
              ) as generated(day)
         where extract(dow from generated.day) between 1 and 5 -- weekdays only
        ) as full_working_days
    from elite_esccases_sla_actions
);

-- select *
-- from elite_esccases_sla_timesplit;

-- select count(*)
-- from generate_series(
--              cast(sla_escalated_at as date) + interval '1 day',
--              cast(sla_first_reply_at as date) - interval '1 day',
--              '1 day'::interval
--      ) as generated(day

create temp table elite_esccases_sla_calc as (
    select
        agent,
        case_id,
        sla_escalated_at,
        sla_first_reply_at,
        escalation_hours,
        first_reply_hours,
        full_working_days * 9 as mid_working_hours, -- 9 hours per full day
        -- total sla in working hours
        escalation_hours + first_reply_hours + (full_working_days * 9) as total_sla_hours,
        case
            when escalation_hours + first_reply_hours + (full_working_days * 9) >6 --total_sla_hours
            then false
            else true
        end
            as is_sla_met

    from elite_esccases_sla_timesplit
);

-- select *
--     from elite_esccases_sla_calc;

-- bonus case-related kpi:
-- are all cases with attached touchpoints? add a metric showing touchpoint count per case
create temp table elite_touchpoints_per_esccase_stat as (
    select c.case_id,
           c.agent,
           count(tp.tp_id) as touchpoints_per_esccase
    from elite_esccases as c
             left outer join elite_esccases_touchpoints as tp
                             on c.case_id = tp.case_id
    group by c.case_id, c.agent
-- 5792
);

create temp table elite_agents_touchpoints_per_esccase_stat as (
select agent,
       avg(touchpoints_per_esccase) as agent_avg_touchpoints_per_esccase
from elite_touchpoints_per_esccase_stat
group by agent
);

-- AGENT-related

-- 2. average handling time
create temp table elite_agents_avg_handling as (
select agent,
       avg(total_sla_hours) as agent_avg_sla_hours,
       avg(case when is_sla_met then 1 else 0 end) as agent_perc_sla_met
from elite_esccases_sla_calc
group by agent
);

-- 3. Touchpoints per productive hours
-- Created in elite_schedule
create temp table elite_agents_touchpoints_per_hour as (
select agent,
       avg(tp_per_hour) as agent_avg_tp_per_hour
from elite_schedule
group by agent
);

-- bonus agent-related KPI:
-- agent handling time per tp
create temp table elite_agents_handling_time_per_tp as (
select agent,
       avg(agent_handling_time) as agent_avg_handling_time_per_tp
from elite_esccases_touchpoints
where agent in (select agent from elite_agents_list)
group by agent
);

-- select *
-- from elite_agents_handling_time_per_tp;

-- III. Viz tables enrichment
-- We can view this data model from 2 main perspectives:
-- 1. Agents with all their characteristics, + derived KPIs;
-- (where we can also group by manager and derive actionable insights for the management)
-- 2. Cases - characteristics + SLA and touchpoint metrics

-- 1. AGENTS viz
-- needs to contain:
-- for all agents in elite_agents_list,
-- agent-specific characteristics from elite_esccases_touchpoints
-- avg sla hours
-- avg tp per hour
-- avg tp per case
-- avg handling time per tp

create table elite.elite_agents_viz as (
select distinct tp.agent,
tp.manager,
tp.agent_country,
tp.agent_tenure_in_month,
avg_handling.agent_avg_sla_hours,
avg_handling.agent_perc_sla_met,
tpperhour.agent_avg_tp_per_hour,
tppercase.agent_avg_touchpoints_per_esccase,
handlingtimepertp.agent_avg_handling_time_per_tp
from elite_esccases_touchpoints tp
left join elite_agents_avg_handling avg_handling
on tp.agent = avg_handling.agent
left join elite_agents_touchpoints_per_hour tpperhour
on tp.agent = tpperhour.agent
left join elite_agents_touchpoints_per_esccase_stat tppercase
on tp.agent = tppercase.agent
left join elite_agents_handling_time_per_tp handlingtimepertp
on tp.agent = handlingtimepertp.agent
);
-- 22

-- 2. CASES viz
-- needs to contain:
-- elite_esccases: case-related identificators like case_id, agent, escalated_at, first_reply_at
-- sla_calc: total sla hours
-- elite_touchpoints_per_esccase_stat: tp per case

create table elite.elite_esccases_viz as (
select esc.case_id,
esc.agent,
sla.total_sla_hours,
sla.is_sla_met,
tp.touchpoints_per_esccase
from elite_esccases esc
join elite_esccases_sla_calc sla
on esc.case_id = sla.case_id
join elite_touchpoints_per_esccase_stat tp
on esc.case_id = tp.case_id
);
-- 5792

-- NOTE: we could take additional info about touchpoints and attach it to cases
-- but it would be rather peripheral than focused for this analysis
-- e.g. if the agent has filled tp_reason etc.