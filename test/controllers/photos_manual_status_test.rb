ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require "minitest/autorun"

class PhotosManualStatusTest < Minitest::Test
  class Controller < PhotosController
    attr_accessor :test_record, :test_client, :redirected, :cleared_record

    def redirect_to(path, **options)
      self.redirected = { path: path, **options }
    end

    private

    def photo_record(_id)
      test_record
    end

    def photos_record_client
      test_client
    end

    def photos_form_properties
      {}
    end

    def clear_photo_summary_cache(record)
      self.cleared_record = record
    end
  end

  def setup
    @controller = Controller.new
    @controller.request = ActionDispatch::TestRequest.create
    @controller.test_record = {
      "施工予定日" => { "value" => (Date.current - 1).iso8601 },
      "施工機通称" => { "value" => "PC200" },
      "写真完了フラグ" => { "type" => "DROP_DOWN", "value" => "未完了" }
    }
    @updates = []
    updates = @updates
    client = Object.new
    client.define_singleton_method(:update) { |*args| updates << args }
    @controller.test_client = client
  end

  def test_button_is_available_from_the_next_day_only
    assert @controller.send(:photo_status_switch_available?, @controller.test_record)
    [Date.current, Date.current + 1, nil, "日付未定"].each do |date|
      @controller.test_record["施工予定日"]["value"] = date&.to_s
      refute @controller.send(:photo_status_switch_available?, @controller.test_record)
    end
  end

  def test_both_status_options_update_only_the_flag
    %w[完了 未完了].each do |status|
      update_status(status)
      assert_equal ["123", { "写真完了フラグ" => { value: status } }], @updates.last
      assert_equal @controller.test_record, @controller.cleared_record
      assert_includes @controller.redirected[:notice], status
      assert_includes @controller.redirected[:path], "machine=PC200"
      assert_includes @controller.redirected[:path], "date=completed"
    end
  end

  def test_future_or_today_records_cannot_be_updated_by_direct_request
    [Date.current, Date.current + 1].each do |date|
      @controller.test_record["施工予定日"]["value"] = date.iso8601
      update_status("完了")
      assert @controller.redirected[:alert]
    end
    assert_empty @updates
  end

  def test_invalid_status_and_missing_field_are_rejected
    update_status("その他")
    assert @controller.redirected[:alert]
    @controller.test_record.delete("写真完了フラグ")
    update_status("完了")
    assert @controller.redirected[:alert]
    assert_empty @updates
  end

  def test_failure_does_not_show_success_or_clear_cache
    @controller.test_client.define_singleton_method(:update) { |*_args| raise Faraday::TimeoutError }
    update_status("完了")
    assert @controller.redirected[:alert]
    assert_nil @controller.redirected[:notice]
    assert_nil @controller.cleared_record
  end

  private

  def update_status(status)
    @controller.params = ActionController::Parameters.new(id: "123", photo_status: status, machine: "PC200", date: "completed")
    @controller.update_photo_status
  end
end
