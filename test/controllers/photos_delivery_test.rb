ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require "minitest/autorun"

class PhotosDeliveryTest < Minitest::Test
  def setup
    @controller = PhotosController.new
  end

  def test_all_five_lengths_and_joint_have_units_in_grid_order
    values = (1..5).each_with_object({}) do |index, record|
      record["杭長#{index}"] = index.to_s
      record["数量#{index}"] = (index * 10).to_s
    end
    assert_equal ["1m × 10本", "2m × 20本", "3m × 30本", "4m × 40本", "5m × 50本", "ジョイント × 35個"],
                 delivery(values.merge("ジョイント" => "ジョイント", "個数" => "35"))
  end

  def test_blank_cells_stay_empty_and_keep_grid_positions
    assert_equal ["5m × 70本", "", "", "", "", "ジョイント × 35個"],
                 delivery("杭長1" => "5", "数量1" => "70", "杭長2" => "　", "数量2" => " ", "ジョイント" => "ジョイント", "個数" => "35")
    assert_equal Array.new(6, ""), @controller.send(:record_delivery_items, nil)
  end

  def test_partial_values_do_not_create_units_for_blanks
    assert_equal ["5m", "70本", "5.5m × 0本", "", "", "35個"],
                 delivery("杭長1" => "5", "数量2" => "70", "杭長3" => "5.5", "数量3" => "0", "個数" => "35")
  end

  def test_summary_fetch_includes_only_available_delivery_fields
    available = PhotosController::DELIVERY_FIELD_CODES - ["杭長5", "数量5"]
    @controller.define_singleton_method(:available_field_codes) { |_client| available }
    fields = @controller.send(:summary_field_codes, Object.new)
    available.each { |code| assert_includes fields, code }
    refute_includes fields, "杭長5"
    refute_includes fields, "数量5"
  end

  private

  def delivery(values)
    record = values.transform_values { |value| { "value" => value } }
    @controller.send(:record_delivery_items, record)
  end
end
