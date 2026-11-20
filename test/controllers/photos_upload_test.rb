ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require "minitest/autorun"

class PhotosUploadTest < Minitest::Test
  class Controller < PhotosController
    attr_accessor :test_record, :test_client, :test_file_key, :test_large_client

    def signed_in?
      request.headers["X-Test-Signed-In"] == "yes"
    end

    private

    def photo_record(_id)
      test_record
    end

    def photos_form_properties
      { "テーブルその他" => { "type" => "SUBTABLE", "fields" => { "その他" => { "type" => "FILE" } } } }
    end

    def uploaded_photo_file_key(photo, **)
      return if photo.blank? || test_file_key.blank?

      pending_photo_upload_logs << {}
      test_file_key
    end

    def photos_record_client
      test_client
    end

    def large_photo_detail_item_by_code(_code)
      { label: "撮影項目", item_code: "test" }
    end

    def upload_large_photo_detail_file(*)
      test_file_key
    end

    def large_photo_detail_record_client
      test_large_client
    end

    def log_photo_upload_successes(*)
    end

    def refresh_photo_completion_status(*)
    end

    def clear_photo_summary_cache(*)
    end
  end

  def setup
    @controller = Controller.new
    @controller.test_record = {
      "$id" => { "value" => "123" },
      "テーブルその他" => {
        "type" => "SUBTABLE",
        "value" => [{ "id" => "row1", "value" => { "その他" => { "type" => "FILE", "value" => [] } } }]
      }
    }
    @controller.test_file_key = "new-key"
    @updates = []
    @controller.test_client = Object.new
    @controller.test_large_client = @controller.test_client
    updates = @updates
    @controller.test_client.define_singleton_method(:update) { |*args| updates << args }
    @controller.test_client.define_singleton_method(:create) { |*args| updates << args }
    @photo = ActionDispatch::Http::UploadedFile.new(tempfile: StringIO.new("image"), filename: "photo.jpg", type: "image/jpeg")
  end

  def test_session_probe_returns_noncacheable_status_without_redirect
    denied = dispatch(:upload_session, signed_in: false)
    assert_equal 401, denied.status
    assert_nil denied.location
    assert_includes denied.headers.fetch("Cache-Control"), "no-store"

    allowed = dispatch(:upload_session)
    assert_equal 204, allowed.status
    assert_includes allowed.headers.fetch("Cache-Control"), "no-store"
  end

  def test_signed_out_json_upload_is_rejected_before_csrf_and_record_update
    previous = Controller.allow_forgery_protection
    Controller.allow_forgery_protection = true
    response = dispatch(:update_table_row, method: "PATCH", signed_in: false, data: photo_params)
    assert_equal 401, response.status
    assert_nil response.location
    assert_empty @updates
  ensure
    Controller.allow_forgery_protection = previous
  end

  def test_json_upload_acknowledges_the_attached_photo_without_redirect
    response = dispatch(:update_table_row, method: "PATCH", data: photo_params)
    assert_acknowledged(response)
    assert_equal [["123", { "テーブルその他" => { value: [{ id: "row1", value: { "その他" => { value: [{ fileKey: "new-key" }] } } }] } }]], @updates
  end

  def test_new_photo_row_acknowledges_attachment
    assert_acknowledged(dispatch(:add_table_row, method: "POST", data: photo_params.except(:row_id)))
    assert_equal 2, @updates.first.last.dig("テーブルその他", :value).size
  end

  def test_legacy_request_redirect_is_preserved
    response = dispatch(:update_table_row, method: "PATCH", data: photo_params, json: false)
    assert_equal 302, response.status
    assert_match(%r{/photos/123}, response.location)
  end

  def test_missing_row_or_file_key_cannot_acknowledge_a_photo
    assert_equal 422, dispatch(:update_table_row, method: "PATCH", data: photo_params.merge(row_id: "gone")).status
    @controller.test_file_key = nil
    assert_equal 422, dispatch(:update_table_row, method: "PATCH", data: photo_params).status
    assert_empty @updates
  end

  def test_kintone_record_update_failure_cannot_acknowledge_a_photo
    @controller.test_client.define_singleton_method(:update) { |*| raise Faraday::TimeoutError }
    assert_equal 422, dispatch(:update_table_row, method: "PATCH", data: photo_params).status
  end

  def test_batch_upload_rejects_deleted_destination_before_updating
    data = photo_params.except(:row_id, :photo).merge(table_rows: { "row1" => { photo: @photo }, "gone" => { photo: @photo } })
    assert_equal 422, dispatch(:update_table_rows_batch, method: "PATCH", data: data).status
    assert_empty @updates
  end

  def test_batch_upload_acknowledges_attachment
    data = photo_params.except(:row_id, :photo).merge(table_rows: { "row1" => { photo: @photo } })
    assert_acknowledged(dispatch(:update_table_rows_batch, method: "PATCH", data: data))
  end

  def test_large_photo_add_and_edit_acknowledge_only_attached_photos
    assert_acknowledged(dispatch(:add_large_photo_detail, method: "POST", data: { photo: @photo }))
    assert_acknowledged(dispatch(:update_large_photo_details_batch, method: "PATCH", data: { large_photo_details: { "456" => { photo: @photo } } }))
    @controller.test_file_key = nil
    assert_equal 422, dispatch(:add_large_photo_detail, method: "POST", data: { photo: @photo }).status
  end

  private

  def photo_params
    { table_code: "テーブルその他", row_id: "row1", file_column: "その他", photo: @photo }
  end

  def assert_acknowledged(response)
    assert_equal 200, response.status
    assert_nil response.location
    assert_equal({ "status" => "saved", "uploaded" => 1 }, JSON.parse(response.body))
  end

  def dispatch(action, data: {}, method: "GET", signed_in: true, json: true)
    request = ActionDispatch::TestRequest.create
    request.request_method = method
    request.path_parameters = { controller: "photos", action: action.to_s, id: "123" }
    request.request_parameters = data.with_indifferent_access
    request.headers["X-Test-Signed-In"] = "yes" if signed_in
    request.headers["X-Requested-With"] = "XMLHttpRequest"
    request.headers["Accept"] = "application/json" if json
    controller = Controller.new
    controller.test_record = @controller.test_record
    controller.test_client = @controller.test_client
    controller.test_large_client = @controller.test_large_client
    controller.test_file_key = @controller.test_file_key
    controller.dispatch(action.to_s, request, ActionDispatch::Response.new)
    controller.response
  end
end
