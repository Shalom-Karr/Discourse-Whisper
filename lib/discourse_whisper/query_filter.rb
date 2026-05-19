# frozen_string_literal: true

module DiscourseWhisper
  # Apply a whisper-visibility filter to an ActiveRecord Post scope. The
  # returned scope drops any post that has a `whisper_target_user_ids` custom
  # field whose audience does not include the given user.
  #
  # Used from:
  #   - TopicView.apply_custom_default_scope   (topic stream filtering)
  #   - Search#posts_query                      (search result filtering)
  #
  # The same visibility rules as Guardian#can_see_post? apply: author, target,
  # staff, and category group moderators can see. Anonymous viewers see
  # nothing. Anyone else is filtered out at the SQL level.
  module QueryFilter
    module_function

    def apply(scope, user)
      return scope unless SiteSetting.discourse_whisper_enabled
      return scope if user&.staff?

      join_sql = <<~SQL
        LEFT JOIN post_custom_fields dw_pcf
          ON dw_pcf.post_id = posts.id
          AND dw_pcf.name = 'whisper_target_user_ids'
          AND dw_pcf.value IS NOT NULL
          AND dw_pcf.value NOT IN ('', '[]', 'null')
      SQL

      if user
        cat_mod_clause =
          if SiteSetting.enable_category_group_moderation
            # Category group moderators have oversight EXCEPT when the whisper
            # is staff-to-staff (author is staff AND every target is staff).
            # In that case the cat-mod path is suppressed.
            <<~SQL
              OR (
                EXISTS (
                  SELECT 1
                  FROM category_moderation_groups dw_cmg
                  JOIN group_users dw_gu ON dw_gu.group_id = dw_cmg.group_id
                  JOIN topics dw_t ON dw_t.id = posts.topic_id
                  WHERE dw_cmg.category_id = dw_t.category_id
                    AND dw_gu.user_id = :user_id
                )
                AND (
                  -- Author is NOT staff → cat mod keeps oversight
                  EXISTS (
                    SELECT 1 FROM users dw_author
                    WHERE dw_author.id = posts.user_id
                      AND NOT (dw_author.admin OR dw_author.moderator)
                  )
                  OR
                  -- At least ONE target is not staff → cat mod keeps oversight
                  EXISTS (
                    SELECT 1
                    FROM users dw_target,
                         jsonb_array_elements_text(dw_pcf.value::jsonb) AS dw_tid(tid)
                    WHERE dw_target.id = dw_tid.tid::int
                      AND NOT (dw_target.admin OR dw_target.moderator)
                  )
                )
              )
            SQL
          else
            ""
          end

        where_sql = <<~SQL
          dw_pcf.id IS NULL
          OR posts.user_id = :user_id
          OR dw_pcf.value::jsonb @> :user_id_json::jsonb
          #{cat_mod_clause}
        SQL

        scope.joins(join_sql).where(where_sql, user_id: user.id, user_id_json: user.id.to_json)
      else
        scope.joins(join_sql).where("dw_pcf.id IS NULL")
      end
    end
  end
end
