require "test_helper"

class HomeTest < ActionDispatch::IntegrationTest
  test "home renders CSRF metadata when a visitor returns with a session cookie" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    https!

    get root_path
    assert_response :success
    assert_select "meta[name='csrf-token'][content]", count: 1
    assert cookies.to_hash.any?, "The first page should set a session cookie"

    get root_path
    assert_response :success
    assert_select "meta[name='csrf-token'][content]", count: 1
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
end
