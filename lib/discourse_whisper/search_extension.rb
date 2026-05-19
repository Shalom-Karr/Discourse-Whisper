# frozen_string_literal: true

module DiscourseWhisper
  # Filters whispers out of search results. Prepended onto ::Search so that
  # `posts_query` — the base query that produces candidate posts for search
  # hits — applies the same visibility rules as Guardian#can_see_post?.
  module SearchExtension
    def posts_query(*args, **kwargs)
      result = super
      DiscourseWhisper::QueryFilter.apply(result, @guardian&.user)
    end
  end
end
