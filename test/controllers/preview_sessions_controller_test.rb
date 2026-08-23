require "test_helper"

class PreviewSessionsControllerTest < ActionDispatch::IntegrationTest
  test "signs the configured preview user in and redirects to Transaction Explorer" do
    user = users(:family_admin)

    with_env_overrides(
      "TRANSACTION_EXPLORER_PREVIEW_LOGIN" => "1",
      "TRANSACTION_EXPLORER_PREVIEW_USER_EMAIL" => user.email
    ) do
      post preview_session_path

      assert_redirected_to myfin_transaction_explorer_path
      assert_equal user, Session.order(:created_at).last.user
      follow_redirect!
      assert_response :success
      assert_select "h1", text: "Transaction Explorer"
    end
  end

  test "returns not found when preview login is not enabled" do
    with_env_overrides(
      "TRANSACTION_EXPLORER_PREVIEW_LOGIN" => nil,
      "TRANSACTION_EXPLORER_PREVIEW_USER_EMAIL" => users(:family_admin).email
    ) do
      assert_no_difference "Session.count" do
        post preview_session_path
      end

      assert_response :not_found
    end
  end
end
