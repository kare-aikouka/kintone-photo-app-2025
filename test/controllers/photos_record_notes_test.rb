ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require "minitest/autorun"

class PhotosRecordNotesTest < Minitest::Test
  def setup
    @controller = PhotosController.new
  end

  def test_notes_are_in_field_order_and_exclude_note_three
    record = {
      "備考4" => { "value" => "単車が短い車" },
      "備考2" => { "value" => "搬入連絡" },
      "備考1" => { "value" => "手配済み" },
      "備考3" => { "value" => "打設明細として別に使用" }
    }
    assert_equal [
      { label: "備考1", text: "手配済み" },
      { label: "備考2", text: "搬入連絡" },
      { label: "備考4", text: "単車が短い車" }
    ], @controller.send(:record_notes, record)
  end

  def test_blank_notes_are_omitted
    assert_empty @controller.send(:record_notes, nil)
    assert_empty @controller.send(:record_notes, { "備考1" => { "value" => " " }, "備考2" => { "value" => nil } })
  end

  def test_full_text_and_line_breaks_are_preserved
    text = "搬入前に連絡してください。\n" + "長い備考です。" * 50
    assert_equal text, @controller.send(:record_notes, { "備考4" => { "value" => text } }).first[:text]
  end

  def test_summary_fetch_includes_available_note_fields
    @controller.define_singleton_method(:available_field_codes) { |_client| %w[備考1 備考4] }
    fields = @controller.send(:summary_field_codes, Object.new)
    assert_includes fields, "備考1"
    assert_includes fields, "備考4"
    refute_includes fields, "備考2"
    refute_includes fields, "備考3"
  end
end
