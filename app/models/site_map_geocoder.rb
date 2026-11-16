class SiteMapGeocoder
  def self.coordinates(latitude, longitude)
    lat = Float(latitude.to_s, exception: false)
    lng = Float(longitude.to_s, exception: false)
    return unless lat&.finite? && lng&.finite?
    return unless lat.between?(-90, 90) && lng.between?(-180, 180)
    return if lat.zero? && lng.zero?

    { lat: lat, lng: lng }
  end

  def initialize(connection: nil, cache: Rails.cache)
    @connection = connection || Faraday.new(url: "https://msearch.gsi.go.jp") do |builder|
      builder.options.open_timeout = 3
      builder.options.timeout = 5
      builder.response :json
    end
    @cache = cache
  end

  def search(value)
    address = value.to_s.strip
    return if address.blank? || address.length > 200

    @cache.fetch(["site-map-geocoder-v1", address], expires_in: 7.days, skip_nil: true) do
      locality = address.sub(/(?<=丁目).+\z/, "").sub(/[0-9０-９]+(?:[-－][0-9０-９]+)*(?:番地?|号)?(?:の内)?\z/, "")
      result = nil
      [address, locality].uniq.each do |query|
        next if query.blank?

        result = search_address(query)
        break if result
      end
      result
    end
  end

  private

  def search_address(address)
    response = @connection.get("/address-search/AddressSearch", q: address)
    raise Faraday::Error, "Address search failed" unless response.success?
    return unless response.body.is_a?(Array)

    response.body.each do |feature|
      next unless feature.is_a?(Hash) && feature.dig("geometry", "type") == "Point"

      position = feature.dig("geometry", "coordinates")
      next unless position.is_a?(Array) && position.length == 2

      point = self.class.coordinates(position[1], position[0])
      return point.merge(label: feature.dig("properties", "title").to_s) if point
    end
    nil
  end
end
