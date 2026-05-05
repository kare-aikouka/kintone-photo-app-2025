require 'base64'
require 'json'
require 'net/http'
require 'securerandom'
require 'tempfile'
require 'uri'

module KintoneSync
  class File < Base
    def download(file_key)
      response = raw_connection.get(api_url('file.json'), fileKey: file_key)
      raise "Kintone file download failed: #{response.status} #{response.body}" unless response.success?

      response.body
    end

    def upload(params)
      filename = params[:filename].presence || 'upload.jpg'
      content_type = params[:content_type].presence || 'application/octet-stream'
      boundary = "----kintone-photo-#{SecureRandom.hex(12)}"
      body = multipart_body(boundary, filename, content_type, params[:data])
      uri = URI("https://#{host}#{api_url('file.json')}")
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
      auth_headers.each { |key, value| request[key] = value }
      request.body = body

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 30) do |http|
        http.request(request)
      end
      raise "Kintone file upload failed: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body).fetch('fileKey')
    end

    private

    def raw_connection
      @raw_connection ||= Faraday.new(url: "https://#{host}") do |builder|
        builder.options.open_timeout = 5
        builder.options.timeout = 30
        configure_auth_headers(builder)
        builder.adapter Faraday.default_adapter
      end
    end

    def host
      ENV['KINTONE_HOST'].to_s.strip.sub(%r{\Ahttps?://}, '').sub(%r{/+\z}, '')
    end

    def api_url(path)
      base = guest_space_id.present? ? "/k/guest/#{guest_space_id}/v1" : "/k/v1"
      "#{base}/#{path}"
    end

    def configure_auth_headers(builder)
      auth_headers.each { |key, value| builder.headers[key] = value }

      return unless ENV['KINTONE_BASIC_USER'].present? && ENV['KINTONE_BASIC_PASS'].present?

      builder.request :authorization, :basic, ENV['KINTONE_BASIC_USER'], ENV['KINTONE_BASIC_PASS']
    end

    def auth_headers
      headers = {}
      token = ENV["KINTONE_API_TOKEN_#{app_id}"].presence || ENV['KINTONE_API_TOKEN'].presence
      if token.present?
        headers['X-Cybozu-API-Token'] = token
      elsif ENV['KINTONE_USER'].present? && ENV['KINTONE_PASS'].present?
        headers['X-Cybozu-Authorization'] = Base64.strict_encode64("#{ENV['KINTONE_USER']}:#{ENV['KINTONE_PASS']}")
      end

      if ENV['KINTONE_BASIC_USER'].present? && ENV['KINTONE_BASIC_PASS'].present?
        headers['Authorization'] = "Basic #{Base64.strict_encode64("#{ENV['KINTONE_BASIC_USER']}:#{ENV['KINTONE_BASIC_PASS']}")}"
      end
      headers
    end

    def multipart_body(boundary, filename, content_type, data)
      body = +"".b
      body << "--#{boundary}\r\n".b
      body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n".b
      body << "Content-Type: #{content_type}\r\n\r\n".b
      body << data.to_s.b
      body << "\r\n--#{boundary}--\r\n".b
      body
    end
  end
end
