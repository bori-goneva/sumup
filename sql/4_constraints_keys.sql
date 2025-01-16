alter table elite.elite_agents_viz
    add constraint pk_elite_agents primary key (agent);

alter table elite.elite_esccases_viz
    add constraint pk_elite_esccases primary key (case_id),
    add constraint fk_elite_esccases_agent foreign key (agent)
    references elite.elite_agents_viz (agent);
