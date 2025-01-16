-- Automated checks for column values uniqueness

do $$
    declare
col_name text;
        tbl_name text; -- changed variable name to avoid conflict
        target_schema text := 'sumup'; -- replace with your schema name if not 'public'
        is_unique boolean;
    begin
        -- loop through all tables in the specified schema
        for tbl_name in
            select t.table_name
            from information_schema.tables t
            where t.table_schema = target_schema
            loop
                raise notice 'checking table: %.%', target_schema, tbl_name;

                -- loop through all columns of the current table
                for col_name in
                select c.column_name
                from information_schema.columns c
                where c.table_name = tbl_name
                  and c.table_schema = target_schema
                loop
                    -- construct and execute the query to check uniqueness
                    execute format(
                            'select count(*) = count(distinct %i) from %i.%i',
                            col_name, target_schema, tbl_name
                            )
                        into is_unique;

                    -- output the result for each column
                    raise notice 'table: %, column: %, unique: %', tbl_name, col_name, is_unique;
                end loop;
            end loop;
end $$;

/*
RESULT (Console):

Checking table: sumup.cases_with_escalation
Table: cases_with_escalation, Column: case_id, Unique: t
Table: cases_with_escalation, Column: agent, Unique: f
Table: cases_with_escalation, Column: manager, Unique: f
Table: cases_with_escalation, Column: escalated_at, Unique: f
Table: cases_with_escalation, Column: first_reply_at, Unique: f
Checking table: sumup.touchpoints
Table: touchpoints, Column: case_id, Unique: f
Table: touchpoints, Column: tp_id, Unique: t
Table: touchpoints, Column: channel, Unique: f
Table: touchpoints, Column: agent, Unique: f
Table: touchpoints, Column: manager, Unique: f
Table: touchpoints, Column: agent_country, Unique: f
Table: touchpoints, Column: tp_reason, Unique: f
Table: touchpoints, Column: tp_detailed_reason, Unique: f
Table: touchpoints, Column: agent_handling_time, Unique: f
Table: touchpoints, Column: agent_tenure_in_month, Unique: f
Table: touchpoints, Column: is_elite_squad, Unique: f
Table: touchpoints, Column: created_at, Unique: f
Checking table: sumup.schedule
Table: schedule, Column: agent, Unique: f
Table: schedule, Column: channel, Unique: f
Table: schedule, Column: schedule_date, Unique: f
Table: schedule, Column: total_tp, Unique: f
Table: schedule, Column: scheduled_hours, Unique: f

*/