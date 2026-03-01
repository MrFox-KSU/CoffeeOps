begin;

-- Ensure service_role can use schemas
grant usage on schema public to service_role;
grant usage on schema analytics to service_role;

-- Existing objects
grant all privileges on all tables in schema public to service_role;
grant all privileges on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;

grant select on all tables in schema analytics to service_role;
grant usage on all sequences in schema analytics to service_role;
grant execute on all functions in schema analytics to service_role;

-- Future objects (created by the migration runner / postgres)
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant all on sequences to service_role;
alter default privileges in schema public grant execute on functions to service_role;

alter default privileges in schema analytics grant select on tables to service_role;
alter default privileges in schema analytics grant usage on sequences to service_role;
alter default privileges in schema analytics grant execute on functions to service_role;

commit;
