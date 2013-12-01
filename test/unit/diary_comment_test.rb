require File.dirname(__FILE__) + '/../test_helper'

class DiaryCommentTest < ActiveSupport::TestCase
  api_fixtures
  fixtures :languages, :diary_entries, :diary_comments
  
  def test_diary_comment_count
    assert_equal 4, DiaryComment.count
  end
end
