ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require "minitest/autorun"

class PhotosBlackboardTest < Minitest::Test
  def setup
    @controller = PhotosController.new
  end

  def test_annotations_do_not_remove_later_pile_details
    detail = "11m(5+6)*30,12m(6+6)*3 計33s"
    [",カーボンキュア材。", "、カーボンキュア材。", " カーボンキュア材。", ",特殊材", ",1本追加", ",1本破損", ",1本折れ"].each do |annotation|
      assert_equal detail, sanitize(detail + annotation)
    end
    assert_equal detail, sanitize(detail)
    assert_equal "12m(6+6)*48,13m(6+7)*6 計54s", sanitize("12m(6+6)*48,13m(6+7)*6 計54s")
  end

  def test_existing_cleanup_rules_are_preserved
    assert_equal "6m*60本", sanitize("★6m*60本☆,JIS")
    assert_equal "6m*60本", sanitize("6m*60本→変更予定")
    assert_equal "", sanitize("6m*60本 確認中")
    assert_equal "", sanitize("カーボンキュア材")
  end

  def test_single_length_populates_detail
    assert_equal "6m×60本", piles("杭長1" => "6", "数量1" => "60", "杭長2" => "")
    assert_equal "6.5m×60本", piles("杭長1" => "6.50", "数量1" => "60.0")
  end

  def test_spare_joints_do_not_prevent_single_pile_population
    assert_equal "6m×60本", piles("杭長1" => "6", "数量1" => "60", "ジョイント" => "2")
  end

  def test_existing_detail_takes_priority
    assert_equal "12m(6+6)*30s", piles("打設明細" => "12m(6+6)*30s", "杭長1" => "6", "数量1" => "60")
  end

  def test_nonblank_detail_is_not_replaced_if_cleanup_returns_blank
    assert_equal "", piles("打設明細" => "確認中", "杭長1" => "6", "数量1" => "60")
  end

  def test_second_length_prevents_population
    assert_equal "", piles("杭長1" => "6", "数量1" => "60", "杭長2" => "5")
  end

  def test_missing_or_invalid_material_values_do_not_populate_detail
    [nil, "", "不明", "0", "-1", "NaN", "Infinity"].each do |value|
      assert_equal "", piles("杭長1" => value, "数量1" => "60")
      assert_equal "", piles("杭長1" => "6", "数量1" => value)
    end
    assert_equal "", piles("杭長1" => "6", "数量1" => "1.5")
  end

  private

  def sanitize(value)
    @controller.send(:sanitize_blackboard_piles, value)
  end

  def piles(values)
    record = values.transform_values { |value| { "value" => value } }
    @controller.send(:blackboard_piles_text, record)
  end
end
