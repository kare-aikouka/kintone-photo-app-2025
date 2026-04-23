# frozen_string_literal: true

module KintoneSync
  class Record < Base
    def find(id)
      client.get("record.json", { app: app_id, id: id })
    end

    def create(record)
      client.post("record.json", { app: app_id, record: record })
    end

    def update(id, record)
      client.put("record.json", { app: app_id, id: id, record: record })
    end

    def find_list(query: nil, fields: nil, total_count: nil)
      logger.info query.to_s
      params = { app: app_id, query: query }
      params[:fields] = fields if fields
      params[:totalCount] = total_count if total_count
      client.get("records.json", params)
    end

    CONTAINER_TYPES = %w(DROP_DOWN CHECK_BOX RADIO_BUTTON).freeze

    def container_type?(type)
      CONTAINER_TYPES.include?(type)
    end

    def where(cond, options = {})
      fetch_all_records(where_query(cond, options))
    end

    def where_query(cond, options = {})
      query = ''.dup
      cond.each do |k, v|
        query << ' and ' unless query == ''
        is_container = configured_container_field?(k) || container_type?(field_type(k))
        not_op = is_container ? 'not' : ?! if options[:not]
        query << if is_container
                   if v.is_a?(Array)
                     "#{k} #{not_op} in (\"#{v.join('","')}\")"
                   else
                     "#{k} #{not_op} in (\"#{v}\")"
                   end
                 else
                   "#{k} #{not_op}= \"#{v}\""
                 end
      end
      if options[:order_by]
        query << " order by #{options[:order_by]}"
      end
      query
    end

    def find_by(cond, options = {})
      base_query = where_query(cond, options)
      query = "#{base_query} limit 1 offset 0"
      records = client.get("records.json", { app: app_id, query: query, fields: [] })['records']
      records&.first
    end

    private

    def field_type(field_code)
      properties[field_code.to_s].try(:[], 'type')
    rescue StandardError => e
      logger.warn("Kintone form fields lookup skipped: #{e.class}: #{e.message}")
      nil
    end

    def configured_container_field?(field_code)
      container_fields.include?(field_code.to_s)
    end

    def container_fields
      ENV.fetch('KINTONE_CONTAINER_FIELDS', 'エリア').split(',').map(&:strip)
    end

    def fetch_all_records(base_query = '')
      res = []
      offset = 0
      limit = 500
      loop do
        query = "#{base_query} limit #{limit} offset #{offset}"
        response = client.get("records.json", { app: app_id, query: query, fields: [] })
        records = response['records']
        break unless records
        res += records
        break if records.count < limit
        offset += limit
      end
      res
    end
  end
end
