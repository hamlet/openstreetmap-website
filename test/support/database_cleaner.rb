require "minitest/around"

DatabaseCleaner.strategy = :truncation
DatabaseCleaner.clean_with(:truncation)

class Minitest::Test
  def around(&block)
    DatabaseCleaner.cleaning(&block)
  end
end
