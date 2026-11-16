ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require "minitest/autorun"

class PhotosMapPositionTest < Minitest::Test
  class Controller < PhotosController
    attr_accessor :test_record, :test_client, :rendered

    def render(**options)
      self.rendered = options
    end

    private

    def photo_record(_id)
      test_record
    end

    def photos_record_client
      test_client
    end
  end

  def setup
    @controller = Controller.new
    @controller.test_record = {
      "B地点緯度" => { "value" => "43" },
      "B地点経度" => { "value" => "141" },
      "住所" => { "value" => "既存住所" }
    }
    @updates = []
    updates = @updates
    client = Object.new
    client.define_singleton_method(:update) { |*args| updates << args }
    @controller.test_client = client
  end

  def test_saves_only_the_two_coordinates_on_the_selected_record
    save("43.1234567", "141.2345678")
    assert_equal [["123", {
      "B地点緯度" => { value: "43.1234567" },
      "B地点経度" => { value: "141.2345678" }
    }]], @updates
    assert_equal "success", @controller.rendered[:json][:status]
  end

  def test_rejects_invalid_or_missing_coordinates_without_updating
    [[nil, "141"], ["43", nil], ["NaN", "141"], ["91", "141"], ["43", "181"], ["0", "0"]].each do |lat, lng|
      save(lat, lng)
      assert_equal :unprocessable_entity, @controller.rendered[:status]
    end
    assert_empty @updates
  end

  def test_does_not_update_if_either_coordinate_field_is_missing
    @controller.test_record.delete("B地点経度")
    save("43", "141")
    assert_equal :unprocessable_entity, @controller.rendered[:status]
    assert_empty @updates
  end

  def test_missing_record_does_not_update_anything
    @controller.test_record = nil
    save("43", "141")
    assert_equal :unprocessable_entity, @controller.rendered[:status]
    assert_empty @updates
  end

  def test_update_failure_is_not_reported_as_success
    @controller.test_client.define_singleton_method(:update) { |*_args| raise Faraday::TimeoutError }
    save("43", "141")
    assert_equal :unprocessable_entity, @controller.rendered[:status]
    refute_equal "success", @controller.rendered[:json][:status]
  end

  private

  def save(lat, lng)
    @controller.params = ActionController::Parameters.new(id: "123", lat: lat, lng: lng)
    @controller.save_map_location
  end
end
