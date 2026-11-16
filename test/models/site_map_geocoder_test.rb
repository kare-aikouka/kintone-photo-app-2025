ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require "minitest/autorun"

class SiteMapGeocoderTest < Minitest::Test
  def test_valid_b_point_coordinates
    assert_equal({ lat: 43.1, lng: 141.2 }, SiteMapGeocoder.coordinates("43.1", "141.2"))
  end

  def test_missing_or_invalid_coordinates_are_not_used
    [[nil, "141"], ["", "141"], ["43", ""], ["NaN", "141"], ["91", "141"], ["43", "181"], ["0", "0"]].each do |latitude, longitude|
      assert_nil SiteMapGeocoder.coordinates(latitude, longitude)
    end
  end

  def test_search_returns_coordinates_in_latitude_longitude_order_and_caches_results
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get(search_path("札幌市中央区")) { response([feature]) }
    end
    geocoder = build_geocoder(stubs)
    expected = { lat: 43.1, lng: 141.2, label: "札幌市中央区" }
    assert_equal expected, geocoder.search("札幌市中央区")
    assert_equal expected, geocoder.search("札幌市中央区")
    stubs.verify_stubbed_calls
  end

  def test_search_falls_back_to_chome_when_full_address_is_not_found
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get(search_path("札幌市中央区北一条一丁目99-1")) { response([]) }
      stub.get(search_path("札幌市中央区北一条一丁目")) { response([feature]) }
    end
    assert_equal 43.1, build_geocoder(stubs).search("札幌市中央区北一条一丁目99-1")[:lat]
    stubs.verify_stubbed_calls
  end

  def test_invalid_and_missing_search_results_do_not_create_a_pin
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get(search_path("不明な場所")) { response([feature([999, 999])]) }
    end
    assert_nil build_geocoder(stubs).search("不明な場所")
    stubs.verify_stubbed_calls
  end

  def test_empty_or_long_searches_do_not_call_external_service
    geocoder = build_geocoder(Faraday::Adapter::Test::Stubs.new)
    assert_nil geocoder.search("")
    assert_nil geocoder.search("a" * 201)
  end

  def test_service_failure_is_reported
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get(search_path("札幌市")) { [503, {}, ""] }
    end
    assert_raises(Faraday::Error) { build_geocoder(stubs).search("札幌市") }
  end

  private

  def search_path(address)
    "/address-search/AddressSearch?#{URI.encode_www_form(q: address)}"
  end

  def feature(coordinates = [141.2, 43.1])
    { geometry: { type: "Point", coordinates: coordinates }, properties: { title: "札幌市中央区" } }
  end

  def response(features)
    [200, { "Content-Type" => "application/json" }, features.to_json]
  end

  def build_geocoder(stubs)
    connection = Faraday.new do |builder|
      builder.response :json
      builder.adapter :test, stubs
    end
    SiteMapGeocoder.new(connection: connection, cache: ActiveSupport::Cache::MemoryStore.new)
  end
end
