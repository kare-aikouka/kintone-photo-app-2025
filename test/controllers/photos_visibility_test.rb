ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require "minitest/autorun"

class PhotosVisibilityTest < Minitest::Test
  class Controller < PhotosController
    attr_accessor :test_record, :test_client, :redirected, :cleared_record, :test_records

    def redirect_to(path, **options)
      self.redirected = { path: path, **options }
    end

    private

    def photo_record(_id)
      test_record
    end

    def photo_records_for(_machine_values)
      test_records
    end

    def refresh_photo_summary_statuses!(_records)
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
      "写真完了フラグ" => { "type" => "DROP_DOWN", "value" => "未完了" },
      "写真アプリ非表示" => { "type" => "CHECK_BOX", "value" => [] }
    }
    @updates = []
    updates = @updates
    client = Object.new
    client.define_singleton_method(:update) { |*args| updates << args }
    @controller.test_client = client
  end

  def test_button_is_available_from_the_next_day_only
    assert @controller.send(:photo_visibility_change_available?, @controller.test_record)
    [Date.current, Date.current + 1, nil, "日付未定"].each do |date|
      @controller.test_record["施工予定日"]["value"] = date&.to_s
      refute @controller.send(:photo_visibility_change_available?, @controller.test_record)
    end
  end

  def test_hiding_updates_only_visibility_and_preserves_the_photo_flag
    %w[完了 未完了].each do |status|
      @controller.test_record["写真完了フラグ"]["value"] = status
      update_visibility("hide")
      assert_equal ["123", { "写真アプリ非表示" => { value: ["非表示"] } }], @updates.last
      assert_equal status, @controller.test_record["写真完了フラグ"]["value"]
      assert_equal @controller.test_record, @controller.cleared_record
      assert_includes @controller.redirected[:notice], "非表示"
      assert_includes @controller.redirected[:path], "machine=PC200"
      assert_includes @controller.redirected[:path], "date=hidden"
    end
  end

  def test_future_or_today_records_cannot_be_updated_by_direct_request
    [Date.current, Date.current + 1].each do |date|
      @controller.test_record["施工予定日"]["value"] = date.iso8601
      update_visibility("hide")
      assert @controller.redirected[:alert]
    end
    assert_empty @updates
  end

  def test_invalid_action_and_missing_or_wrong_field_are_rejected
    update_visibility("完了")
    assert @controller.redirected[:alert]
    @controller.test_record["写真アプリ非表示"]["type"] = "DROP_DOWN"
    update_visibility("hide")
    assert @controller.redirected[:alert]
    @controller.test_record.delete("写真アプリ非表示")
    update_visibility("hide")
    assert @controller.redirected[:alert]
    assert_empty @updates
  end

  def test_failure_does_not_show_success_or_clear_cache
    @controller.test_client.define_singleton_method(:update) { |*_args| raise Faraday::TimeoutError }
    update_visibility("hide")
    assert @controller.redirected[:alert]
    assert_nil @controller.redirected[:notice]
    assert_nil @controller.cleared_record
  end

  def test_restoring_has_no_schedule_date_restriction
    [Date.current, Date.current + 1, nil, Date.current - 400].each do |date|
      @controller.test_record["施工予定日"]["value"] = date&.to_s
      @controller.test_record["写真アプリ非表示"]["value"] = ["非表示"]
      assert @controller.send(:photo_visibility_change_available?, @controller.test_record)
      update_visibility("show")
      assert_equal ["123", { "写真アプリ非表示" => { value: [] } }], @updates.last
      assert_includes @controller.redirected[:notice], "一覧に戻しました"
      assert_equal "未完了", @controller.test_record["写真完了フラグ"]["value"]
    end
  end

  def test_other_checkbox_options_are_preserved_when_restoring
    @controller.test_record["写真アプリ非表示"]["value"] = ["非表示", "別の選択肢"]
    update_visibility("show")
    assert_equal ["123", { "写真アプリ非表示" => { value: ["別の選択肢"] } }], @updates.last
  end

  def test_hidden_records_are_separate_from_every_normal_filter
    visible = record("1", Date.current)
    hidden_past = record("2", Date.current - 1, hidden: true)
    hidden_done = record("3", Date.current - 2, hidden: true, status: "完了")
    hidden_future = record("4", Date.current + 20, hidden: true)
    @controller.test_records = [visible, hidden_past, hidden_done, hidden_future]

    [Date.current.to_s, "all", "completed", "hidden"].each do |filter|
      @controller.params = ActionController::Parameters.new(machine: "PC200", date: filter)
      @controller.index
      assert_nil @controller.instance_variable_get(:@photo_error)
      assert_equal [visible], @controller.instance_variable_get(:@default_records)
      assert_equal [visible], @controller.instance_variable_get(:@incomplete_records)
      selected = @controller.instance_variable_get(:@selected_records)
      if filter == "hidden"
        assert_equal [hidden_done, hidden_past, hidden_future], selected
      else
        assert_empty selected & [hidden_past, hidden_done, hidden_future]
      end
    end
  end

  def test_hidden_filter_remains_available_for_cooperation_machines
    @controller.test_records = [record("1", Date.current + 20, hidden: true)]
    @controller.params = ActionController::Parameters.new(machine: "住パイ", date: "hidden")
    @controller.index
    assert_equal "hidden", @controller.instance_variable_get(:@selected_filter)
    assert_equal @controller.test_records, @controller.instance_variable_get(:@selected_records)
    refute @controller.instance_variable_get(:@future_records_enabled)
  end

  def test_hidden_records_outside_the_normal_date_range_are_still_requested
    query = @controller.send(:photo_summary_query)
    assert_includes query, 'or 写真アプリ非表示 in ("非表示")'
    assert_includes query, "施工予定日 > FROM_TODAY(-1, MONTHS)"
  end

  def test_summaries_include_visibility_when_the_field_is_available
    client = Object.new
    client.define_singleton_method(:properties) { { "写真アプリ非表示" => { "type" => "CHECK_BOX" } } }
    @controller.define_singleton_method(:available_field_codes) { |_client| ["写真アプリ非表示"] }
    assert_includes @controller.send(:summary_field_codes, client), "写真アプリ非表示"
  end

  def test_office_restoration_refreshes_cached_visibility
    cached = record("1", Date.current - 1, hidden: true)
    fresh = record("1", Date.current - 1)
    @controller.define_singleton_method(:available_field_codes) { |_client| ["写真アプリ非表示"] }
    @controller.define_singleton_method(:fetch_all_photo_records) { |*_args, **_options| [fresh] }
    PhotosController.instance_method(:refresh_photo_summary_statuses!).bind(@controller).call([cached])
    refute @controller.send(:photo_app_hidden?, cached)
    assert_equal "未完了", cached["写真完了フラグ"]["value"]
  end

  private

  def record(id, date, hidden: false, status: "未完了")
    {
      "$id" => { "value" => id },
      "施工予定日" => { "value" => date.to_s },
      "写真完了フラグ" => { "value" => status },
      "写真アプリ非表示" => { "value" => hidden ? ["非表示"] : [] }
    }
  end

  def update_visibility(visibility)
    @controller.params = ActionController::Parameters.new(id: "123", visibility: visibility, machine: "PC200", date: "hidden")
    @controller.update_visibility
  end
end
