class FixUserDetailsNullFields < ActiveRecord::Migration
  def up
    execute <<-SQL
      drop materialized view "1".user_totals CASCADE;

      create materialized view "1".user_totals AS
       SELECT b.user_id AS id,
          b.user_id,
          count(DISTINCT b.project_id) AS total_contributed_projects,
          sum(pa.value) AS sum,
          count(DISTINCT b.id) AS count,
              CASE
                  WHEN u.zero_credits THEN 0::numeric
                  ELSE sum(
                  CASE
                      WHEN lower(pa.gateway) = 'pagarme'::text THEN 0::numeric
                      WHEN p.state::text <> 'failed'::text AND NOT uses_credits(pa.*) THEN 0::numeric
                      WHEN p.state::text = 'failed'::text AND uses_credits(pa.*) THEN 0::numeric
                      WHEN p.state::text = 'failed'::text AND ((pa.state = ANY (ARRAY['pending_refund'::character varying::text, 'refunded'::character varying::text])) AND NOT uses_credits(pa.*) OR uses_credits(pa.*) AND NOT (pa.state = ANY (ARRAY['pending_refund'::character varying::text, 'refunded'::character varying::text]))) THEN 0::numeric
                      WHEN p.state::text = 'failed'::text AND NOT uses_credits(pa.*) AND pa.state = 'paid'::text THEN pa.value
                      ELSE pa.value * (-1)::numeric
                  END)
              END AS credits,
          (
            SELECT count(*) 
            FROM public.projects p2 
            WHERE p2.is_published AND p2.user_id = b.user_id
          ) AS total_published_projects
         FROM contributions b
           JOIN payments pa ON b.id = pa.contribution_id
           JOIN projects p ON b.project_id = p.id
           JOIN users u ON u.id = b.user_id
        WHERE pa.state = ANY (confirmed_states())
        GROUP BY b.user_id, u.zero_credits;

      create index user_totals_user_id_ix ON "1".user_totals (user_id);

      create or replace view "1".team_totals AS
       SELECT count(DISTINCT u.id) AS member_count,
          array_to_json(array_agg(DISTINCT country.name)) AS countries,
          count(DISTINCT c.project_id) FILTER (WHERE was_confirmed(c.*)) AS total_contributed_projects,
          count(DISTINCT lower(unaccent(u.address_city))) AS total_cities,
          sum(c.value) FILTER (WHERE was_confirmed(c.*)) AS total_amount
         FROM users u
           LEFT JOIN contributions c ON c.user_id = u.id
           LEFT JOIN countries country ON country.id = u.country_id
        WHERE u.admin;

      create or replace view "1".user_details as
        select
        	u.id,
        	u.name,
        	u.address_city,
          u.profile_img_thumbnail,
          u.facebook_link,
          u.twitter as twitter_username,
        	(
        		case
            when current_user = 'anonymous' then null
        		when public.is_owner_or_admin(u.id) or u.has_published_projects then u.email
        		else null
        		end
        	) as email,
          coalesce(ut.total_contributed_projects, 0) as total_contributed_projects,
          coalesce(ut.total_published_projects, 0) as total_published_projects,
        	(
            SELECT json_agg(distinct ul.link)
            FROM user_links ul 
            WHERE ul.user_id = u.id
          ) as links
        from users u
        left join user_totals ut on ut.user_id = u.id;

      grant select on "1".user_details to admin;
      grant select on "1".user_details to web_user;
      grant select on "1".user_details to anonymous;
    SQL
  end

  def down
    execute <<-SQL
      drop materialized view "1".user_totals CASCADE;
      create materialized view "1".user_totals AS
       SELECT b.user_id AS id,
          b.user_id,
          count(DISTINCT b.project_id) AS total_contributed_projects,
          sum(pa.value) AS sum,
          count(DISTINCT b.id) AS count,
              CASE
                  WHEN u.zero_credits THEN 0::numeric
                  ELSE sum(
                  CASE
                      WHEN lower(pa.gateway) = 'pagarme'::text THEN 0::numeric
                      WHEN p.state::text <> 'failed'::text AND NOT uses_credits(pa.*) THEN 0::numeric
                      WHEN p.state::text = 'failed'::text AND uses_credits(pa.*) THEN 0::numeric
                      WHEN p.state::text = 'failed'::text AND ((pa.state = ANY (ARRAY['pending_refund'::character varying::text, 'refunded'::character varying::text])) AND NOT uses_credits(pa.*) OR uses_credits(pa.*) AND NOT (pa.state = ANY (ARRAY['pending_refund'::character varying::text, 'refunded'::character varying::text]))) THEN 0::numeric
                      WHEN p.state::text = 'failed'::text AND NOT uses_credits(pa.*) AND pa.state = 'paid'::text THEN pa.value
                      ELSE pa.value * (-1)::numeric
                  END)
              END AS credits
         FROM contributions b
           JOIN payments pa ON b.id = pa.contribution_id
           JOIN projects p ON b.project_id = p.id
           JOIN users u ON u.id = b.user_id
        WHERE pa.state = ANY (confirmed_states())
        GROUP BY b.user_id, u.zero_credits;

      create or replace view "1".team_totals AS
       SELECT count(DISTINCT u.id) AS member_count,
          array_to_json(array_agg(DISTINCT country.name)) AS countries,
          count(DISTINCT c.project_id) FILTER (WHERE was_confirmed(c.*)) AS total_contributed_projects,
          count(DISTINCT lower(unaccent(u.address_city))) AS total_cities,
          sum(c.value) FILTER (WHERE was_confirmed(c.*)) AS total_amount
         FROM users u
           LEFT JOIN contributions c ON c.user_id = u.id
           LEFT JOIN countries country ON country.id = u.country_id
        WHERE u.admin;

      create or replace view "1".user_details as
        select
        	u.id,
        	u.name,
        	u.address_city,
          u.profile_img_thumbnail,
          u.facebook_link,
          u.twitter as twitter_username,
        	(
        		case
            when current_user = 'anonymous' then null
        		when public.is_owner_or_admin(u.id) or u.has_published_projects then u.email
        		else null
        		end
        	) as email,
          ut.total_contributed_projects,
        	count(p.id) filter (where p.is_published) as total_published_projects,
        	json_agg(distinct ul.link) as links
        from users u
        left join user_links ul on ul.user_id = u.id
        left join user_totals ut on ut.user_id = u.id
        left join projects p on p.user_id = u.id
        group by u.id, ut.total_contributed_projects;

      grant select on "1".user_details to admin;
      grant select on "1".user_details to web_user;
      grant select on "1".user_details to anonymous;
    SQL
  end
end
