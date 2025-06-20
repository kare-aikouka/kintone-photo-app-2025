# frozen_string_literal: true

module KintoneSync
  class Record < Base
    def find(id)
      api.record.get(app_id, id)
    end

    def create(record)
      api.record.register(app_id, record)
    end

    def update(id, record)
      api.record.update(app_id, id, record)
    end

    def find_list(query: nil, fields: nil, total_count: nil)
      logger.info query.to_s
      api.records.get(app_id, query, fields || [], total_count: total_count)
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
        type = properties[k.to_s].try(:[], 'type')
        is_container = container_type?(type)
        not_op = is_container ? 'not' : ?! if options[:not]
        query << if container_type?(type)
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
      api.records.get(app_id, query, [])['records'].first
    end

    private

    def fetch_all_records(base_query = '')
      res = []
      offset = 0
      limit = 500
      loop do
        query = "#{base_query} limit #{limit} offset #{offset}"
        records = api.records.get(app_id, query, [])['records']
        break unless records
        res += records
        break if records.count < limit
        offset += limit
      end
      res
    end
  end
end
